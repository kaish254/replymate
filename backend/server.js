import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import Database from 'better-sqlite3';
import cors from 'cors';
import express from 'express';
import { rateLimit } from 'express-rate-limit';

const app = express();
app.set('trust proxy', 1);
app.use(express.json({ limit: '32kb' }));

const allowedOrigins = (process.env.ALLOWED_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);
app.use(cors({
  origin(origin, callback) {
    if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
    return callback(new Error('Origin is not allowed'));
  },
}));

const apiLimiter = rateLimit({ windowMs: 60_000, limit: 20, standardHeaders: true, legacyHeaders: false });
app.use('/api', apiLimiter);

const amountKes = 100;
const shortcode = requiredEnv('DARAJA_BUSINESS_SHORT_CODE');
const passkey = requiredEnv('DARAJA_PASSKEY');
const callbackToken = requiredEnv('DARAJA_CALLBACK_TOKEN');
const publicApiUrl = (process.env.PUBLIC_API_URL ?? process.env.RENDER_EXTERNAL_URL ?? '').replace(/\/$/, '');
if (!publicApiUrl) throw new Error('Set PUBLIC_API_URL to the public HTTPS URL of this API.');
const darajaBaseUrl = process.env.DARAJA_ENV === 'production'
  ? 'https://api.safaricom.co.ke'
  : 'https://sandbox.safaricom.co.ke';
const darajaCallbackUrl = `${publicApiUrl}/api/daraja/callback/${encodeURIComponent(callbackToken)}`;

const databasePath = process.env.DATABASE_PATH ?? path.join(path.dirname(fileURLToPath(import.meta.url)), 'data', 'crushreply.sqlite');
mkdirSync(path.dirname(path.resolve(databasePath)), { recursive: true });
const database = new Database(databasePath);
database.pragma('journal_mode = WAL');
database.exec(`
  CREATE TABLE IF NOT EXISTS payments (
    checkout_request_id TEXT PRIMARY KEY,
    status_token_hash TEXT NOT NULL,
    phone TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    receipt TEXT,
    result_description TEXT,
    created_at TEXT NOT NULL,
    paid_at TEXT,
    expires_at TEXT
  );
  CREATE TABLE IF NOT EXISTS subscriptions (
    phone TEXT PRIMARY KEY,
    expires_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );
`);

const insertPayment = database.prepare(`
  INSERT INTO payments (checkout_request_id, status_token_hash, phone, created_at)
  VALUES (?, ?, ?, ?)
`);
const findPayment = database.prepare('SELECT * FROM payments WHERE checkout_request_id = ?');
const paymentByPhoneExpiry = database.prepare('SELECT expires_at FROM subscriptions WHERE phone = ?');

app.get('/api/health', (_request, response) => response.json({ ok: true }));

app.post('/api/payments/stk', async (request, response) => {
  const phone = normalizeKenyanPhone(request.body?.phone);
  if (!phone) return response.status(400).json({ error: 'Enter a valid Safaricom number, for example 0712345678.' });

  try {
    const accessToken = await getDarajaAccessToken();
    const timestamp = nairobiTimestamp();
    const password = Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');
    const darajaResponse = await fetch(`${darajaBaseUrl}/mpesa/stkpush/v1/processrequest`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        BusinessShortCode: shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: process.env.DARAJA_TRANSACTION_TYPE ?? 'CustomerPayBillOnline',
        Amount: amountKes,
        PartyA: phone,
        PartyB: shortcode,
        PhoneNumber: phone,
        CallBackURL: darajaCallbackUrl,
        AccountReference: 'CrushReply Premium',
        TransactionDesc: 'CrushReply monthly premium',
      }),
      signal: AbortSignal.timeout(20_000),
    });
    const result = await darajaResponse.json();
    if (!darajaResponse.ok || result.ResponseCode !== '0' || !result.CheckoutRequestID) {
      console.error('Daraja STK request rejected:', result.errorMessage ?? result.ResponseDescription ?? darajaResponse.status);
      return response.status(502).json({ error: 'M-Pesa could not start the payment. Check the number and try again.' });
    }

    const statusToken = randomBytes(32).toString('base64url');
    insertPayment.run(
      result.CheckoutRequestID,
      sha256(statusToken),
      phone,
      new Date().toISOString(),
    );
    return response.status(202).json({
      checkoutRequestId: result.CheckoutRequestID,
      statusToken,
      customerMessage: result.CustomerMessage ?? 'Approve the M-Pesa prompt on your phone.',
      amountKes,
    });
  } catch (error) {
    console.error('STK request failed:', error.message);
    return response.status(502).json({ error: 'Payment service is temporarily unavailable.' });
  }
});

