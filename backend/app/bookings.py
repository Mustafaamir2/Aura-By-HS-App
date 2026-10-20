"""A customer's bookings, bridal bookings, bills and wallet."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from . import availability as av
from .auth import current_account
from .catalog import free_slots
from .core import ApiError, bad, conflict, local_now, money, not_found, now_iso, parse_iso, round2, stamped, to_iso, tz, uid
from .data import active_shop, amount_owed, appointment_total, customer_at, customer_ids, raise_notification, settings
from .payments.service import public_view
from .store import Store, get_store

router = APIRouter(prefix="/v1", tags=["bookings"])

OPEN_STATUSES = ("pending", "confirmed")


class BookingIn(BaseModel):
    shopId: str
    serviceIds: list[str] = Field(min_length=1, max_length=12)
    staffId: str = "any"
    startAt: str
    notes: str = Field(default="", max_length=1000)
    couponCode: str | None = Field(default=None, max_length=30)


class CancelIn(BaseModel):
    reason: str = Field(default="", max_length=300)


class RescheduleIn(BaseModel):
    startAt: str
    staffId: str | None = None


class ReviewIn(BaseModel):
    rating: int = Field(ge=1, le=5)
    comment: str = Field(default="", max_length=1000)


class BridalIn(BaseModel):
    shopId: str
    packageId: str
    events: list[dict] = Field(min_length=1, max_length=8)
    location: str = "salon"
    venue: str = Field(default="", max_length=300)
    notes: str = Field(default="", max_length=1000)


# ----------------------------------------------------------------- helpers


async def coupon_discount(store: Store, code: str | None, shop_id: str, subtotal: float) -> tuple[str | None, float]:
    if not code:
        return None, 0.0
    code = code.strip().upper()
    c = next((x for x in await store.list("coupons") if (x.get("code") or "").upper() == code), None)
    today = local_now().date().isoformat()
    if not c or not c.get("active"):
        raise bad("That promo code isn’t valid.")
    if (c.get("startsOn") and c["startsOn"] > today) or (c.get("endsOn") and c["endsOn"] < today):
        raise bad("That promo code has expired.")
    if c.get("shopId") and c["shopId"] != shop_id:
        raise bad("That promo code is for another branch.")
    if subtotal < (c.get("minSpend") or 0):
        raise bad(f"Spend {money(c['minSpend'])} or more to use {code}.")
    if c.get("maxUses"):
        used = sum(1 for s in await store.list("sales") if (s.get("couponCode") or "").upper() == code and s.get("status") == "completed")
        if used >= c["maxUses"]:
            raise bad("That promo code has been fully used.")
    off = subtotal * c["value"] / 100 if c["mode"] == "percent" else c["value"]
    return code, round2(min(subtotal, off))


async def booking_view(store: Store, a: dict, names: dict, cfg: dict) -> dict:
    total, paid, due = await amount_owed(store, "appointment", a)
    pays = [public_view(p) for p in await store.list("online_payments", refId=a["id"]) if p.get("purpose") == "appointment"]
    start = parse_iso(a["startAt"])
    hours_left = (start - datetime.now(timezone.utc)).total_seconds() / 3600
    window = cfg["appointments"]["cancellationWindowHours"]
    review = next((f for f in names["feedback"] if f.get("appointmentId") == a["id"]), None)
    sale = names["sales"].get(a.get("saleId") or "")
    return {
        "kind": "appointment",
        "id": a["id"],
        "shopId": a["shopId"],
        "shopName": names["shops"].get(a["shopId"], {}).get("name", ""),
        "staffId": a.get("staffId"),
        "staffName": names["staff"].get(a.get("staffId"), {}).get("name", ""),
        "services": [{**s, "name": names["services"].get(s["serviceId"], {}).get("name", "Service")} for s in a.get("services") or []],
        "startAt": a["startAt"],
        "durationMin": a.get("durationMin"),
        "status": a["status"],
        "notes": a.get("notes", ""),
        "cancelReason": a.get("cancelReason"),
        "couponCode": a.get("couponCode"),
        "total": total,
        "paid": paid,
        "due": due,
        "payments": pays,
        "canCancel": a["status"] in OPEN_STATUSES and hours_left >= window,
        "canReschedule": a["status"] in OPEN_STATUSES and hours_left >= window,
        "canPay": a["status"] in OPEN_STATUSES + ("checked-in", "in-progress", "completed") and due > 0,
        "canReview": a["status"] == "completed" and review is None,
        "review": {"rating": review["rating"], "comment": review.get("comment", "")} if review else None,
        "receiptNo": sale.get("receiptNo") if sale else None,
        "bridalBookingId": a.get("bridalBookingId"),
    }


def bridal_view(b: dict, names: dict, pays: list[dict]) -> dict:
    paid = round2(sum(p["amount"] * (-1 if p.get("kind") == "refund" else 1) for p in b.get("payments") or []))
    return {
        "kind": "bridal",
        "id": b["id"],
        "bookingNo": b.get("bookingNo"),
        "shopId": b["shopId"],
        "shopName": names["shops"].get(b["shopId"], {}).get("name", ""),
        "packageName": b.get("packageName"),
        "status": b["status"],
        "total": b["total"],
        "paid": paid,
        "due": max(0, round2(b["total"] - paid)),
        "advanceRequired": b.get("advanceRequired", 0),
        "advanceDue": max(0, round2((b.get("advanceRequired") or 0) - paid)),
        "events": [
            {k: e.get(k) for k in ("id", "type", "date", "readyBy", "location", "venue", "status")}
            | {"artistName": names["staff"].get(e.get("artistId"), {}).get("name") if e.get("artistId") else None}
            for e in b.get("events") or []
        ],
        "payments": [{k: p.get(k) for k in ("id", "at", "amount", "method", "kind")} for p in b.get("payments") or []],
        "onlinePayments": pays,
        "canPay": b["status"] in ("tentative", "confirmed") and paid < b["total"],
        "notes": b.get("notes", ""),
    }


async def lookups(store: Store) -> dict:
    return {
        "shops": {s["id"]: s for s in await store.list("shops")},
        "staff": {s["id"]: s for s in await store.list("staff")},
        "services": {s["id"]: s for s in await store.list("services")},
        "feedback": await store.list("feedback"),
        "sales": {s["id"]: s for s in await store.list("sales")},
    }


async def own_appointment(store: Store, acc: dict, id: str) -> dict:
    a = await store.get("appointments", id)
    if not a or a.get("customerId") not in customer_ids(acc):
        raise not_found("That booking")
    return a


def parse_start(value: str):
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise bad("Pick a time from the list.") from exc
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=tz())
    return dt


async def pick_staff(store: Store, shop_id: str, start, service_ids: list[str], staff_id: str, exclude: str | None = None) -> str:
    slots = await free_slots(store, shop_id, start.astimezone(tz()).date(), service_ids, staff_id if staff_id != "any" else None, exclude)
    hhmm = start.astimezone(tz()).strftime("%H:%M")
    hit = next((s for s in slots if s["time"] == hhmm and s["available"]), None)
    if not hit:
        reason = next((s.get("reasonLabel") for s in slots if s["time"] == hhmm), None)
        raise conflict(reason or "That time is no longer free. Please pick another.")
    if staff_id != "any":
        return staff_id
    # Spread work: the free artist with the fewest bookings that day.
    day = start.astimezone(tz()).date()
    load = {sid: 0 for sid in hit["staffIds"]}
    for a in await store.list("appointments", shopId=shop_id):
        if a.get("staffId") in load and a.get("status") in av.BLOCKING and parse_iso(a["startAt"]).astimezone(tz()).date() == day:
            load[a["staffId"]] += 1
    return min(load, key=lambda k: (load[k], k))


# ------------------------------------------------------------------ routes


@router.get("/bookings")
async def my_bookings(acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    cfg = await settings(store)
    names = await lookups(store)
    ids = customer_ids(acc)
    appts = [a for a in await store.list("appointments", customerId=ids) if not a.get("bridalBookingId")] if ids else []
    appts.sort(key=lambda a: a["startAt"], reverse=True)
    bridal = await store.list("bridal_bookings", customerId=ids) if ids else []
    pays = await store.list("online_payments", accountId=acc["id"])
    return {
        "appointments": [await booking_view(store, a, names, cfg) for a in appts],
        "bridal": [bridal_view(b, names, [public_view(p) for p in pays if p.get("refId") == b["id"]]) for b in sorted(bridal, key=lambda b: b.get("createdAt", ""), reverse=True)],
    }


@router.post("/bookings")
async def book(body: BookingIn, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    shop = await active_shop(store, body.shopId)
    cfg = await settings(store)
    catalogue = {s["id"]: s for s in await store.list("services")}
    chosen = []
    for sid in body.serviceIds:
        s = catalogue.get(sid)
        if not s or not s.get("active", True):
            raise bad("One of the chosen services is no longer offered.")
        chosen.append(s)
    start = parse_start(body.startAt)
    staff_id = await pick_staff(store, shop["id"], start, body.serviceIds, body.staffId)
    customer = await customer_at(store, acc, shop["id"])
    services = [{"serviceId": s["id"], "price": av.unit_price(s), "durationMin": s["durationMin"]} for s in chosen]
    subtotal = float(sum(x["price"] for x in services))
    code, discount = await coupon_discount(store, body.couponCode, shop["id"], subtotal)
    at = now_iso()
    notes = " · ".join(x for x in [body.notes.strip(), f"Promo {code} (−{money(discount)})" if code else "", "Booked in the Aura app"] if x)
    appt = stamped(
        {
            "id": uid("apt"),
            "shopId": shop["id"],
            "customerId": customer["id"],
            "staffId": staff_id,
            "services": services,
            "startAt": to_iso(start),
            "durationMin": sum(x["durationMin"] for x in services),
            "status": "pending",
            "notes": notes,
            "cancelReason": None,
            "history": [{"status": "pending", "at": at, "byUserId": acc["id"], "byUserName": f"{customer['name']} (app)", "note": None}],
            "saleId": None,
            "source": "online",
            "couponCode": code,
            "quotedTotal": round2(subtotal - discount),
            "accountId": acc["id"],
        }
    )
    await store.insert("appointments", appt)
    local = start.astimezone(tz())
    await raise_notification(store, shop["id"], "appointment-created", "New booking from the app", f"{customer['name']} booked for {local.strftime('%a %d %b, %I:%M %p')}.", f"/appointments?id={appt['id']}")
    names = await lookups(store)
    online = cfg["onlinePayments"]
    view = await booking_view(store, appt, names, cfg)
    return {
        "booking": view,
        "quote": {
            "subtotal": subtotal,
            "discount": discount,
            "total": round2(subtotal - discount),
            "advance": round2((subtotal - discount) * online["advancePct"] / 100),
            "advancePct": online["advancePct"],
        },
    }


@router.post("/bookings/{id}/cancel")
async def cancel(id: str, body: CancelIn, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    a = await own_appointment(store, acc, id)
    cfg = await settings(store)
    if a["status"] not in OPEN_STATUSES:
        raise conflict("This booking can no longer be cancelled.")
    window = cfg["appointments"]["cancellationWindowHours"]
    if parse_iso(a["startAt"]) - datetime.now(timezone.utc) < timedelta(hours=window):
        raise conflict(f"Bookings can be cancelled in the app up to {window} hours before. Please call the salon.")
    at = now_iso()
    reason = body.reason.strip() or "Cancelled by the customer in the app"
    a = {**a, "status": "cancelled", "cancelReason": reason, "updatedAt": at,
         "history": [*(a.get("history") or []), {"status": "cancelled", "at": at, "byUserId": acc["id"], "byUserName": "Customer (app)", "note": reason}]}
    await store.put("appointments", a)
    _, paid, _ = await amount_owed(store, "appointment", a)
    await raise_notification(store, a["shopId"], "appointment-cancelled", "Booking cancelled in the app", f"{acc.get('name')} cancelled their {parse_iso(a['startAt']).astimezone(tz()).strftime('%a %d %b, %I:%M %p')} booking." + (f" {money(paid)} advance is on their account." if paid else ""), f"/appointments?id={a['id']}", "warning")
    names = await lookups(store)
    return {"booking": await booking_view(store, a, names, cfg), "advanceHeld": paid}


@router.post("/bookings/{id}/reschedule")
async def reschedule(id: str, body: RescheduleIn, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    a = await own_appointment(store, acc, id)
    cfg = await settings(store)
    if a["status"] not in OPEN_STATUSES:
        raise conflict("This booking can no longer be moved.")
    window = cfg["appointments"]["cancellationWindowHours"]
    if parse_iso(a["startAt"]) - datetime.now(timezone.utc) < timedelta(hours=window):
        raise conflict(f"Bookings can be moved in the app up to {window} hours before. Please call the salon.")
    start = parse_start(body.startAt)
    staff_id = await pick_staff(store, a["shopId"], start, [s["serviceId"] for s in a["services"]], body.staffId or a["staffId"], exclude=a["id"])
    at = now_iso()
    old = parse_iso(a["startAt"]).astimezone(tz()).strftime("%a %d %b, %I:%M %p")
    a = {**a, "startAt": to_iso(start), "staffId": staff_id, "updatedAt": at,
         "history": [*(a.get("history") or []), {"status": a["status"], "at": at, "byUserId": acc["id"], "byUserName": "Customer (app)", "note": f"Moved from {old}"}]}
    await store.put("appointments", a)
    await raise_notification(store, a["shopId"], "appointment-rescheduled", "Booking moved in the app", f"{acc.get('name')} moved their booking from {old} to {start.astimezone(tz()).strftime('%a %d %b, %I:%M %p')}.", f"/appointments?id={a['id']}")
    return {"booking": await booking_view(store, a, await lookups(store), cfg)}


@router.post("/bookings/{id}/review")
async def review(id: str, body: ReviewIn, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    a = await own_appointment(store, acc, id)
    if a["status"] != "completed":
        raise conflict("You can rate a visit once it is completed.")
    if any(f.get("appointmentId") == id for f in await store.list("feedback", shopId=a["shopId"])):
        raise conflict("You have already rated this visit. Thank you!")
    c = await store.get("customers", a["customerId"])
    fb = stamped({"id": uid("fbk"), "shopId": a["shopId"], "customerId": a["customerId"], "customerName": (c or {}).get("name", acc.get("name", "")),
                  "saleId": a.get("saleId"), "staffId": a.get("staffId"), "rating": body.rating, "comment": body.comment.strip(), "appointmentId": id, "source": "app"})
    await store.put("feedback", fb)
    return {"ok": True}


@router.post("/bridal")
async def book_bridal(body: BridalIn, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    shop = await active_shop(store, body.shopId)
    pkg = await store.get("packages", body.packageId)
    if not pkg or not pkg.get("active", True):
        raise not_found("That package")
    cfg = await settings(store)
    types = {"Trial", "Engagement", "Dholki", "Mayun", "Mehndi", "Nikah", "Barat", "Walima", "Photoshoot", "Other"}
    today = local_now().date().isoformat()
    events = []
    for e in body.events:
        t, d = str(e.get("type") or "Barat"), str(e.get("date") or "")
        if t not in types:
            raise bad(f"Unknown event “{t}”.")
        if not d or d < today:
            raise bad(f"Pick a future date for the {t}.")
        events.append({"id": uid("bev"), "type": t, "date": d, "readyBy": str(e.get("readyBy") or "18:00")[:5], "durationMin": 240,
                       "artistId": None, "location": "on-location" if body.location == "on-location" else "salon", "venue": body.venue.strip(),
                       "lookNotes": str(e.get("notes") or "")[:300], "appointmentId": None, "status": "scheduled"})
    if body.location == "on-location" and not body.venue.strip():
        raise bad("Add the venue address for on-location service.")
    customer = await customer_at(store, acc, shop["id"])
    year = local_now().year
    prefix = f"BR-{shop.get('code') or 'AUR'}-{year}-"
    n = max([int(b["bookingNo"][len(prefix):]) for b in await store.list("bridal_bookings", shopId=shop["id"]) if str(b.get("bookingNo", "")).startswith(prefix) and b["bookingNo"][len(prefix):].isdigit()] or [0])
    total = round2(pkg["price"])
    b = stamped({
        "id": uid("brd"), "shopId": shop["id"], "bookingNo": f"{prefix}{n + 1:04d}", "customerId": customer["id"], "brideName": customer["name"], "phone": customer["phone"],
        "packageId": pkg["id"], "packageName": pkg["name"], "packagePrice": total, "extras": [], "travelCharge": 0, "discount": 0, "total": total,
        "events": events, "payments": [], "status": "tentative", "advanceRequired": round2(total * cfg["onlinePayments"]["bridalAdvancePct"] / 100),
        "notes": " · ".join(x for x in [body.notes.strip(), "Requested in the Aura app — assign artists and confirm times."] if x), "cancelReason": None, "saleId": None, "accountId": acc["id"],
    })
    await store.put("bridal_bookings", b)
    await raise_notification(store, shop["id"], "appointment-created", "New bridal booking from the app", f"{customer['name']} requested {pkg['name']} for {', '.join(e['type'] + ' ' + e['date'] for e in events)}.", f"/bridal/{b['id']}", "success")
    return {"bridal": bridal_view(b, await lookups(store), [])}


@router.get("/invoices")
async def invoices(acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    ids = customer_ids(acc)
    names = await lookups(store)
    sales = await store.list("sales", customerId=ids) if ids else []
    out = []
    for s in sorted(sales, key=lambda x: x.get("soldAt", ""), reverse=True):
        shop = names["shops"].get(s["shopId"], {})
        out.append({k: s.get(k) for k in ("id", "receiptNo", "soldAt", "subtotal", "itemDiscountTotal", "billDiscount", "membershipDiscount", "taxAmount", "total", "status", "balanceDue", "pointsEarned", "couponCode", "tip")}
                   | {"shopName": shop.get("name", ""), "shopAddress": shop.get("addressLine", ""), "shopPhone": shop.get("phone", ""),
                      "items": [{k: i.get(k) for k in ("name", "kind", "unitPrice", "quantity", "discount", "lineTotal")} for i in s.get("items") or []],
                      "payments": [{k: p.get(k) for k in ("method", "amount", "at")} for p in s.get("payments") or []]})
    return {"invoices": out}


@router.get("/wallet")
async def wallet(acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    cfg = await settings(store)
    ids = customer_ids(acc)
    points = 0.0
    for s in await store.list("sales", customerId=ids) if ids else []:
        if s.get("status") != "completed":
            continue
        points += s.get("pointsEarned") or 0
        for p in s.get("payments") or []:
            if p.get("method") == "points":
                try:
                    points -= float(p.get("reference") or 0)
                except ValueError:
                    pass
    credits = await store.list("customer_credits", customerId=ids) if ids else []
    vouchers = []
    for p in await store.list("online_payments", accountId=acc["id"]):
        if p.get("purpose") == "voucher" and p.get("status") == "paid" and (p.get("voucher") or {}).get("voucherId"):
            v = await store.get("vouchers", p["voucher"]["voucherId"])
            if v:
                vouchers.append({k: v.get(k) for k in ("id", "code", "initialValue", "balance", "recipientName", "recipientPhone", "expiresOn", "active")})
    mems = []
    for m in await store.list("customer_memberships", customerId=ids) if ids else []:
        if m.get("status") == "active" and m.get("expiresOn", "") >= local_now().date().isoformat():
            t = await store.get("memberships", m["membershipId"])
            mems.append({"name": (t or {}).get("name", "Member"), "discountPct": (t or {}).get("discountPct", 0), "expiresOn": m["expiresOn"]})
    loyalty = cfg["loyalty"]
    pts = max(0, int(points))
    payments = sorted([public_view(p) for p in await store.list("online_payments", accountId=acc["id"])], key=lambda p: p["createdAt"], reverse=True)
    return {
        "points": pts,
        "pointValue": loyalty.get("pointValue", 1),
        "pointsWorth": round2(pts * loyalty.get("pointValue", 1)),
        "minRedeemPoints": loyalty.get("minRedeemPoints", 0),
        "credit": round2(sum(c["amount"] for c in credits)),
        "memberships": mems,
        "tier": mems[0]["name"] if mems else ("Gold" if pts >= 2000 else "Silver"),
        "vouchers": vouchers,
        "payments": payments,
    }


_ = (ApiError, appointment_total)
