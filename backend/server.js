import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import Database from 'better-sqlite3';
import cors from 'cors';
import express from 'express';
import { rateLimit } from 'express-rate-limit';

const app = express();
app.set('trust proxy', 1);

/*
 * Paystack webhook signature verification needs the raw request body.
 * We keep a copy of the raw bytes while still parsing normal JSON.
 */
app.use(express.json({
  limit: '32kb',
  verify: (request, _response, buffer) => {
    request.rawBody = Buffer.from(buffer);
  },
}));

const allowedOrigins = (process.env.ALLOWED_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

app.use(cors({
  origin(origin, callback) {
    if (!origin || allowedOrigins.includes(origin)) {
      return callback(null, true);
    }

    return callback(new Error('Origin is not allowed'));
  },
}));

const apiLimiter = rateLimit({
  windowMs: 60_000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/api', apiLimiter);

const amountKes = 100;
const amountSubunit = amountKes * 100;

const paystackSecretKey = requiredEnv('PAYSTACK_SECRET_KEY');

const publicApiUrl = (
  process.env.PUBLIC_API_URL ??
  process.env.RENDER_EXTERNAL_URL ??
  ''
).replace(/\/$/, '');

if (!publicApiUrl) {
  throw new Error('Set PUBLIC_API_URL to the public HTTPS URL of this API.');
}

const paystackWebhookUrl = `${publicApiUrl}/api/paystack/webhook`;

const databasePath =
  process.env.DATABASE_PATH ??
  path.join(
    path.dirname(fileURLToPath(import.meta.url)),
    'data',
    'crushreply.sqlite',
  );

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
  INSERT INTO payments (
    checkout_request_id,
    status_token_hash,
    phone,
    created_at
  )
  VALUES (?, ?, ?, ?)
`);

const findPayment = database.prepare(`
  SELECT * FROM payments
  WHERE checkout_request_id = ?
`);

const paymentByPhoneExpiry = database.prepare(`
  SELECT expires_at
  FROM subscriptions
  WHERE phone = ?
`);

app.get('/api/health', (_request, response) => {
  return response.json({
    ok: true,
    paymentProvider: 'paystack',
  });
});

/*
 * Start a KSh 100 Premium M-PESA payment.
 *
 * Flutter continues using:
 * POST /api/payments/stk
 *
 * This keeps the existing app endpoint so we don't have to redesign
 * the Flutter payment service immediately.
 */
app.post('/api/payments/stk', async (request, response) => {
  const phone = normalizeKenyanPhone(request.body?.phone);

  if (!phone) {
    return response.status(400).json({
      error: 'Enter a valid Kenyan phone number, for example 0712345678.',
    });
  }

  /*
   * Paystack requires an email for the Charge API.
   *
   * We accept one from Flutter if supplied. Until Flutter is updated,
   * use a deterministic internal email based on the phone number.
   *
   * This is NOT used as a password or secret.
   */
  const suppliedEmail = request.body?.email;
  const email =
    typeof suppliedEmail === 'string' && isValidEmail(suppliedEmail)
      ? suppliedEmail.trim().toLowerCase()
      : `customer-${phone}@replymate.app`;

  const reference = createPaymentReference();
  const statusToken = randomBytes(32).toString('base64url');

  try {
    const paystackResponse = await fetch(
      'https://api.paystack.co/charge',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${paystackSecretKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          amount: amountSubunit,
          currency: 'KES',
          reference,
          mobile_money: {
            phone: `+${phone}`,
            provider: 'mpesa',
          },
          metadata: {
            product: 'ReplyMate Premium',
            phone,
            amount_kes: amountKes,
          },
        }),
        signal: AbortSignal.timeout(20_000),
      },
    );

    const result = await paystackResponse.json();

    if (!paystackResponse.ok || !result.status || !result.data?.reference) {
      console.error(
        'Paystack charge rejected:',
        result.message ?? paystackResponse.status,
      );

      return response.status(502).json({
        error: 'M-PESA payment could not be started. Please try again.',
      });
    }

    const paystackReference = result.data.reference;

    insertPayment.run(
      paystackReference,
      sha256(statusToken),
      phone,
      new Date().toISOString(),
    );

    return response.status(202).json({
      checkoutRequestId: paystackReference,
      statusToken,
      customerMessage:
        result.data.display_text ??
        'Check your phone and approve the M-PESA payment.',
      amountKes,
      status: result.data.status ?? 'pending',
    });
  } catch (error) {
    console.error('Paystack charge failed:', error.message);

    return response.status(502).json({
      error: 'Payment service is temporarily unavailable.',
    });
  }
});

/*
 * Flutter polls this endpoint using the status token.
 */
app.get(
  '/api/payments/:checkoutRequestId',
  (request, response) => {
    const token = request
      .get('authorization')
      ?.replace(/^Bearer\s+/i, '');

    if (!token) {
      return response.status(401).json({
        error: 'Payment status token is required.',
      });
    }

    const payment = findPayment.get(
      request.params.checkoutRequestId,
    );

    if (
      !payment ||
      !safeEqual(
        sha256(token),
        payment.status_token_hash,
      )
    ) {
      return response.status(404).json({
        error: 'Payment request not found.',
      });
    }

    const subscription = paymentByPhoneExpiry.get(payment.phone);

    return response.json({
      status: payment.status,
      receipt: payment.receipt,
      expiresAt:
        payment.expires_at ??
        subscription?.expires_at ??
        null,
      message: payment.result_description,
    });
  },
);

/*
 * Paystack webhook.
 *
 * Paystack sends charge.success when the M-PESA payment succeeds.
 * We verify the x-paystack-signature BEFORE processing the event.
 */
app.post('/api/paystack/webhook', (request, response) => {
  const signature = request.get('x-paystack-signature');

  if (!signature || !request.rawBody) {
    return response.sendStatus(401);
  }

  const expectedSignature = createHmac(
    'sha512',
    paystackSecretKey,
  )
    .update(request.rawBody)
    .digest('hex');

  if (!safeEqual(signature, expectedSignature)) {
    console.error('Invalid Paystack webhook signature.');
    return response.sendStatus(401);
  }

  /*
   * Acknowledge the webhook quickly.
   */
  response.sendStatus(200);

  const event = request.body;

  if (event?.event !== 'charge.success') {
    return;
  }

  const charge = event.data;

  if (!charge?.reference) {
    return;
  }

  const payment = findPayment.get(charge.reference);

  if (!payment) {
    console.error(
      'Paystack webhook reference not found:',
      charge.reference,
    );
    return;
  }

  if (payment.status !== 'pending') {
    return;
  }

  /*
   * Verify the important payment details before activating Premium.
   */
  const paidAmount = Number(charge.amount);
  const currency = String(charge.currency ?? '').toUpperCase();

  if (paidAmount !== amountSubunit || currency !== 'KES') {
    database
      .prepare(`
        UPDATE payments
        SET
          status = 'failed',
          result_description = ?
        WHERE checkout_request_id = ?
      `)
      .run(
        'Payment amount or currency did not match the requested Premium plan.',
        charge.reference,
      );

    return;
  }

  const metadataPhone =
    charge.metadata?.phone ??
    charge.customer?.metadata?.phone ??
    null;

  if (
    metadataPhone &&
    normalizeKenyanPhone(String(metadataPhone)) !== payment.phone
  ) {
    database
      .prepare(`
        UPDATE payments
        SET
          status = 'failed',
          result_description = ?
        WHERE checkout_request_id = ?
      `)
      .run(
        'Payment phone number did not match the payment request.',
        charge.reference,
      );

    return;
  }

  const receipt =
    charge.receipt_number ??
    charge.reference ??
    null;

  const paidAt =
    charge.paid_at ??
    new Date().toISOString();

  const priorExpiry =
    paymentByPhoneExpiry.get(payment.phone)?.expires_at;

  const now = new Date();

  const start =
    priorExpiry && new Date(priorExpiry) > now
      ? new Date(priorExpiry)
      : now;

  const expiresAt =
    addOneCalendarMonth(start).toISOString();

  const completePayment = database.transaction(() => {
    database
      .prepare(`
        UPDATE payments
        SET
          status = 'paid',
          receipt = ?,
          result_description = ?,
          paid_at = ?,
          expires_at = ?
        WHERE checkout_request_id = ?
          AND status = 'pending'
      `)
      .run(
        receipt,
        charge.gateway_response ??
          'Payment successful.',
        paidAt,
        expiresAt,
        charge.reference,
      );

    database
      .prepare(`
        INSERT INTO subscriptions (
          phone,
          expires_at,
          updated_at
        )
        VALUES (?, ?, ?)
        ON CONFLICT(phone)
        DO UPDATE SET
          expires_at = excluded.expires_at,
          updated_at = excluded.updated_at
      `)
      .run(
        payment.phone,
        expiresAt,
        paidAt,
      );
  });

  completePayment();

  console.log(
    `Premium activated: ${payment.phone} until ${expiresAt}`,
  );
});

/*
 * Error handling.
 */
app.use((error, _request, response, _next) => {
  if (error.message === 'Origin is not allowed') {
    return response.status(403).json({
      error: error.message,
    });
  }

  console.error(
    'Unhandled API error:',
    error.message,
  );

  return response.status(500).json({
    error: 'Unexpected server error.',
  });
});

const port = Number(
  process.env.PORT ?? 3000,
);

app.listen(port, () => {
  console.log(
    `ReplyMate Paystack API listening on ${port}`,
  );
});

/* ---------------- Helper functions ---------------- */

function createPaymentReference() {
  return `RM-${Date.now()}-${randomBytes(6).toString('hex')}`;
}

function normalizeKenyanPhone(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const digits = value.replace(/\D/g, '');

  const national =
    digits.startsWith('254')
      ? digits.slice(3)
      : digits.startsWith('0')
        ? digits.slice(1)
        : digits;

  if (!/^(7|1)\d{8}$/.test(national)) {
    return null;
  }

  return `254${national}`;
}

function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function addOneCalendarMonth(date) {
  const next = new Date(date);
  const day = next.getUTCDate();

  next.setUTCDate(1);
  next.setUTCMonth(
    next.getUTCMonth() + 1,
  );

  const lastDay =
    new Date(
      Date.UTC(
        next.getUTCFullYear(),
        next.getUTCMonth() + 1,
        0,
      ),
    ).getUTCDate();

  next.setUTCDate(
    Math.min(day, lastDay),
  );

  return next;
}

function sha256(value) {
  return createHash('sha256')
    .update(value)
    .digest('hex');
}

function safeEqual(left, right) {
  if (
    typeof left !== 'string' ||
    typeof right !== 'string'
  ) {
    return false;
  }

  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  return (
    leftBuffer.length === rightBuffer.length &&
    timingSafeEqual(
      leftBuffer,
      rightBuffer,
    )
  );
}

function requiredEnv(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(
      `Missing required environment variable: ${name}`,
    );
  }

  return value;
}