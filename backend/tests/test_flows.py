from __future__ import annotations

import asyncio
from datetime import timedelta

from app.core import local_now
from app.payments import easypaisa, jazzcash

from .conftest import H, in_days, tomorrow


def run(c):
    return asyncio.get_event_loop().run_until_complete(c) if False else asyncio.run(c)


def set_phone(client):
    r = client.put("/v1/me", json={"phone": "0300 1234567"}, headers=H())
    assert r.status_code == 200, r.text
    return r.json()


def book(client, hhmm="11:00", staff="any", services=("svc_cut",), days=1, coupon=None):
    body = {"shopId": "shp_gul", "serviceIds": list(services), "staffId": staff, "startAt": in_days(days, hhmm)}
    if coupon:
        body["couponCode"] = coupon
    return client.post("/v1/bookings", json=body, headers=H())


def test_health_and_catalogue(client):
    assert client.get("/health").json()["ok"]
    cat = client.get("/v1/catalog").json()
    assert [s["name"] for s in cat["shops"]] == ["Aura Gulberg"]
    assert len(cat["services"]) == 2 and cat["payments"]["methods"] == ["jazzcash", "easypaisa", "card", "bank-transfer"]
    assert cat["payments"]["bank"]["bankName"] == "Meezan Bank"


def test_guest_cannot_book_but_can_see_times(client):
    day = (local_now() + timedelta(days=1)).date().isoformat()
    slots = client.get("/v1/availability", params={"shopId": "shp_gul", "date": day, "serviceIds": "svc_cut"}).json()["slots"]
    assert slots and slots[0]["time"] == "10:00"
    assert not next(s for s in slots if s["time"] == "15:00")["available"]  # break
    r = client.post("/v1/bookings", json={"shopId": "shp_gul", "serviceIds": ["svc_cut"], "startAt": tomorrow()})
    assert r.status_code == 401


def test_booking_needs_phone_then_lands_in_pos(client, store):
    r = book(client)
    assert r.status_code == 400 and "mobile" in r.json()["error"]
    set_phone(client)
    r = book(client, coupon="aura15")
    assert r.status_code == 200, r.text
    b = r.json()["booking"]
    assert b["status"] == "pending" and b["total"] == 2975 and b["couponCode"] == "AURA15"
    appt = run(store.get("appointments", b["id"]))
    assert appt["source"] == "online" and appt["services"][0]["price"] == 3500
    cust = run(store.get("customers", appt["customerId"]))
    assert cust["phone"] == "03001234567" and cust["shopId"] == "shp_gul"
    assert any(n["type"] == "appointment-created" for n in run(store.list("notifications")))
    # The same slot is now taken for that artist; "any" moves to the other artist.
    r2 = book(client, staff=appt["staffId"])
    assert r2.status_code == 409
    r3 = book(client)
    assert r3.status_code == 200 and r3.json()["booking"]["staffId"] != appt["staffId"]


