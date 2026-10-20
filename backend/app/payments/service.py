"""Online payments: requests for money and what a successful one changes.

A payment row (`online_payments`) is created by the app, the website or the POS
(as a shareable link). When it is paid — by a gateway callback, or by the POS
verifying a bank-transfer slip — the money lands on the same record a cashier
would have used:

* appointment → an advance on the customer's account (`customer_credits`),
  which the till offers automatically at checkout; a pending booking is confirmed
* bridal      → a payment line on the bridal booking; the advance confirms it
* sale        → a payment against the bill's balance ("udhaar")
* voucher     → a new gift voucher

The POS has the same rules for slips it verifies (src/services/onlinePaymentService.ts).
"""
from __future__ import annotations

import random
import string
from datetime import datetime, timedelta, timezone

from ..core import ApiError, bad, money, not_found, now_iso, parse_iso, round2, stamped, to_iso, token, uid
from ..data import amount_owed, appointment_total, raise_notification, settings
from ..store import Store

PURPOSES = ("appointment", "bridal", "sale", "voucher")
PLANS = ("advance", "full", "partial", "balance", "custom")
METHOD_LABEL = {"jazzcash": "JazzCash", "easypaisa": "Easypaisa", "card": "Card", "bank-transfer": "Bank transfer"}
OPEN = ("pending", "processing", "failed")


def payment_no() -> str:
    return "PAY-" + datetime.now(timezone.utc).strftime("%y%m%d") + "-" + "".join(random.choice(string.ascii_uppercase + string.digits) for _ in range(5))


async def target(store: Store, purpose: str, ref_id: str) -> dict:
    table = {"appointment": "appointments", "bridal": "bridal_bookings", "sale": "sales"}[purpose]
    row = await store.get(table, ref_id)
    if not row:
        raise not_found({"appointment": "That booking", "bridal": "That bridal booking", "sale": "That bill"}[purpose])
    return row


async def ref_label(store: Store, purpose: str, ref: dict) -> str:
    if purpose == "appointment":
        svc = {s["id"]: s for s in await store.list("services")}
        names = " + ".join(svc.get(x["serviceId"], {}).get("name", "Service") for x in ref.get("services") or []) or "Appointment"
        return names
    if purpose == "bridal":
        return f"{ref.get('packageName', 'Bridal booking')} · {ref.get('bookingNo', '')}".strip(" ·")
    if purpose == "sale":
        return f"Bill {ref.get('receiptNo', '')}"
    return "Payment"


async def plan_amount(store: Store, purpose: str, ref: dict, plan: str, amount: float | None) -> float:
    cfg = (await settings(store))["onlinePayments"]
    total, paid, left = await amount_owed(store, purpose, ref)
    if left <= 0:
        raise ApiError(409, "Nothing is left to pay on this.")
    if plan == "advance":
        if purpose == "bridal":
            want = round2(ref.get("advanceRequired") or total * cfg["bridalAdvancePct"] / 100) - paid
        else:
            want = round2(total * cfg["advancePct"] / 100) - paid
        if want <= 0:
            raise ApiError(409, "The advance is already paid. Choose full or part payment instead.")
        return round2(min(want, left))
    if plan in ("full", "balance"):
        return left
    if plan in ("partial", "custom"):
        if amount is None:
            raise bad("Enter how much you would like to pay.")
        amount = round2(amount)
        if amount < min(cfg["minPartial"], left):
            raise bad(f"The smallest payment is {money(min(cfg['minPartial'], left))}.")
        if amount > left + 0.001:
            raise bad(f"Only {money(left)} is left to pay.")
        return amount
    raise bad("Choose advance, full or part payment.")


