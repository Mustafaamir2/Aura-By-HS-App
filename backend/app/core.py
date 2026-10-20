"""Small helpers shared by every module: ids, clocks, money and errors."""
from __future__ import annotations

import random
import re
import string
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from fastapi import HTTPException

from .config import get_settings

_B36 = string.digits + string.ascii_lowercase


def _base36(n: int) -> str:
    out = ""
    while n:
        n, r = divmod(n, 36)
        out = _B36[r] + out
    return out or "0"


def uid(prefix: str) -> str:
    """Same shape as the POS's ids (prefix_<time><random>), so both sides mix freely."""
    rand = "".join(random.choice(_B36) for _ in range(8))
    return f"{prefix}_{_base36(int(time.time() * 1000))}{rand}"


def token(n: int = 24) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(random.SystemRandom().choice(alphabet) for _ in range(n))


def now_iso() -> str:
    """ISO-8601 in UTC with milliseconds and a Z, exactly like JavaScript's toISOString()."""
    return to_iso(datetime.now(timezone.utc))


def to_iso(dt: datetime) -> str:
    dt = dt.astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def parse_iso(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def tz() -> ZoneInfo:
    return ZoneInfo(get_settings().timezone)


def local_now() -> datetime:
    return datetime.now(tz())


def round2(x: float) -> float:
    return round(float(x) + 1e-9, 2)


def money(x: float) -> str:
    return f"Rs {round(x):,}"


def digits(phone: str | None) -> str:
    d = re.sub(r"\D", "", phone or "")
    # 92300… and 0300… are the same Pakistani mobile.
    if d.startswith("92") and len(d) == 12:
        d = "0" + d[2:]
    return d


def stamped(row: dict) -> dict:
    at = now_iso()
    return {**row, "createdAt": at, "updatedAt": at}


class ApiError(HTTPException):
    """Raised with a sentence the app shows to the customer as-is."""

    def __init__(self, status: int, message: str):
        super().__init__(status_code=status, detail=message)


def bad(message: str) -> ApiError:
    return ApiError(400, message)


def not_found(what: str = "That record") -> ApiError:
    return ApiError(404, f"{what} could not be found.")


def conflict(message: str) -> ApiError:
    return ApiError(409, message)