def test_advance_payment_via_simulator_confirms_booking(client, store):
    set_phone(client)
    b = book(client).json()["booking"]
    r = client.post("/v1/payments", json={"purpose": "appointment", "refId": b["id"], "plan": "advance", "method": "jazzcash"}, headers=H())
    assert r.status_code == 200, r.text
    pay = r.json()
    assert pay["payment"]["amount"] == 700  # 20% of 3,500
    tok = pay["payment"]["token"]
    r = client.get(f"/pay/{tok}/start?method=jazzcash", follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"].endswith("/simulate")
    page = client.get(f"/pay/{tok}/simulate")
    assert "TEST MODE" in page.text
    client.post(f"/pay/{tok}/simulate", data={"decision": "approve"}, follow_redirects=False)
    p = client.get(f"/v1/payments/{pay['payment']['id']}", headers=H()).json()["payment"]
    assert p["status"] == "paid" and p["gateway"] == "simulator"
    appt = run(store.get("appointments", b["id"]))
    assert appt["status"] == "confirmed"
    credit = run(store.list("customer_credits"))[0]
    assert credit["amount"] == 700 and credit["kind"] == "advance" and credit["method"] == "jazzcash" and credit["appointmentId"] == b["id"]
    view = client.get("/v1/bookings", headers=H()).json()["appointments"][0]
    assert view["paid"] == 700 and view["due"] == 2800
    # Paying the advance again is refused; the rest can be paid as "full".
    assert client.post("/v1/payments", json={"purpose": "appointment", "refId": b["id"], "plan": "advance"}, headers=H()).status_code == 409
    full = client.post("/v1/payments", json={"purpose": "appointment", "refId": b["id"], "plan": "full", "method": "easypaisa"}, headers=H()).json()
    assert full["payment"]["amount"] == 2800
    part = client.post("/v1/payments", json={"purpose": "appointment", "refId": b["id"], "plan": "partial", "amount": 100}, headers=H())
    assert part.status_code == 400 and "smallest" in part.json()["error"]


def test_declined_payment_can_be_retried(client):
    set_phone(client)
    b = book(client).json()["booking"]
    pay = client.post("/v1/payments", json={"purpose": "appointment", "refId": b["id"], "plan": "full", "method": "easypaisa"}, headers=H()).json()
    tok = pay["payment"]["token"]
    client.get(f"/pay/{tok}/start?method=easypaisa")
    client.post(f"/pay/{tok}/simulate", data={"decision": "decline"})
    res = client.get(f"/pay/{tok}/result")
    assert "not completed" in res.text and "Try again" in res.text


def test_jazzcash_signed_callback(client, store, monkeypatch):
    from app import config

    config.get_settings.cache_clear()
    monkeypatch.setenv("JAZZCASH_MERCHANT_ID", "MC123")
    monkeypatch.setenv("JAZZCASH_PASSWORD", "pw")
    monkeypatch.setenv("JAZZCASH_INTEGRITY_SALT", "salt123")
    try:
        set_phone(client)
        b = book(client).json()["booking"]
        pay = client.post("/v1/payments", json={"purpose": "appointment", "refId": b["id"], "plan": "full", "method": "jazzcash"}, headers=H()).json()["payment"]
        page = client.get(f"/pay/{pay['token']}/start?method=jazzcash")
        assert "sandbox.jazzcash.com.pk" in page.text and "pp_SecureHash" in page.text
        row = run(store.get("online_payments", pay["id"]))
        fields = {"pp_ResponseCode": "000", "pp_ResponseMessage": "Thank you", "pp_TxnRefNo": row["gatewayRef"], "pp_Amount": str(int(row["amount"] * 100)),
                  "pp_MerchantID": "MC123", "pp_RetreivalReferenceNo": "RRN1"}
        # A forged result is refused …
        bad = dict(fields, pp_SecureHash="00")
        client.post(f"/pay/{pay['token']}/jazzcash/return", data=bad)
        assert run(store.get("online_payments", pay["id"]))["status"] != "paid"
        # … a correctly signed one is accepted.
        fields["pp_SecureHash"] = jazzcash.secure_hash(fields, "salt123")
        client.post(f"/pay/{pay['token']}/jazzcash/return", data=fields)
        row = run(store.get("online_payments", pay["id"]))
        assert row["status"] == "paid" and row["gatewayRef"] == "RRN1"
        # Replaying the callback does not pay twice.
        client.post(f"/pay/{pay['token']}/jazzcash/return", data=fields)
        assert len(run(store.list("customer_credits"))) == 1
    finally:
        config.get_settings.cache_clear()


def test_easypaisa_request_is_aes_encrypted():
    import base64

    from cryptography.hazmat.primitives import padding
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    key = "0123456789ABCDEF"
    enc = easypaisa.hashed_request({"amount": "10.0", "storeId": "1", "orderRefNum": "X", "postBackURL": "u", "emailAddr": ""}, key)
    d = Cipher(algorithms.AES(key.encode()), modes.ECB()).decryptor()
    raw = d.update(base64.b64decode(enc)) + d.finalize()
    un = padding.PKCS7(128).unpadder()
    plain = (un.update(raw) + un.finalize()).decode()
    assert plain == "amount=10.0&orderRefNum=X&postBackURL=u&storeId=1"


def test_bank_slip_waits_for_pos_verification(client, store):
    set_phone(client)
    b = book(client).json()["booking"]
    pay = client.post("/v1/payments", json={"purpose": "appointment", "refId": b["id"], "plan": "advance", "method": "bank-transfer"}, headers=H()).json()["payment"]
    r = client.post(f"/v1/payments/{pay['id']}/slip", files={"file": ("slip.jpg", b"\xff\xd8jpeg", "image/jpeg")}, data={"note": "From Ayesha"}, headers=H())
    assert r.status_code == 200 and r.json()["payment"]["status"] == "verifying"
    row = run(store.get("online_payments", pay["id"]))
    assert row["slipPath"].startswith("shp_gul/") and f"payment-slips/{row['slipPath']}" in store.files
    assert run(store.get("appointments", b["id"]))["status"] == "pending"  # not until the salon checks it
    bad = client.post(f"/v1/payments/{pay['id']}/slip", files={"file": ("x.exe", b"MZ", "application/x-msdownload")}, headers=H())
    assert bad.status_code == 409  # closed now that it is verifying


def test_bridal_request_advance_confirms(client, store):
    set_phone(client)
    d = (local_now() + timedelta(days=60)).date().isoformat()
    r = client.post("/v1/bridal", json={"shopId": "shp_gul", "packageId": "pkg_sig", "events": [{"type": "Mehndi", "date": d}, {"type": "Barat", "date": d}]}, headers=H())
    assert r.status_code == 200, r.text
    br = r.json()["bridal"]
    assert br["status"] == "tentative" and br["advanceRequired"] == 28500 and br["bookingNo"].startswith("BR-GUL-")
    pay = client.post("/v1/payments", json={"purpose": "bridal", "refId": br["id"], "plan": "advance", "method": "easypaisa"}, headers=H()).json()["payment"]
    assert pay["amount"] == 28500
    client.get(f"/pay/{pay['token']}/start?method=easypaisa")
    client.post(f"/pay/{pay['token']}/simulate", data={"decision": "approve"})
    row = run(store.get("bridal_bookings", br["id"]))
    assert row["status"] == "confirmed" and row["payments"][0]["method"] == "easypaisa" and row["payments"][0]["kind"] == "advance"
    view = client.get("/v1/bookings", headers=H()).json()["bridal"][0]
    assert view["paid"] == 28500 and view["due"] == 66500


def test_pos_payment_link_for_bill_balance(client, store):
    """The POS writes a payment row for a bill with money owed; the customer pays from the link."""
    from app.core import stamped

    sale = stamped({"id": "sal_1", "shopId": "shp_gul", "receiptNo": "GUL-2026-000010", "customerId": None, "customerName": "Walk-in", "total": 9000,
                    "balanceDue": 4000, "payments": [{"id": "p1", "method": "cash", "amount": 5000, "tendered": 5000, "reference": None}], "status": "completed"})
    run(store.put("sales", sale))
    link = stamped({"id": "opy_pos", "paymentNo": "PAY-1", "shopId": "shp_gul", "purpose": "sale", "refId": "sal_1", "refLabel": "Bill GUL-2026-000010",
                    "customerId": None, "customerName": "Walk-in", "customerPhone": "", "accountId": None, "plan": "balance", "amount": 4000,
                    "method": None, "status": "pending", "token": "TOKPOS", "attempts": [], "createdBy": "Front desk", "channel": "link", "expiresAt": None, "appliedAt": None})
    run(store.put("online_payments", link))
    page = client.get("/pay/TOKPOS")
    assert "Rs 4,000" in page.text and "JazzCash" in page.text and "Bank transfer" in page.text
    client.get("/pay/TOKPOS/start?method=card")
    client.post("/pay/TOKPOS/simulate", data={"decision": "approve"})
    s = run(store.get("sales", "sal_1"))
    assert s["balanceDue"] == 0 and s["payments"][-1]["method"] == "card"
    assert "successful" in client.get("/pay/TOKPOS/result").text


def test_cancel_and_reschedule_rules(client, store):
    set_phone(client)
    soon = client.post("/v1/bookings", json={"shopId": "shp_gul", "serviceIds": ["svc_cut"], "startAt": (local_now() + timedelta(hours=3)).replace(minute=0, second=0, microsecond=0).isoformat()}, headers=H())
    if soon.status_code == 200:  # only when the salon is open in three hours
        assert client.post(f"/v1/bookings/{soon.json()['booking']['id']}/cancel", json={}, headers=H()).status_code == 409
    b = book(client, days=2).json()["booking"]
    r = client.post(f"/v1/bookings/{b['id']}/reschedule", json={"startAt": in_days(2, "17:00")}, headers=H())
    assert r.status_code == 200, r.text
    from app.core import parse_iso, tz

    assert parse_iso(r.json()["booking"]["startAt"]).astimezone(tz()).strftime("%H:%M") == "17:00"
    r = client.post(f"/v1/bookings/{b['id']}/cancel", json={"reason": "Travelling"}, headers=H())
    assert r.status_code == 200 and r.json()["booking"]["status"] == "cancelled"
    # Someone else cannot touch it.
    assert client.post(f"/v1/bookings/{b['id']}/cancel", json={}, headers=H("tok-other")).status_code == 404


def test_messages_with_branch_and_head_office(client, store):
    r = client.post("/v1/threads/hq/messages", json={"text": "Is 20 Dec free for Bride Royal?"}, headers=H())
    assert r.status_code == 200
    client.post("/v1/threads/shp_gul/photo", files={"file": ("ref.jpg", b"\xff\xd8", "image/jpeg")}, data={"text": "My reference"}, headers=H())
    rows = run(store.list("messages"))
    assert {m["shopId"] for m in rows} == {None, "shp_gul"}
    # Staff reply from the POS.
    from app.core import stamped

    run(store.put("messages", stamped({"id": "msg_staff", "threadId": "u-ayesha:hq", "shopId": None, "accountId": "u-ayesha", "from": "staff", "authorName": "Hira",
                                        "text": "Yes, it is free!", "imagePath": None, "at": "2999-01-01T00:00:00.000Z", "readByStaff": True, "readByCustomer": False})))
    t = client.get("/v1/threads", headers=H()).json()
    hq = next(x for x in t["threads"] if x["key"] == "hq")
    assert hq["unread"] == 1 and hq["title"] == "Aura Concierge"
    msgs = client.get("/v1/threads/hq/messages", headers=H()).json()["messages"]
    assert [m["from"] for m in msgs] == ["customer", "staff"]
    assert client.get("/v1/threads", headers=H()).json()["threads"][0]["unread"] == 0
    photo = client.get("/v1/threads/shp_gul/messages", headers=H()).json()["messages"][0]
    assert photo["imageUrl"].startswith("memory://chat-images/u-ayesha/")


def test_gift_voucher_purchase(client, store):
    r = client.post("/v1/payments", json={"purpose": "voucher", "method": "easypaisa", "voucher": {"value": 5000, "recipientName": "Sara", "shopId": "shp_gul"}}, headers=H())
    assert r.status_code == 200, r.text
    tok = r.json()["payment"]["token"]
    client.get(f"/pay/{tok}/start?method=easypaisa")
    client.post(f"/pay/{tok}/simulate", data={"decision": "approve"})
    v = run(store.list("vouchers"))[0]
    assert v["initialValue"] == 5000 and v["code"].startswith("GV-") and v["paidBy"] == "easypaisa"
    w = client.get("/v1/wallet", headers=H()).json()
    assert w["vouchers"][0]["code"] == v["code"]


def test_website_guest_booking_and_enquiry(client, store):
    r = client.post("/v1/public/bookings", json={"name": "Hina", "phone": "0321 5556677", "shopId": "shp_gul", "serviceIds": ["svc_style"], "startAt": in_days(3, "12:00"), "payPlan": "advance", "returnUrl": "https://aurabyhs.pk/thank-you"})
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["total"] == 7200 and out["payAmount"] == 1440 and "/pay/" in out["payUrl"]
    assert run(store.get("appointments", out["bookingId"]))["notes"].endswith("Booked on the website")
    tok = out["payUrl"].rsplit("/", 1)[1]
    client.get(f"/pay/{tok}/start?method=jazzcash")
    client.post(f"/pay/{tok}/simulate", data={"decision": "approve"})
    page = client.get(f"/pay/{tok}/result").text
    assert "Back to the website" in page and "https://aurabyhs.pk/thank-you?payment=" in page
    e = client.post("/v1/public/enquiries", json={"name": "Sara", "phone": "03001112222", "interest": "Bride Royal"})
    assert e.status_code == 200 and run(store.list("enquiries"))[0]["status"] == "new"


def test_wallet_points_and_invoices(client, store):
    set_phone(client)
    b = book(client).json()["booking"]
    appt = run(store.get("appointments", b["id"]))
    from app.core import stamped

    run(store.put("sales", stamped({"id": "sal_9", "shopId": "shp_gul", "receiptNo": "GUL-1", "customerId": appt["customerId"], "customerName": "Ayesha",
                                     "items": [{"name": "Haircut", "kind": "service", "unitPrice": 3500, "quantity": 1, "discount": 0, "lineTotal": 3500}],
                                     "subtotal": 3500, "total": 3500, "status": "completed", "soldAt": "2026-10-01T10:00:00.000Z", "pointsEarned": 35,
                                     "payments": [{"method": "cash", "amount": 3500}], "balanceDue": 0})))
    w = client.get("/v1/wallet", headers=H()).json()
    assert w["points"] == 35 and w["tier"] == "Silver"
    inv = client.get("/v1/invoices", headers=H()).json()["invoices"]
    assert inv[0]["receiptNo"] == "GUL-1" and inv[0]["shopName"] == "Aura Gulberg"


def test_delete_account_cancels_upcoming(client, store):
    set_phone(client)
    b = book(client, days=3).json()["booking"]
    assert client.delete("/v1/me", headers=H()).status_code == 200
    assert run(store.get("appointments", b["id"]))["status"] == "cancelled"
    assert client.get("/v1/me", headers=H()).status_code == 403