async def create(
    store: Store,
    *,
    purpose: str,
    ref_id: str | None,
    plan: str,
    amount: float | None,
    method: str | None,
    created_by: str,
    channel: str,
    account: dict | None = None,
    shop_id: str | None = None,
    voucher: dict | None = None,
    return_url: str | None = None,
) -> dict:
    if purpose not in PURPOSES:
        raise bad("Unknown payment purpose.")
    cfg = (await settings(store))["onlinePayments"]
    if not cfg.get("enabled", True):
        raise ApiError(403, "Online payments are switched off. Please pay at the salon.")
    if method is not None and method not in METHOD_LABEL:
        raise bad("Choose JazzCash, Easypaisa, card or bank transfer.")
    if method and not cfg["methods"].get(method, False):
        raise bad(f"{METHOD_LABEL[method]} is not available right now.")

    customer_id = None
    customer_name = (account or {}).get("name", "")
    customer_phone = (account or {}).get("phone", "")
    if purpose == "voucher":
        if not voucher or not shop_id:
            raise bad("Choose the voucher value and branch.")
        value = round2(voucher.get("value") or 0)
        if value < 500:
            raise bad("Gift vouchers start at Rs 500.")
        amt, label, ref_id = value, f"Gift voucher for {voucher.get('recipientName') or 'someone special'}", None
        plan = "full"
    else:
        if not ref_id:
            raise bad("Missing what this payment is for.")
        ref = await target(store, purpose, ref_id)
        shop_id = ref["shopId"]
        if account is not None and ref.get("customerId") not in (account.get("customerIds") or {}).values():
            raise ApiError(403, "That booking is not on your account.")
        if purpose == "appointment" and ref.get("status") in ("cancelled", "no-show"):
            raise ApiError(409, "This booking was cancelled.")
        if purpose == "bridal" and ref.get("status") == "cancelled":
            raise ApiError(409, "This bridal booking was cancelled.")
        customer_id = ref.get("customerId")
        if customer_id:
            c = await store.get("customers", customer_id)
            if c:
                customer_name, customer_phone = c.get("name", customer_name), c.get("phone", customer_phone)
        amt = await plan_amount(store, purpose, ref, plan, amount)
        label = await ref_label(store, purpose, ref)

    row = stamped(
        {
            "id": uid("opy"),
            "paymentNo": payment_no(),
            "shopId": shop_id,
            "purpose": purpose,
            "refId": ref_id,
            "refLabel": label,
            "customerId": customer_id,
            "customerName": customer_name,
            "customerPhone": customer_phone,
            "accountId": (account or {}).get("id"),
            "plan": plan,
            "amount": amt,
            "method": method,
            "status": "pending",
            "token": token(),
            "gateway": None,
            "gatewayRef": None,
            "gatewayMessage": None,
            "slipPath": None,
            "payerNote": "",
            "paidAt": None,
            "verifiedBy": None,
            "rejectReason": None,
            "createdBy": created_by,
            "channel": channel,
            "expiresAt": to_iso(datetime.now(timezone.utc) + timedelta(days=3)),
            "appliedAt": None,
            "voucher": voucher if purpose == "voucher" else None,
            # Where the result page's button goes (the website); the app deep link otherwise.
            "returnUrl": return_url,
            "attempts": [],
        }
    )
    await store.put("online_payments", row)
    return row


async def by_token(store: Store, tok: str) -> dict:
    rows = await store.list("online_payments", token=tok)
    if not rows:
        raise not_found("That payment link")
    p = rows[0]
    if p["status"] in OPEN and p.get("expiresAt") and parse_iso(p["expiresAt"]) < datetime.now(timezone.utc):
        p = {**p, "status": "expired", "updatedAt": now_iso()}
        await store.put("online_payments", p)
    return p


def can_pay(p: dict) -> bool:
    return p["status"] in OPEN


async def record_attempt(store: Store, p: dict, **fields) -> dict:
    p = {**p, **fields, "updatedAt": now_iso()}
    p["attempts"] = [*(p.get("attempts") or []), {"at": now_iso(), **{k: fields.get(k) for k in ("method", "gateway", "status", "gatewayRef", "gatewayMessage")}}][-20:]
    await store.put("online_payments", p)
    return p


async def settle(store: Store, p: dict, *, status: str, gateway: str, gateway_ref: str | None, message: str | None, by: str = "Online") -> dict:
    """Records a gateway result. Paying twice (a callback replayed) changes nothing."""
    fresh = await store.get("online_payments", p["id"]) or p
    if fresh.get("appliedAt"):
        return fresh
    if status not in ("paid", "processing", "failed"):
        raise ValueError(status)
    fresh = await record_attempt(store, fresh, status=status, gateway=gateway, gatewayRef=gateway_ref, gatewayMessage=message, method=fresh.get("method"))
    if status == "paid":
        fresh = await apply_paid(store, {**fresh, "paidAt": now_iso(), "verifiedBy": by})
    return fresh


def _pos_method(method: str | None) -> str:
    return method if method in ("jazzcash", "easypaisa", "card", "bank-transfer") else "other"