app.get('/api/payments/:checkoutRequestId', (request, response) => {
  const token = request.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return response.status(401).json({ error: 'Payment status token is required.' });

  const payment = findPayment.get(request.params.checkoutRequestId);
  if (!payment || !safeEqual(sha256(token), payment.status_token_hash)) {
    return response.status(404).json({ error: 'Payment request not found.' });
  }

  const subscription = paymentByPhoneExpiry.get(payment.phone);
  return response.json({
    status: payment.status,
    receipt: payment.receipt,
    expiresAt: payment.expires_at ?? subscription?.expires_at ?? null,
    message: payment.result_description,
  });
});

app.post('/api/daraja/callback/:token', (request, response) => {
  if (!safeEqual(request.params.token, callbackToken)) return response.sendStatus(404);

  const callback = request.body?.Body?.stkCallback;
  if (!callback?.CheckoutRequestID || !Number.isInteger(callback.ResultCode)) {
    return response.status(400).json({ ResultCode: 1, ResultDesc: 'Invalid callback payload.' });
  }

  const payment = findPayment.get(callback.CheckoutRequestID);
  if (!payment) return response.json({ ResultCode: 0, ResultDesc: 'Callback received.' });
  if (payment.status !== 'pending') return response.json({ ResultCode: 0, ResultDesc: 'Callback already processed.' });

  if (callback.ResultCode !== 0) {
    database.prepare(`UPDATE payments SET status = 'failed', result_description = ? WHERE checkout_request_id = ?`)
      .run(callback.ResultDesc ?? 'Payment was not completed.', callback.CheckoutRequestID);
    return response.json({ ResultCode: 0, ResultDesc: 'Callback received.' });
  }

  const metadata = new Map((callback.CallbackMetadata?.Item ?? []).map((item) => [item.Name, item.Value]));
  if (Number(metadata.get('Amount')) !== amountKes || normalizeKenyanPhone(String(metadata.get('PhoneNumber') ?? '')) !== payment.phone) {
    database.prepare(`UPDATE payments SET status = 'failed', result_description = ? WHERE checkout_request_id = ?`)
      .run('Payment amount or phone did not match the request.', callback.CheckoutRequestID);
    return response.json({ ResultCode: 0, ResultDesc: 'Callback received.' });
  }
  const receipt = metadata.get('MpesaReceiptNumber');
  const paidAt = new Date().toISOString();
  const priorExpiry = paymentByPhoneExpiry.get(payment.phone)?.expires_at;
  const start = priorExpiry && new Date(priorExpiry) > new Date() ? new Date(priorExpiry) : new Date();
  const expiresAt = addOneCalendarMonth(start).toISOString();

  const completePayment = database.transaction(() => {
    database.prepare(`
      UPDATE payments
      SET status = 'paid', receipt = ?, result_description = ?, paid_at = ?, expires_at = ?
      WHERE checkout_request_id = ? AND status = 'pending'
    `).run(receipt ?? null, callback.ResultDesc ?? 'Payment successful.', paidAt, expiresAt, callback.CheckoutRequestID);
    database.prepare(`
      INSERT INTO subscriptions (phone, expires_at, updated_at) VALUES (?, ?, ?)
      ON CONFLICT(phone) DO UPDATE SET expires_at = excluded.expires_at, updated_at = excluded.updated_at
    `).run(payment.phone, expiresAt, paidAt);
  });
  completePayment();
  return response.json({ ResultCode: 0, ResultDesc: 'Callback received.' });
});

app.use((error, _request, response, _next) => {
  if (error.message === 'Origin is not allowed') return response.status(403).json({ error: error.message });
  console.error('Unhandled API error:', error.message);
  return response.status(500).json({ error: 'Unexpected server error.' });
});

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => console.log(`CrushReply Daraja API listening on ${port}`));

async function getDarajaAccessToken() {
  const consumerKey = requiredEnv('DARAJA_CONSUMER_KEY');
  const consumerSecret = requiredEnv('DARAJA_CONSUMER_SECRET');
  const credentials = Buffer.from(`${consumerKey}:${consumerSecret}`).toString('base64');
  const result = await fetch(`${darajaBaseUrl}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${credentials}` },
    signal: AbortSignal.timeout(15_000),
  });
  if (!result.ok) throw new Error(`Daraja OAuth failed with status ${result.status}`);
  return (await result.json()).access_token;
}

function normalizeKenyanPhone(value) {
  if (typeof value !== 'string') return null;
  const digits = value.replace(/\D/g, '');
  const national = digits.startsWith('254') ? digits.slice(3) : digits.startsWith('0') ? digits.slice(1) : digits;
  if (!/^(7|1)\d{8}$/.test(national)) return null;
  return `254${national}`;
}

function nairobiTimestamp() {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Africa/Nairobi',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(({ type, value }) => [type, value]));
  return `${values.year}${values.month}${values.day}${values.hour}${values.minute}${values.second}`;
}

function addOneCalendarMonth(date) {
  const next = new Date(date);
  const day = next.getUTCDate();
  next.setUTCDate(1);
  next.setUTCMonth(next.getUTCMonth() + 1);
  const lastDay = new Date(Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0)).getUTCDate();
  next.setUTCDate(Math.min(day, lastDay));
  return next;
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function safeEqual(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') return false;
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}