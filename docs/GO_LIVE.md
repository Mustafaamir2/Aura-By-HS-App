# Aura by HS — going live (app + API + payments)

Three products, **one database**:

```
                        ┌──────────────── Supabase (free) ────────────────┐
  POS (React) ─────────►│ Postgres: bookings, bills, stock, staff, chats,  │
  Cloudflare Pages      │ online payments · Auth: Google + email · Storage │
                        └──────────▲──────────────────────▲───────────────┘
                                   │ service key          │ sign-in only
  Website (aurabyhs.pk) ──► Aura API (Python, Render) ◄── Flutter app (Play Store / App Store)
                                   │
                                   └──► JazzCash / Easypaisa hosted checkout (wallet + card)
```

Do the POS's own guide first (`Aura-By-HS-POS/docs/GO_LIVE.md`) — it creates the Supabase project,
the tables and the owner login. This guide adds the app, the API and payments on top.

**Time:** about an hour, plus the days the payment companies take to approve merchant accounts.
Everything works in **test mode** meanwhile.

---

## 1. Supabase settings for customers (5 minutes)

In the same project the POS uses:

1. **SQL Editor** → run the latest `Aura-By-HS-POS/supabase/schema.sql` again. It adds the app's tables
   (`online_payments`, `messages`, `customer_accounts`, `announcements`) and two private file buckets
   (`payment-slips`, `chat-images`). Safe to re-run; nothing is deleted.
2. **Authentication → Sign In / Providers**
   * *Allow new users to sign up*: **ON** (customers sign up in the app).
   * Email: **Confirm email ON** — new accounts get a verification link.
3. **Authentication → URL Configuration → Redirect URLs** — add:
   ```
   aurabyhs://login-callback
   aurabyhs://reset-password
   ```
   (plus the POS address that is already there).
4. **Authentication → SMTP** (strongly recommended): Supabase's built-in mailer sends only a few emails
   an hour. Use a free sender, e.g. **Brevo** (300/day free) or **Resend** (3,000/month free): create an
   account, verify the `aurabyhs.pk` domain, paste the SMTP host/user/password here. Sender name
   "Aura by HS", sender email `no-reply@aurabyhs.pk`.
5. **Authentication → Email Templates**: put the logo and a friendly line in *Confirm signup* and
   *Reset password* ("Tap the button to open the Aura app").
6. **Project Settings → API**: copy the **Project URL**, the **anon / publishable key** (goes in the
   app) and the **service_role / secret key** (goes only on the API server — never in the app,
   website or POS).

## 2. Google sign-in for the app (10 minutes)

The POS already uses a Google *Web* OAuth client with Supabase. The app signs in through the same
Supabase Google provider, so:

1. Google Cloud console → the same project → **OAuth consent screen**: app name "Aura by HS", logo,
   support email, privacy policy `https://aurabyhs.pk/privacy`. Publish to production.
2. Nothing else is needed for Android/iOS: Google returns to Supabase, and Supabase sends the customer
   back to `aurabyhs://login-callback`, which opens the app (already set up in the Android manifest and
   iOS Info.plist).

## 3. Deploy the API on Render — free (10 minutes)

1. <https://render.com> → sign in with GitHub → **New → Blueprint** → choose the `Aura-App` repository.
   Render reads `render.yaml` and creates the `aura-api` service on the free plan.
2. Fill the environment variables it asks for:

   | Name | Value |
   | --- | --- |
   | `SUPABASE_URL` | Project URL from step 1.6 |
   | `SUPABASE_SERVICE_KEY` | service_role key from step 1.6 |
   | `PUBLIC_URL` | the address Render shows, e.g. `https://aura-api.onrender.com` |
   | `CORS_ORIGINS` | `https://aurabyhs.pk,https://www.aurabyhs.pk,https://pos.aurabyhs.pk` |
   | `PAYMENT_MODE` | `sandbox` for now (test checkout), `live` when the merchant accounts are ready |

