# Aura by HS — customer app + API

| Folder | What |
| --- | --- |
| `app/` | Flutter app (Android, iOS, web) for Aura by HS customers — its code is in `app/lib/` |
| `backend/` | Python (FastAPI) API: bookings, payments, chat, website endpoints — see [backend/README.md](backend/README.md) |
| `docs/GO_LIVE.md` | Step-by-step launch: Supabase, Google sign-in, Render, JazzCash/Easypaisa, Play Store |

The two halves are deployed separately: `backend/` to Render (its `render.yaml` sets
`rootDir: backend`), and `app/` to the Play Store and App Store. Run every Flutter
command from inside `app/`.

The app, the API and the **POS** (`Aura-By-HS-POS` repo) share one Supabase database, so a booking,
payment or message made in one shows up in the others straight away.

## What customers can do

- Sign in with **Google**, or email + password (verification email, **forgot password** by email);
  or browse as a **guest**
- See the salon's real menu, prices, branches (open now?), artists and offers — edited in the POS
- Book in 7 steps with **real free times** (the POS's own rota, break and double-booking rules)
- Pay an **advance, the full amount or the balance** with **JazzCash, Easypaisa, card** (on the
  provider's secure page) or **bank transfer** with receipt upload; or pay at the salon
- Request **bridal packages** for their event dates and pay the 30% advance to hold them
- My bookings: status from the salon, reschedule, cancel (with the salon's notice rule), pay, rate
- **Chat** with head office (Aura Concierge) or any branch, with photos; read the owner's announcements
- Wallet: loyalty points, advance credit, gift vouchers bought in the app, payment history; invoices
  from the POS's bills
- Profile, beauty preferences shared with the artist, delete account, English / اردو

## Run

```bash
cd app                                              # every Flutter command runs from here
flutter pub get
flutter run                                         # offline demo (sample data, demo sign-in)
cp config.example.json config.json                  # fill in Supabase + API addresses
flutter run --dart-define-from-file=config.json     # connected to the real system
flutter build appbundle --release --dart-define-from-file=config.json   # Play Store
```

Without `config.json` the app is a self-contained demo (sign-in code `1234`, test payments), useful
for showing the design. With it, everything is live.

## Tests

```bash
flutter analyze && flutter test
cd backend && pip install -r requirements-dev.txt && pytest
```
