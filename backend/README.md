# Aura by HS — API (Python / FastAPI)

The backend for the customer app, the website's booking form and the POS's
online-payment links. It shares **one Supabase database** with the POS, so a
booking made in the app appears in the branch diary instantly, a payment shows
in POS → Online payments, and a chat message lands in POS → Messages.

```
Flutter app ──┐                        ┌── POS (React, Supabase client)
Website ──────┼──► this API ──► Supabase (Postgres + Auth + Storage) ◄──┘
              │      │
              │      └──► JazzCash / Easypaisa hosted checkout (card, wallet)
              └── Supabase Auth (Google, email + verification, password reset)
```

## What it does

| Area | Endpoints |
| --- | --- |
| Catalogue (guests too) | `GET /v1/catalog` branches, services, packages, artists, offers, announcements, payment options · `GET /v1/availability` free times using the POS's exact rules |
| Account | `GET/PUT/DELETE /v1/me` |
| Bookings | `GET/POST /v1/bookings` · `POST /v1/bookings/{id}/cancel` · `/reschedule` · `/review` · `POST /v1/bridal` |
| Money | `POST /v1/payments` (advance, full, part, balance; JazzCash, Easypaisa, card, bank transfer) · `GET /v1/payments/{id}` · `POST /v1/payments/{id}/slip` · `GET /v1/wallet` · `GET /v1/invoices` |
| Chat | `GET /v1/threads` · `GET/POST /v1/threads/{hq or shopId}/messages` · `POST /v1/threads/{key}/photo` |
| Website | `POST /v1/public/bookings` · `POST /v1/public/enquiries` · `GET /v1/public/app-links` |
| Hosted pages | `/pay/{token}` — the payment page the app opens and the POS shares on WhatsApp |

Interactive docs: `/docs` once running.

## How a payment works

1. The app (or the POS, as a link) creates a payment: what it is for and how much
   (advance = 20% for services / 30% for bridal by default, full, part, or the bill's balance).
2. The customer opens `/pay/{token}` and is handed to **JazzCash** or **Easypaisa**'s own
   secure page (wallet or card). Card numbers and PINs never reach this server.
3. The gateway's signed result comes back; the money is booked exactly where a cashier
   would put it — an advance on the customer's account (offered automatically at the till),
   a payment on the bridal booking, or against the bill's balance — and a pending booking is confirmed.
4. **Bank transfer**: the customer uploads the receipt; the branch checks it in
   POS → Online payments and presses Verify.

Without merchant keys every gateway runs as a **test checkout** (approve / decline), so the
whole flow can be shown to the client before the merchant accounts are open.

## Run locally

```bash
cd backend
python -m venv .venv && . .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env    # fill SUPABASE_URL and SUPABASE_SERVICE_KEY
uvicorn app.main:app --reload                    # http://127.0.0.1:8000
pytest                  # 30 tests, no database needed
```

Check it is up:

```bash
curl http://127.0.0.1:8000/health
# {"ok":true,"service":"aura-api","database":true,...}
```

`database: false` means `SUPABASE_SERVICE_KEY` is missing or wrong — the server
still starts, so this is the only way to notice.

## Run in Docker

Render does not use the Dockerfile (`render.yaml` declares `runtime: python`,
which builds faster and is cached). It is here so the API runs anywhere a
container runs — Fly.io, Railway, Cloud Run, a VPS — and so nobody has to match
Python versions by hand.

```bash
docker build -t aura-api ./backend
docker run --rm -p 8000:8000 --env-file backend/.env aura-api
curl http://127.0.0.1:8000/health
```

The image runs as a non-root user, and `.dockerignore` keeps `.env`, `.venv`
and the tests out of the build context, so no secret can reach a layer.

To deploy to Render as a container instead of the native runtime, change
`render.yaml` to `runtime: docker` with `dockerfilePath: ./Dockerfile`
(`rootDir` is already `backend`).

## Deploy free on Render

Render → **New → Blueprint** → choose this repository (it reads `render.yaml`), then fill
`SUPABASE_URL`, `SUPABASE_SERVICE_KEY` and `PUBLIC_URL` (the `…onrender.com` address Render gives you).
The free plan sleeps after 15 minutes idle (the first request then takes ~30–50 s);
the app shows "Connecting…" meanwhile. For no sleep, Render Starter is $7/month.

Full go-live steps (Supabase, Google sign-in, merchant accounts) are in [`../docs/GO_LIVE.md`](../docs/GO_LIVE.md).