3. Open `https://aura-api.onrender.com/health` — it should say `"database": true`.
4. In the POS as owner: **Settings → Online & app → Payments server address** = that address. Fill the
   bank account for transfers. Save.

> **Free plan:** the server sleeps after 15 minutes without requests and the first request then takes
> ~30–60 seconds (the app shows "Connecting to Aura…"). Bookings and payments are never lost — the app
> just waits. For instant responses all day, Render **Starter is $7/month**; nothing else changes.
> Optional free trick: an uptime monitor (e.g. UptimeRobot, free) calling `/health` every 10 minutes
> during salon hours keeps it awake.

## 4. Payments — JazzCash and Easypaisa merchant accounts

Until this step, every payment runs through the built-in **test checkout** (clearly marked
"TEST MODE — no real money"), so the whole flow can be shown to the owner and staff.

| | JazzCash | Easypaisa |
| --- | --- | --- |
| Apply | jazzcash.com.pk → Business → Online Payment Gateway (or the JazzCash business team) | easypaisa.com.pk → Business → Easypay / Online Payments |
| Documents | Business NTN or owner CNIC, bank account in the business name, website with privacy & terms pages | Same |
| Test keys | Sandbox portal (sandbox.jazzcash.com.pk) gives a Merchant ID, Password and Integrity Salt | Staging store id and hash key from the Easypay merchant portal |
| Fees (typical) | ~1.5–2.5% per wallet/card payment | ~1.5–2.5% |
| Cards | Visa / Mastercard through the same JazzCash checkout | Card payments through Easypay, if enabled on the store |

When the keys arrive, add them on Render → Environment:

```
JAZZCASH_MERCHANT_ID=…    JAZZCASH_PASSWORD=…    JAZZCASH_INTEGRITY_SALT=…
EASYPAISA_STORE_ID=…      EASYPAISA_HASH_KEY=…
EASYPAISA_USERNAME=…      EASYPAISA_PASSWORD=…     (optional — double-checks every result)
PAYMENT_MODE=sandbox      (test keys)  →  live  (real keys)
```

Give each provider these addresses if their portal asks (they are also sent with every payment):

* JazzCash return URL: `https://aura-api.onrender.com/pay/{token}/jazzcash/return`
  (some portals want just the domain: `https://aura-api.onrender.com`)
* Easypaisa postback URL: `https://aura-api.onrender.com/pay/{token}/easypaisa/return`

How the money is recorded (no extra work for staff):

| Paid for | Where it appears in the POS |
| --- | --- |
| Appointment advance / full / part | Advance on the customer's account (offered automatically at the till), booking confirmed |
| Bridal advance / instalment | Payment line on the bridal booking; the advance confirms the dates |
| Unpaid bill (payment link) | Payment on the bill; balance due goes down |
| Gift voucher (from the app) | A new gift voucher, code shown to the customer |
| Bank transfer | Waits in **POS → Online payments → Receipts to check** until a branch presses *Verify* |

Every payment is listed in **POS → Online payments**, with **Money by platform** showing cash, card,
bank transfer, JazzCash and Easypaisa per customer, branch and day (exportable to Excel).

Card numbers and wallet PINs never touch our server: customers pay on JazzCash's / Easypaisa's own page.

## 5. Build and publish the app

### Settings file

The Flutter app lives in `app/`, so run every `flutter` command from inside that
folder (`cd app`). The backend stays at the repository root in `backend/`, which is
what `render.yaml` points at.

Copy `app/config.example.json` to `app/config.json` (never commit it — it is in
`.gitignore`):

```json
{
  "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "anon / publishable key",
  "API_URL": "https://aura-api.onrender.com"
}
```

Run on a phone: `flutter run --dart-define-from-file=config.json`.
Without the file the app runs as the offline **demo** (sample data, demo sign-in) — handy for showing it.

### Android — Google Play (one-time $25)

