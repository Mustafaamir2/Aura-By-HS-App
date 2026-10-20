"""Public catalogue and free times — no sign-in needed, so guests can browse."""
from __future__ import annotations

from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, Query

from . import availability as av
from .core import bad, local_now, parse_iso, tz
from .data import PAY_METHODS, active_shop, public_staff, settings
from .store import Store, get_store

router = APIRouter(prefix="/v1", tags=["catalogue"])


def _shop(s: dict) -> dict:
    keys = ("id", "name", "code", "addressLine", "city", "phone", "email", "logoUrl", "businessHours", "active")
    return {k: s.get(k) for k in keys}


def _is_open(shop: dict, now: datetime) -> bool:
    wd = av.js_weekday(now.date())
    h = next((x for x in shop.get("businessHours") or [] if x["weekday"] == wd), None)
    if not h or h.get("closed"):
        return False
    m = now.hour * 60 + now.minute
    return av.clock(h["open"]) <= m < av.clock(h["close"])


def _active_coupons(rows: list[dict], today: str) -> list[dict]:
    out = []
    for c in rows:
        if not c.get("active"):
            continue
        if c.get("startsOn") and c["startsOn"] > today:
            continue
        if c.get("endsOn") and c["endsOn"] < today:
            continue
        out.append({k: c.get(k) for k in ("id", "code", "name", "mode", "value", "minSpend", "endsOn", "shopId")})
    return out


@router.get("/catalog")
async def catalog(store: Store = Depends(get_store)):
    cfg = await settings(store)
    now = local_now()
    today = now.date().isoformat()
    shops = [s for s in await store.list("shops") if s.get("active", True)]
    ratings: dict[str, list[int]] = {}
    for f in await store.list("feedback"):
        if f.get("staffId"):
            ratings.setdefault(f["staffId"], []).append(int(f.get("rating") or 0))
    staff = [
        public_staff(s) | {"rating": round(sum(ratings.get(s["id"], [])) / len(ratings[s["id"]]), 1) if ratings.get(s["id"]) else None, "reviews": len(ratings.get(s["id"], []))}
        for s in await store.list("staff")
        if s.get("active", True)
    ]
    online = cfg["onlinePayments"]
    announcements = sorted(
        [a for a in await store.list("announcements") if a.get("active", True)], key=lambda a: a.get("createdAt", ""), reverse=True
    )
    return {
        "business": cfg["business"],
        "shops": [{**_shop(s), "isOpenNow": _is_open(s, now)} for s in shops],
        "categories": sorted([c for c in await store.list("service_categories") if c.get("active", True)], key=lambda c: c.get("sortOrder", 0)),
        "services": [s for s in await store.list("services") if s.get("active", True)],
        "packages": [p for p in await store.list("packages") if p.get("active", True)],
        "memberships": [m for m in await store.list("memberships") if m.get("active", True)],
        "staff": staff,
        "offers": _active_coupons(await store.list("coupons"), today),
        "announcements": announcements[:30],
        "payments": {
            "enabled": online["enabled"],
            "methods": [m for m in PAY_METHODS if online["methods"].get(m)],
            "advancePct": online["advancePct"],
            "bridalAdvancePct": online["bridalAdvancePct"],
            "minPartial": online["minPartial"],
            "bank": online["bank"],
        },
        "rules": {k: cfg["appointments"][k] for k in ("slotIntervalMin", "minAdvanceBookingMin", "cancellationWindowHours")},
        "loyalty": cfg["loyalty"],
        "app": cfg["customerApp"],
        "currency": (cfg.get("billing") or {}).get("currencyCode", "PKR"),
    }


async def free_slots(
    store: Store, shop_id: str, day: date, service_ids: list[str], staff_id: str | None, exclude: str | None = None
) -> list[dict]:
    shop = await active_shop(store, shop_id)
    cfg = await settings(store)
    catalogue = {s["id"]: s for s in await store.list("services")}
    chosen = [catalogue[i] for i in service_ids if i in catalogue]
    if len(chosen) != len(service_ids) or not chosen:
        raise bad("Choose at least one service that is still offered.")
    staff = [s for s in await store.list("staff", shopId=shop_id) if s.get("active", True)]
    if staff_id and staff_id != "any":
        staff = [s for s in staff if s["id"] == staff_id]
        if not staff:
            raise bad("That artist does not work at this branch.")
    appts = await store.list("appointments", shopId=shop_id)
    by_time: dict[str, dict] = {}
    for st in staff:
        for slot in av.slots(day, st, shop, appts, chosen, cfg["appointments"], exclude=exclude):
            entry = by_time.setdefault(slot.time, {"time": slot.time, "startAt": slot.start.isoformat(), "staffIds": [], "reason": slot.reason})
            if slot.available:
                entry["staffIds"].append(st["id"])
                entry["reason"] = None
    out = sorted(by_time.values(), key=lambda x: x["time"])
    for e in out:
        e["available"] = bool(e["staffIds"])
        if e["available"]:
            e["reason"] = None
        e["reasonLabel"] = av.REASONS.get(e["reason"] or "", None)
    return out


@router.get("/availability")
async def availability(
    shopId: str,
    date: str = Query(..., description="yyyy-MM-dd in the salon's time zone"),
    serviceIds: str = Query(..., description="comma separated"),
    staffId: str | None = None,
    excludeAppointmentId: str | None = None,
    store: Store = Depends(get_store),
):
    try:
        day = datetime.strptime(date, "%Y-%m-%d").date()
    except ValueError as exc:
        raise bad("Use a date like 2026-12-20.") from exc
    if day < local_now().date() or day > local_now().date() + timedelta(days=180):
        raise bad("Pick a date within the next six months.")
    ids = [x for x in serviceIds.split(",") if x]
    return {"date": date, "slots": await free_slots(store, shopId, day, ids, staffId, excludeAppointmentId)}


_ = (parse_iso, tz)
