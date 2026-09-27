# CrushReply Daraja API

This API starts a KSh 100 M-Pesa STK Push, accepts the Daraja result callback, and records one calendar month of Premium access after a successful payment. It is separate from Flutter because Daraja credentials and callback processing must stay on a server.

## Deploy on Render

1. Push this project to a GitHub repository.
2. In Render, create a Blueprint from that repository and apply `render.yaml`. The API is a separate service from GitHub Pages and uses a persistent disk for SQLite.
3. In the Render service environment, set `DARAJA_CONSUMER_KEY`, `DARAJA_CONSUMER_SECRET`, `DARAJA_PASSKEY`, and a long random `DARAJA_CALLBACK_TOKEN`. Set `ALLOWED_ORIGINS` to the exact GitHub Pages origin, for example `https://your-user.github.io`.
4. Render provides `RENDER_EXTERNAL_URL`; the API uses it to construct the callback URL. Otherwise set `PUBLIC_API_URL` to the public HTTPS API origin.
5. Start with Daraja sandbox credentials and `DARAJA_ENV=sandbox`. Use the sandbox shortcode/passkey and test phone/account from the Daraja developer portal.
6. Only after Safaricom approves production access, use production credentials and set `DARAJA_ENV=production`.
7. Check `https://<api-host>/api/health` for `{"ok":true}`.

Never commit `.env` or place Daraja credentials in Flutter, GitHub Pages, or the browser. `DARAJA_CALLBACK_TOKEN` is a secret callback path component; it is not a substitute for reconciling payments against Safaricom transaction records in a production finance workflow.

## Configure Flutter

Set the GitHub repository Actions variable `PAYMENT_API_BASE_URL` to the Render API origin without a trailing slash. The Pages workflow passes it to Flutter at build time. For local runs:

```powershell
flutter run --dart-define=PAYMENT_API_BASE_URL=https://your-api-host.onrender.com
```

Enable GitHub Pages with **Build and deployment: GitHub Actions**, then push to `main`. Flutter Web is installable as a PWA in supported browsers; GitHub Pages does not create or sign an Android APK. Android builds still come from `flutter build apk` or `flutter build appbundle` and require release signing.

## Subscription behavior and limitations

- The server fixes the price at KSh 100; the app cannot choose another amount.
- Each successful payment adds one calendar month. A user must pay again to renew; there are no automatic monthly charges.
- The M-Pesa phone number is retained in the payment/subscription database so renewals extend the same subscription.
- The app persists verified expiry locally for offline use. Device preferences are not tamper-resistant, and this MVP has no user account, phone ownership challenge, or cross-device entitlement restore. Add authenticated identity and server-side entitlement checks before relying on this as a robust subscription platform.
- Test callbacks over public HTTPS with Daraja sandbox before live transactions. Review Safaricom requirements, customer support/refund handling, privacy disclosures, and data retention before launch.
