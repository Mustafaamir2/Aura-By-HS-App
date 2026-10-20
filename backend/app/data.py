"""Reading the POS's records the way the POS understands them."""
from __future__ import annotations

from typing import Any

from .core import bad, digits, not_found, now_iso, round2, stamped, uid
from .store import Store

DEFAULT_RULES = {
    "defaultDurationMin": 60,
    "slotIntervalMin": 30,
    "minAdvanceBookingMin": 60,
    "cancellationWindowHours": 4,
    "bufferMin": 0,
}

DEFAULT_ONLINE = {
    "enabled": True,
    # Share of the price asked up front when a customer books in the app.
    "advancePct": 20,
    "bridalAdvancePct": 30,
    # The smallest part-payment accepted.
    "minPartial": 500,
    "methods": {"jazzcash": True, "easypaisa": True, "card": True, "bank-transfer": True},
    "bank": {
        "bankName": "",
        "accountTitle": "",
        "accountNumber": "",
        "iban": "",
        "raastId": "",
    },
    # Where the POS sends payment links (this API's public address).
    "apiUrl": "",
}

DEFAULT_APP = {"playStoreUrl": "", "appStoreUrl": "", "websiteUrl": "", "whatsapp": ""}

PAY_METHODS = ("jazzcash", "easypaisa", "card", "bank-transfer")


async def settings(store: Store) -> dict[str, Any]:
    row = await store.get("app_settings", "global") or {}
    online = {**DEFAULT_ONLINE, **(row.get("onlinePayments") or {})}
    online["methods"] = {**DEFAULT_ONLINE["methods"], **(online.get("methods") or {})}
    online["bank"] = {**DEFAULT_ONLINE["bank"], **(online.get("bank") or {})}
    return {
        **row,
        "appointments": {**DEFAULT_RULES, **(row.get("appointments") or {})},
        "onlinePayments": online,
        "customerApp": {**DEFAULT_APP, **(row.get("customerApp") or {})},
        "business": row.get("business") or {"name": "Aura by HS"},
        "loyalty": row.get("loyalty") or {"enabled": True, "pointsPer100": 1, "pointValue": 1, "minRedeemPoints": 100},
    }


async def active_shop(store: Store, shop_id: str) -> dict:
    shop = await store.get("shops", shop_id)
    if not shop or not shop.get("active", True):
        raise not_found("That branch")
    return shop


async def services_by_id(store: Store) -> dict[str, dict]:
    return {s["id"]: s for s in await store.list("services")}


def public_staff(s: dict) -> dict:
    return {
        "id": s["id"],
        "name": s["name"],
        "role": s.get("role", ""),
        "shopId": s["shopId"],
        "photoUrl": s.get("photoUrl"),
        "specializations": s.get("specializations") or [],
    }


async def raise_notification(store: Store, shop_id: str, kind: str, title: str, message: str, link: str | None, severity: str = "info") -> None:
    """Puts a line in the branch's bell in the POS, as the POS's own services do."""
    cfg = await settings(store)
    if (cfg.get("notifications") or {}).get(kind) is False:
        return
    at = now_iso()
    await store.put(
        "notifications",
        {
            "id": uid("ntf"),
            "shopId": shop_id,
            "createdAt": at,
            "updatedAt": at,
            "type": kind,
            "title": title,
            "message": message,
            "read": False,
            "link": link,
            "severity": severity,
        },
    )


async def customer_at(store: Store, account: dict, shop_id: str) -> dict:
    """The customer record this account has at a branch — matched by phone, or created."""
    linked = (account.get("customerIds") or {}).get(shop_id)
    if linked:
        c = await store.get("customers", linked)
        if c:
            return c
    phone = digits(account.get("phone"))
    if len(phone) < 10:
        raise bad("Add your mobile number to your profile before booking.")
    match = next((c for c in await store.list("customers", shopId=shop_id) if digits(c.get("phone")) == phone), None)
    if match is None:
        match = stamped(
            {
                "id": uid("cus"),
                "shopId": shop_id,
                "name": account.get("name") or "App customer",
                "phone": phone,
                "email": account.get("email") or None,
                "gender": account.get("gender") or "female",
                "preferredStaffId": None,
                "preferredServiceIds": [],
                "sensitivities": account.get("allergies") or "",
                "notes": "Joined through the Aura app.",
                "active": True,
                "firstVisitOn": None,
                "birthday": account.get("birthday"),
                "anniversary": None,
            }
        )
        await store.put("customers", match)
        await raise_notification(store, shop_id, "customer-created", "New customer from the app", f"{match['name']} signed up in the Aura app.", f"/customers/{match['id']}")
    account["customerIds"] = {**(account.get("customerIds") or {}), shop_id: match["id"]}
    account["updatedAt"] = now_iso()
    await store.put("customer_accounts", account)
    return match


def customer_ids(account: dict) -> list[str]:
    return list((account.get("customerIds") or {}).values())


# ------------------------------------------------------------- money owed


def appointment_total(appt: dict) -> float:
    quoted = appt.get("quotedTotal")
    if isinstance(quoted, (int, float)):
        return float(quoted)
    return float(sum(s.get("price", 0) for s in appt.get("services") or []))


async def paid_towards(store: Store, purpose: str, ref_id: str) -> float:
    rows = await store.list("online_payments", refId=ref_id)
    return round2(sum(p["amount"] for p in rows if p.get("purpose") == purpose and p.get("status") == "paid"))


async def amount_owed(store: Store, purpose: str, ref: dict) -> tuple[float, float, float]:
    """(total, paid so far, still to pay) for something a customer can pay towards."""
    if purpose == "appointment":
        total = appointment_total(ref)
        if ref.get("saleId"):
            sale = await store.get("sales", ref["saleId"])
            if sale:
                return float(sale["total"]), round2(sale["total"] - (sale.get("balanceDue") or 0)), float(sale.get("balanceDue") or 0)
        credits = [c for c in await store.list("customer_credits", customerId=ref["customerId"]) if c.get("appointmentId") == ref["id"] and c.get("kind") == "advance"]
        paid = round2(sum(c["amount"] for c in credits))
        return total, paid, max(0.0, round2(total - paid))
    if purpose == "bridal":
        paid = round2(sum(p["amount"] * (-1 if p.get("kind") == "refund" else 1) for p in ref.get("payments") or []))
        return float(ref["total"]), paid, max(0.0, round2(ref["total"] - paid))
    if purpose == "sale":
        due = float(ref.get("balanceDue") or 0)
        return float(ref["total"]), round2(ref["total"] - due), due
    raise bad("Unknown payment purpose.")
