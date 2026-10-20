"""Which times can be booked — the POS's rules (src/services/availability.ts),
ported line for line so the app never offers a slot the front desk would refuse.

All clock arithmetic is in the salon's local time zone; appointments are stored
as UTC ISO strings exactly as the POS writes them.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Any

from .core import parse_iso, tz

BLOCKING = {"pending", "confirmed", "checked-in", "in-progress", "completed"}

REASONS = {
    "past": "This time has already passed",
    "too-soon": "Too soon — needs more advance notice",
    "outside-shop-hours": "Outside the salon’s opening hours",
    "outside-shift": "Outside this stylist’s shift",
    "on-break": "The stylist is on a break",
    "booked": "Already booked",
    "day-off": "The stylist is off on this day",
    "on-leave": "The stylist is on leave",
    "not-qualified": "This stylist does not perform the selected services",
    "shop-closed": "The salon is closed on this day",
}


def clock(hhmm: str) -> int:
    h, m = hhmm.split(":")[:2]
    return int(h) * 60 + int(m)


def hhmm(minutes: int) -> str:
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def js_weekday(d: date) -> int:
    """0 = Sunday … 6 = Saturday, like JavaScript's getDay()."""
    return (d.weekday() + 1) % 7


def day_start(d: date) -> datetime:
    return datetime.combine(d, time(0, 0), tzinfo=tz())


def total_duration(services: list[dict], fallback: int = 0) -> int:
    s = sum(int(x.get("durationMin", 0)) for x in services)
    return s if s > 0 else fallback


def unit_price(service: dict) -> int:
    return round(service["price"] * (1 - (service.get("discountPct") or 0) / 100))


def qualified(staff: dict, services: list[dict]) -> bool:
    return all(s["id"] in (staff.get("specializations") or []) for s in services)


def day_block(d: date, staff: dict, shop: dict, services: list[dict]) -> str | None:
    wd = js_weekday(d)
    hours = next((h for h in shop.get("businessHours") or [] if h["weekday"] == wd), None)
    if not hours or hours.get("closed"):
        return "shop-closed"
    if d.isoformat() in (staff.get("timeOff") or []):
        return "on-leave"
    shift = next((s for s in staff.get("schedule") or [] if s["weekday"] == wd), None)
    if not shift or not shift.get("working"):
        return "day-off"
    if not qualified(staff, services):
        return "not-qualified"
    return None


def busy(d: date, staff_id: str, appointments: list[dict], exclude: str | None = None) -> list[tuple[int, int]]:
    start0 = day_start(d)
    out = []
    for a in appointments:
        if a.get("staffId") != staff_id or a.get("id") == exclude or a.get("status") not in BLOCKING:
            continue
        s = parse_iso(a["startAt"]).astimezone(tz())
        if s.date() != d:
            continue
        off = round((s - start0).total_seconds() / 60)
        out.append((off, off + int(a.get("durationMin") or 0)))
    return sorted(out)


def _overlaps(a: tuple[int, int], b: tuple[int, int]) -> bool:
    return a[0] < b[1] and a[1] > b[0]


@dataclass
class Slot:
    time: str
    start: datetime
    available: bool
    reason: str | None


def slots(
    d: date,
    staff: dict,
    shop: dict,
    appointments: list[dict],
    services: list[dict],
    rules: dict[str, Any],
    now: datetime | None = None,
    exclude: str | None = None,
) -> list[Slot]:
    now = now or datetime.now(tz())
    wd = js_weekday(d)
    duration = total_duration(services, int(rules.get("defaultDurationMin", 60)))
    step = max(5, int(rules.get("slotIntervalMin", 15)))
    blanket = day_block(d, staff, shop, services)
    hours = next((h for h in shop.get("businessHours") or [] if h["weekday"] == wd), None)
    shift = next((s for s in staff.get("schedule") or [] if s["weekday"] == wd), None)
    if not hours or hours.get("closed"):
        return []
    if blanket in ("day-off", "on-leave") or not shift or not shift.get("working"):
        return []

    shop_open, shop_close = clock(hours["open"]), clock(hours["close"])
    shift_start, shift_end = clock(shift["start"]), clock(shift["end"])
    brk = (clock(shift["breakStart"]), clock(shift["breakEnd"])) if shift.get("breakStart") and shift.get("breakEnd") else None
    taken = busy(d, staff["id"], appointments, exclude)
    buffer = max(0, int(rules.get("bufferMin", 0)))
    earliest = now + timedelta(minutes=max(0, int(rules.get("minAdvanceBookingMin", 0))))
    start0 = day_start(d)

    out: list[Slot] = []
    m = max(shop_open, shift_start)
    end = min(shop_close, shift_end)
    while m + duration <= end:
        cand = (m, m + duration)
        start = start0 + timedelta(minutes=m)
        reason = None
        if blanket == "not-qualified":
            reason = "not-qualified"
        elif start < now:
            reason = "past"
        elif start < earliest:
            reason = "too-soon"
        elif cand[0] < shop_open or cand[1] > shop_close:
            reason = "outside-shop-hours"
        elif cand[0] < shift_start or cand[1] > shift_end:
            reason = "outside-shift"
        elif brk and _overlaps(cand, brk):
            reason = "on-break"
        elif any(_overlaps(cand, (b0 - buffer, b1 + buffer)) for b0, b1 in taken):
            reason = "booked"
        out.append(Slot(hhmm(m), start, reason is None, reason))
        m += step
    return out


def validate(
    start: datetime,
    staff: dict,
    shop: dict,
    appointments: list[dict],
    services: list[dict],
    rules: dict[str, Any],
    now: datetime | None = None,
    exclude: str | None = None,
) -> str | None:
    """None when the exact start time can be booked, else the reason it cannot."""
    start = start.astimezone(tz())
    d = start.date()
    for s in slots(d, staff, shop, appointments, services, rules, now, exclude):
        if s.start == start:
            return s.reason
    # Off the grid (e.g. 10:07) — check the same rules directly.
    blanket = day_block(d, staff, shop, services)
    if blanket:
        return blanket
    now = now or datetime.now(tz())
    if start < now:
        return "past"
    duration = total_duration(services, int(rules.get("defaultDurationMin", 60)))
    m = round((start - day_start(d)).total_seconds() / 60)
    wd = js_weekday(d)
    hours = next(h for h in shop["businessHours"] if h["weekday"] == wd)
    shift = next(s for s in staff["schedule"] if s["weekday"] == wd)
    if m < clock(hours["open"]) or m + duration > clock(hours["close"]):
        return "outside-shop-hours"
    if m < clock(shift["start"]) or m + duration > clock(shift["end"]):
        return "outside-shift"
    buffer = max(0, int(rules.get("bufferMin", 0)))
    if any(_overlaps((m, m + duration), (b0 - buffer, b1 + buffer)) for b0, b1 in busy(d, staff["id"], appointments, exclude)):
        return "booked"
    return None
