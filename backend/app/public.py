"""For the website: booking and enquiry forms that work without an account."""
from __future__ import annotations

import time
from collections import defaultdict, deque

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from . import availability as av
from .bookings import coupon_discount, parse_start, pick_staff
from .config import get_settings
from .core import ApiError, bad, digits, money, now_iso, round2, stamped, to_iso, tz, uid
from .data import active_shop, raise_notification, settings
from .payments import service
from .store import Store, get_store

router = APIRouter(prefix="/v1/public", tags=["website"])

_hits: dict[str, deque] = defaultdict(deque)


def limit(request: Request, per_hour: int = 20) -> None:
    """A small per-address brake so the open forms cannot be flooded."""
    ip = (request.headers.get("x-forwarded-for") or (request.client.host if request.client else "?")).split(",")[0].strip()
    q = _hits[ip]
    now = time.time()
    while q and q[0] < now - 3600:
        q.popleft()
    if len(q) >= per_hour:
        raise ApiError(429, "Too many requests — please call or WhatsApp us instead.")
    q.append(now)


class EnquiryIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    phone: str = Field(min_length=7, max_length=30)
    email: str = Field(default="", max_length=120)
    interest: str = Field(default="", max_length=200)
    preferredDate: str | None = Field(default=None, max_length=10)
    message: str = Field(default="", max_length=2000)
    shopId: str | None = None
    source: str = "website"


class GuestBookingIn(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    phone: str = Field(min_length=10, max_length=20)
    email: str = Field(default="", max_length=120)
    shopId: str
    serviceIds: list[str] = Field(min_length=1, max_length=12)
    staffId: str = "any"
    startAt: str
    notes: str = Field(default="", max_length=1000)
    couponCode: str | None = None
    # Ask for an advance online now: None = pay at the salon.
    payPlan: str | None = None
    # Website page the payment result sends the customer back to (https only).
    returnUrl: str | None = Field(default=None, max_length=300)


@router.get("/app-links")
async def app_links(store: Store = Depends(get_store)):
    return (await settings(store))["customerApp"]


@router.post("/enquiries")
async def enquiry(body: EnquiryIn, request: Request, store: Store = Depends(get_store)):
    limit(request)
    at = now_iso()
    row = {
        "id": uid("enq_web"), "createdAt": at, "updatedAt": at, "shopId": body.shopId, "name": body.name.strip(),
        "phone": body.phone.strip(), "email": body.email.strip(), "interest": body.interest.strip(),
        "preferredDate": body.preferredDate, "message": body.message.strip(),
        "source": body.source if body.source in ("website", "instagram", "facebook", "whatsapp", "phone", "referral") else "website",
        "status": "new", "notes": "", "followUpOn": None, "customerId": None, "bookingId": None,
    }
    await store.put("enquiries", row)
    return {"ok": True, "id": row["id"]}


@router.post("/bookings")
async def guest_booking(body: GuestBookingIn, request: Request, store: Store = Depends(get_store)):
    """Books straight into the branch diary from the website, without an app account."""
    limit(request, per_hour=10)
    phone = digits(body.phone)
    if not (len(phone) == 11 and phone.startswith("03")):
        raise bad("Enter a mobile number like 0300 1234567.")
    shop = await active_shop(store, body.shopId)
    catalogue = {s["id"]: s for s in await store.list("services")}
    chosen = [catalogue.get(i) for i in body.serviceIds]
    if not all(c and c.get("active", True) for c in chosen):
        raise bad("One of the chosen services is no longer offered.")
    start = parse_start(body.startAt)
    staff_id = await pick_staff(store, shop["id"], start, body.serviceIds, body.staffId)
    customer = next((c for c in await store.list("customers", shopId=shop["id"]) if digits(c.get("phone")) == phone), None)
    if customer is None:
        customer = stamped({"id": uid("cus"), "shopId": shop["id"], "name": body.name.strip(), "phone": phone, "email": body.email.strip() or None,
                            "gender": "female", "preferredStaffId": None, "preferredServiceIds": [], "sensitivities": "", "notes": "Booked on the website.",
                            "active": True, "firstVisitOn": None, "birthday": None, "anniversary": None})
        await store.put("customers", customer)
    services = [{"serviceId": s["id"], "price": av.unit_price(s), "durationMin": s["durationMin"]} for s in chosen]
    subtotal = float(sum(x["price"] for x in services))
    code, discount = await coupon_discount(store, body.couponCode, shop["id"], subtotal)
    at = now_iso()
    appt = stamped({
        "id": uid("apt"), "shopId": shop["id"], "customerId": customer["id"], "staffId": staff_id, "services": services,
        "startAt": to_iso(start), "durationMin": sum(x["durationMin"] for x in services), "status": "pending",
        "notes": " · ".join(x for x in [body.notes.strip(), f"Promo {code} (−{money(discount)})" if code else "", "Booked on the website"] if x),
        "cancelReason": None, "history": [{"status": "pending", "at": at, "byUserId": "website", "byUserName": f"{customer['name']} (website)", "note": None}],
        "saleId": None, "source": "online", "couponCode": code, "quotedTotal": round2(subtotal - discount),
    })
    await store.insert("appointments", appt)
    await raise_notification(store, shop["id"], "appointment-created", "New booking from the website",
                             f"{customer['name']} booked for {start.astimezone(tz()).strftime('%a %d %b, %I:%M %p')}.", f"/appointments?id={appt['id']}")
    out = {"ok": True, "bookingId": appt["id"], "total": round2(subtotal - discount), "startAt": appt["startAt"], "staffId": staff_id}
    if body.payPlan:
        ret = body.returnUrl if body.returnUrl and (body.returnUrl.startswith("https://") or body.returnUrl.startswith("http://localhost")) else None
        p = await service.create(store, purpose="appointment", ref_id=appt["id"], plan=body.payPlan, amount=None, method=None, created_by="website", channel="website", return_url=ret)
        out["payUrl"] = f"{get_settings().public_url}/pay/{p['token']}"
        out["payAmount"] = p["amount"]
    return out
