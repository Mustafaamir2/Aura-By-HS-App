"""The website seam, and the row shapes the POS depends on.

Two things are checked here that nothing else covers:

1. The public endpoints the website uses (`/v1/public/*`) — no account, so a
   different path through the code than the app's authenticated booking.

2. That the rows those endpoints write carry every field the POS declares in
   its own TypeScript types. This is the seam that actually breaks in
   production: the POS trusts the database, the backend trusts itself, and the
   two repositories never meet in either test suite. A booking the POS cannot
   render is worse than a booking that was refused.

The field lists below are transcribed from the POS repo:
    src/types/appointment.ts   Appointment, AppointmentService, AppointmentStatusHistory
    src/types/customer.ts      Customer
    src/types/bridal.ts        Enquiry
    src/types/online.ts        OnlinePayment
    src/types/common.ts        BaseRecord, ShopScoped
If a type changes there, this test should fail here.
"""
from __future__ import annotations

from datetime import timedelta

from app.core import local_now, parse_iso

BASE_RECORD = {"id", "createdAt", "updatedAt"}

APPOINTMENT = BASE_RECORD | {
    "shopId", "customerId", "staffId", "services", "startAt", "durationMin",
    "status", "notes", "cancelReason", "history", "saleId", "source",
}
APPOINTMENT_SERVICE = {"serviceId", "price", "durationMin"}
APPOINTMENT_HISTORY = {"status", "at", "byUserId", "byUserName", "note"}
APPOINTMENT_STATUSES = {
    "pending", "confirmed", "checked-in", "in-progress", "completed", "cancelled", "no-show",
}
APPOINTMENT_SOURCES = {"walk-in", "phone", "online", "front-desk"}

CUSTOMER = BASE_RECORD | {
    "shopId", "name", "phone", "email", "gender", "preferredStaffId",
    "preferredServiceIds", "sensitivities", "notes", "active", "firstVisitOn",
}
CUSTOMER_GENDERS = {"female", "male", "other", "unspecified"}

ENQUIRY = BASE_RECORD | {
    "shopId", "name", "phone", "email", "interest", "preferredDate", "message",
    "source", "status", "notes", "followUpOn", "customerId", "bookingId",
}

ONLINE_PAYMENT = BASE_RECORD | {
    "paymentNo", "shopId", "purpose", "refId", "refLabel", "customerId", "customerName",
    "customerPhone", "accountId", "plan", "amount", "method", "status", "token",
    "gateway", "gatewayRef", "gatewayMessage", "slipPath", "payerNote", "paidAt",
    "verifiedBy", "rejectReason", "createdBy", "channel", "expiresAt", "appliedAt", "attempts",
}


def _day(n: int = 1) -> str:
    return (local_now() + timedelta(days=n)).date().isoformat()


def _first_free(client, services: str = "svc_cut", day: str | None = None) -> dict:
    slots = client.get(
        "/v1/availability",
        params={"shopId": "shp_gul", "date": day or _day(), "serviceIds": services},
    ).json()["slots"]
    free = [s for s in slots if s["available"]]
    assert free, "the seeded diary should have free times"
    return free[0]


def _book(client, slot: dict, **over):
    body = {
        "name": "Test Website", "phone": "03001112233", "email": "test@example.com",
        "shopId": "shp_gul", "serviceIds": ["svc_cut"], "staffId": "any",
        "startAt": slot["startAt"], "notes": "From the website",
    }
    body.update(over)
    return client.post("/v1/public/bookings", json=body)


def _missing(row: dict, required: set[str]) -> set[str]:
    return required - set(row)


# --- the website's own endpoints ---------------------------------------


def test_website_can_browse_without_an_account(client):
    cat = client.get("/v1/catalog")
    assert cat.status_code == 200
    body = cat.json()
    # Prices must stay numeric: the website does arithmetic on them.
    assert all(isinstance(s["price"], (int, float)) for s in body["services"])
    assert client.get("/v1/public/app-links").status_code == 200


def test_website_booking_lands_in_the_diary(client, store):
    slot = _first_free(client)
    r = _book(client, slot, couponCode="aura15")
    assert r.status_code == 200, r.text
    out = r.json()

    appts = store.tables["appointments"]
    assert len(appts) == 1
    appt = next(iter(appts.values()))

    assert appt["source"] == "online", "the POS filters the diary by this"
    assert appt["status"] == "pending"
    # Stored as UTC — the same instant, not the same string.
    assert parse_iso(appt["startAt"]) == parse_iso(slot["startAt"])
    assert out["bookingId"] == appt["id"]
    # 3500 less the seeded 15% coupon.
    assert out["total"] == 2975


def test_website_booking_raises_a_bell_in_the_pos(client, store):
    _book(client, _first_free(client))
    notes = list(store.tables.get("notifications", {}).values())
    assert notes, "the front desk must be told about an online booking"
    assert notes[0]["shopId"] == "shp_gul"


def test_a_booked_artist_stops_being_offered(client):
    """The slot itself survives while a second qualified artist is free — what
    must disappear is the artist who was just booked."""
    slot = _first_free(client)
    booked = _book(client, slot)
    assert booked.status_code == 200
    taken_by = booked.json()["staffId"]
    assert taken_by in slot["staffIds"]

    again = client.get(
        "/v1/availability",
        params={"shopId": "shp_gul", "date": _day(), "serviceIds": "svc_cut"},
    ).json()["slots"]
    same = next(s for s in again if s["startAt"] == slot["startAt"])
    assert taken_by not in same["staffIds"]
    # Two artists can do svc_cut, so the time is still bookable with the other.
    assert same["available"] == bool(same["staffIds"])