async def apply_paid(store: Store, p: dict) -> dict:
    at = now_iso()
    method = _pos_method(p.get("method"))
    ref_note = f"Online {p['paymentNo']} · {METHOD_LABEL.get(p.get('method') or '', 'online')}" + (f" · ref {p['gatewayRef']}" if p.get("gatewayRef") else "")
    purpose = p["purpose"]

    if purpose == "appointment":
        appt = await store.get("appointments", p["refId"])
        if appt:
            await store.put(
                "customer_credits",
                stamped(
                    {
                        "id": uid("crd"),
                        "shopId": appt["shopId"],
                        "customerId": appt["customerId"],
                        "amount": p["amount"],
                        "kind": "advance",
                        "method": method,
                        "appointmentId": appt["id"],
                        "saleId": None,
                        "note": ref_note,
                        "byUserName": p.get("verifiedBy") or "Online",
                        "onlinePaymentId": p["id"],
                    }
                ),
            )
            if appt.get("status") == "pending":
                appt = {
                    **appt,
                    "status": "confirmed",
                    "updatedAt": at,
                    "history": [*(appt.get("history") or []), {"status": "confirmed", "at": at, "byUserId": "online", "byUserName": "Online payment", "note": f"{money(p['amount'])} paid by {METHOD_LABEL.get(p.get('method') or '', 'online')}"}],
                }
                await store.put("appointments", appt)

    elif purpose == "bridal":
        b = await store.get("bridal_bookings", p["refId"])
        if b:
            paid = round2(sum(x["amount"] * (-1 if x.get("kind") == "refund" else 1) for x in b.get("payments") or []))
            kind = "advance" if paid == 0 else ("final" if paid + p["amount"] >= b["total"] - 0.001 else "instalment")
            status = b["status"]
            if status == "tentative" and paid + p["amount"] >= (b.get("advanceRequired") or 0):
                status = "confirmed"
            b = {
                **b,
                "status": status,
                "updatedAt": at,
                "payments": [*(b.get("payments") or []), {"id": uid("bpy"), "at": at, "amount": p["amount"], "method": method, "kind": kind, "note": ref_note, "byUserName": p.get("verifiedBy") or "Online"}],
            }
            await store.put("bridal_bookings", b)

    elif purpose == "sale":
        s = await store.get("sales", p["refId"])
        if s:
            due = float(s.get("balanceDue") or 0)
            amount = min(p["amount"], due)
            s = {
                **s,
                "updatedAt": at,
                "balanceDue": round2(due - amount),
                "payments": [*(s.get("payments") or []), {"id": uid("pay"), "method": method, "amount": amount, "tendered": None, "reference": ref_note, "at": at, "byUserName": p.get("verifiedBy") or "Online"}],
            }
            await store.put("sales", s)

    elif purpose == "voucher":
        v = p.get("voucher") or {}
        code = await _voucher_code(store)
        voucher = stamped(
            {
                "id": uid("vch"),
                "shopId": p["shopId"],
                "code": code,
                "initialValue": p["amount"],
                "balance": p["amount"],
                "recipientName": v.get("recipientName") or "",
                "recipientPhone": v.get("recipientPhone") or "",
                "purchasedBy": p.get("customerName") or "App customer",
                "paidBy": method,
                "expiresOn": (datetime.now(timezone.utc) + timedelta(days=365)).date().isoformat(),
                "active": True,
                "notes": ref_note,
            }
        )
        await store.put("vouchers", voucher)
        p = {**p, "voucher": {**v, "code": code, "voucherId": voucher["id"]}}

    p = {**p, "status": "paid", "appliedAt": at, "updatedAt": at}
    await store.put("online_payments", p)
    await raise_notification(
        store,
        p["shopId"],
        "payment-completed",
        "Online payment received",
        f"{p.get('customerName') or 'A customer'} paid {money(p['amount'])} by {METHOD_LABEL.get(p.get('method') or '', 'online')} — {p.get('refLabel', '')}.",
        f"/online-payments?id={p['id']}",
        "success",
    )
    return p


async def _voucher_code(store: Store) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    taken = {v.get("code", "").upper() for v in await store.list("vouchers")}
    while True:
        code = "GV-" + "".join(random.choice(alphabet) for _ in range(6))
        if code not in taken:
            return code


def public_view(p: dict) -> dict:
    """What the customer may see about a payment."""
    keys = ("id", "paymentNo", "purpose", "refId", "refLabel", "plan", "amount", "method", "status", "gateway", "gatewayRef", "gatewayMessage", "paidAt", "rejectReason", "createdAt", "token", "shopId")
    out = {k: p.get(k) for k in keys}
    if p.get("purpose") == "voucher":
        out["voucher"] = p.get("voucher")
    return out


_ = appointment_total  # re-exported for callers that build quotes