1. Create an upload key once (keep it and its passwords safe — losing it means a new app listing):
   `keytool -genkey -v -keystore aura-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Create `android/key.properties` (git-ignored) and reference it in `android/app/build.gradle.kts`
   as described in <https://docs.flutter.dev/deployment/android#sign-the-app>.
3. `flutter build appbundle --release --dart-define-from-file=config.json`
   → `build/app/outputs/bundle/release/app-release.aab`.
4. <https://play.google.com/console> → pay the $25 developer fee → **Create app** "Aura by HS" →
   upload the .aab to *Internal testing* first, then *Production*. Fill the store listing (photos from
   `assets/images`), the privacy policy URL, the **Data safety** form (name, email, phone, purchase
   history; data encrypted in transit; users can delete their account in the app) and the account
   deletion URL (`https://aurabyhs.pk/delete-account`).
5. When it is live, paste the Play Store link in POS → Settings → Online & app — the website's
   "Get the app" button appears by itself.

### iPhone — App Store ($99 / year)

Needs a Mac with Xcode and an Apple Developer account. `flutter build ipa --release
--dart-define-from-file=config.json`, then upload with Xcode's Organizer / Transporter. Apple requires
**Sign in with Apple** in apps that offer Google sign-in; if you publish on iOS, enable the Apple
provider in Supabase (Authentication → Providers → Apple) and add the button (small change in
`lib/aura/screens/auth_screen.dart` and `services/auth.dart` — same pattern as Google).

Application id: `pk.aurabyhs.aura_by_hs` (Android) — keep it forever once published.

## 6. Demo / test access for the client

* **App:** "Browse as guest" shows the real menu without an account. A build without `config.json`
  is a fully offline demo.
* **POS:** a build without Supabase keys has *Login as Admin* / *Login as Shop* demo buttons.
* **Payments:** with `PAYMENT_MODE=sandbox` and no keys, every payment uses the test checkout.

## 7. Backups — free

The POS repository's **Nightly backup** GitHub Action dumps the whole Supabase database every night
(POS data, app accounts, online payments, chats), kept 90 days. Set it up once
(`Aura-By-HS-POS/.github/workflows/backup.yml`, secret `SUPABASE_DB_URL`). Receipt photos and chat
images live in Supabase Storage; download them occasionally from Storage → `payment-slips` if you want
an offline copy.

## 8. What it costs

| Item | Plan | Cost |
| --- | --- | --- |
| Supabase (database, sign-in, files, realtime) | Free: 500 MB DB, 1 GB files, 50,000 monthly users | Rs 0 — Pro $25/month only if it outgrows that |
| API server | Render Free (sleeps when idle) | Rs 0 — Starter $7/month for always-on |
| POS hosting | Cloudflare Pages | Rs 0 |
| Emails (verification, password reset) | Brevo / Resend free tier | Rs 0 |
| Backups | GitHub Actions | Rs 0 |
| Google Play | one-time | $25 |
| Apple App Store | yearly (only if you publish on iPhone) | $99/year |
| JazzCash / Easypaisa | per transaction | ~1.5–2.5% of each online payment |
| Domain | aurabyhs.pk | ~Rs 3–4k/year |

## 9. Checklist

- [ ] POS schema re-run; sign-ups ON; Confirm email ON; redirect URLs added; SMTP set
- [ ] API on Render, `/health` shows `database: true`; POS → Settings → Online & app filled
- [ ] Test booking from the app → appears in POS → Appointments
- [ ] Test payment (test checkout) → booking confirmed, payment in POS → Online payments
- [ ] Test bank transfer → receipt visible in POS → Online payments → Verify works
- [ ] Test chat both ways (app ↔ POS → Messages); post an announcement
- [ ] Merchant keys added, `PAYMENT_MODE=live`, one real Rs 10 payment each for JazzCash and Easypaisa
- [ ] App published; store links in POS settings; website updated (`Aura-By-HS-POS/docs/WEBSITE_CHANGES.md`)
- [ ] Nightly backup green