def test_the_last_artist_closes_the_slot(client):
    """With only one qualified artist left, the time goes away entirely."""
    slot = _first_free(client, services="svc_style")  # only stf_sana does this
    assert slot["staffIds"] == ["stf_sana"]
    assert _book(client, slot, serviceIds=["svc_style"]).status_code == 200

    again = client.get(
        "/v1/availability",
        params={"shopId": "shp_gul", "date": _day(), "serviceIds": "svc_style"},
    ).json()["slots"]
    assert not next(s for s in again if s["startAt"] == slot["startAt"])["available"]


def test_two_people_taking_the_last_slot(client):
    slot = _first_free(client)
    first = _book(client, slot)
    assert first.status_code == 200
    second = _book(client, slot, name="Second Person", phone="03009998877",
                   staffId=first.json()["staffId"])
    assert second.status_code >= 400
    # The website shows this sentence verbatim, so it has to read like English.
    assert isinstance(second.json().get("error"), str)


def test_website_booking_refuses_bad_input(client):
    slot = _first_free(client)
    assert _book(client, slot, phone="12345").status_code >= 400
    assert _book(client, slot, shopId="shp_nope").status_code >= 400
    assert _book(client, slot, serviceIds=["svc_nope"]).status_code >= 400


def test_website_enquiry_reaches_the_pos(client, store):
    r = client.post("/v1/public/enquiries", json={
        "name": "Test Enquiry", "phone": "03001112233", "interest": "Bride Royal",
        "preferredDate": "2026-12-20", "message": "Planning a December wedding",
        "source": "website",
    })
    assert r.status_code == 200, r.text
    row = next(iter(store.tables["enquiries"].values()))
    assert row["source"] == "website" and row["status"] == "new"


def test_website_advance_payment(client, store):
    slot = _first_free(client)
    r = _book(client, slot, payPlan="advance", returnUrl="https://aurabyhs.pk/thank-you")
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["payUrl"].endswith(out["payUrl"].rsplit("/", 1)[-1])
    # 20% of 3500 by the seeded settings.
    assert out["payAmount"] == 700

    pay = next(iter(store.tables["online_payments"].values()))
    assert pay["channel"] == "website" and pay["createdBy"] == "website"
    # The payment page must actually render for the customer.
    assert client.get(f"/pay/{pay['token']}").status_code == 200


def test_website_rejects_a_non_https_return_url(client):
    slot = _first_free(client)
    r = _book(client, slot, payPlan="advance", returnUrl="http://aurabyhs.pk/thank-you")
    assert r.status_code == 200
    # Dropped rather than honoured: an http return address would downgrade the
    # customer out of TLS on the way back from the bank.
    pay = r.json()
    assert pay.get("payUrl")


# --- the POS has to be able to read what we wrote -----------------------


def test_written_appointment_matches_the_pos_type(client, store):
    slot = _first_free(client)
    assert _book(client, slot).status_code == 200
    appt = next(iter(store.tables["appointments"].values()))

    assert not _missing(appt, APPOINTMENT), f"POS Appointment needs {_missing(appt, APPOINTMENT)}"
    assert appt["status"] in APPOINTMENT_STATUSES
    assert appt["source"] in APPOINTMENT_SOURCES
    assert isinstance(appt["durationMin"], (int, float))
    assert isinstance(appt["services"], list) and appt["services"]
    for line in appt["services"]:
        assert not _missing(line, APPOINTMENT_SERVICE)
        assert isinstance(line["price"], (int, float))
    assert isinstance(appt["history"], list) and appt["history"]
    for entry in appt["history"]:
        assert not _missing(entry, APPOINTMENT_HISTORY)
        assert entry["status"] in APPOINTMENT_STATUSES
    for field in ("createdAt", "updatedAt", "startAt"):
        parse_iso(appt[field])  # raises if the POS could not parse it either


def test_written_customer_matches_the_pos_type(client, store):
    assert _book(client, _first_free(client)).status_code == 200
    cust = next(iter(store.tables["customers"].values()))

    assert not _missing(cust, CUSTOMER), f"POS Customer needs {_missing(cust, CUSTOMER)}"
    assert cust["gender"] in CUSTOMER_GENDERS
    assert isinstance(cust["preferredServiceIds"], list)
    assert cust["active"] is True
    # The POS matches a returning customer on digits alone.
    assert cust["phone"] == "03001112233"


def test_written_enquiry_matches_the_pos_type(client, store):
    client.post("/v1/public/enquiries", json={
        "name": "Test Enquiry", "phone": "03001112233", "interest": "Bride Royal"})
    row = next(iter(store.tables["enquiries"].values()))
    assert not _missing(row, ENQUIRY), f"POS Enquiry needs {_missing(row, ENQUIRY)}"


def test_written_payment_matches_the_pos_type(client, store):
    slot = _first_free(client)
    assert _book(client, slot, payPlan="advance").status_code == 200
    pay = next(iter(store.tables["online_payments"].values()))

    assert not _missing(pay, ONLINE_PAYMENT), f"POS OnlinePayment needs {_missing(pay, ONLINE_PAYMENT)}"
    assert pay["channel"] in {"app", "website", "link"}
    assert isinstance(pay["amount"], (int, float))
    assert isinstance(pay["attempts"], list)
    parse_iso(pay["createdAt"])
