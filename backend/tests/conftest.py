from __future__ import annotations

import os
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("PUBLIC_URL", "http://testserver")
os.environ.setdefault("PAYMENT_MODE", "sandbox")

from app import auth  # noqa: E402
from app.core import local_now  # noqa: E402
from app.main import app  # noqa: E402
from app.store import MemoryStore, set_store  # noqa: E402

AT = "2026-01-01T00:00:00.000Z"
HOURS = [{"weekday": d, "closed": False, "open": "10:00", "close": "21:00"} for d in range(7)]
SHIFT = [{"weekday": d, "working": True, "start": "10:00", "end": "21:00", "breakStart": "15:00", "breakEnd": "15:30"} for d in range(7)]


def base(id: str, **kw):
    return {"id": id, "createdAt": AT, "updatedAt": AT, **kw}


def seed() -> dict[str, list[dict]]:
    return {
        "app_settings": [{"id": "global", "updatedAt": AT, "business": {"name": "Aura by HS"},
                          "appointments": {"defaultDurationMin": 60, "slotIntervalMin": 30, "minAdvanceBookingMin": 60, "cancellationWindowHours": 4, "bufferMin": 0},
                          "notifications": {}, "loyalty": {"enabled": True, "pointsPer100": 1, "pointValue": 1, "minRedeemPoints": 100},
                          "onlinePayments": {"bank": {"bankName": "Meezan Bank", "accountTitle": "AURA BY HS", "accountNumber": "0101", "iban": "PK36MEZN", "raastId": ""}}}],
        "shops": [base("shp_gul", name="Aura Gulberg", code="GUL", addressLine="MM Alam Road", city="Lahore", phone="042", email="", logoUrl=None,
                       businessHours=HOURS, receiptFooter="", active=True, openedOn="2026-01-01")],
        "service_categories": [base("cat_hair", name="Hair", description="", icon="wind", sortOrder=1, active=True)],
        "services": [
            base("svc_cut", name="Haircut & Blow-Dry", categoryId="cat_hair", description="", durationMin=60, price=3500, discountPct=0, imageUrl=None, active=True),
            base("svc_style", name="Event Styling", categoryId="cat_hair", description="", durationMin=60, price=8000, discountPct=10, imageUrl=None, active=True),
        ],
        "packages": [base("pkg_sig", name="Bride Signature", description="", price=95000, items=[], imageUrl=None, active=True)],
        "staff": [
            base("stf_sana", shopId="shp_gul", name="Sana", role="Stylist", phone="", email="", photoUrl=None, specializations=["svc_cut", "svc_style"],
                 schedule=SHIFT, timeOff=[], commissionRate=0.1, active=True, joinedOn="2026-01-01"),
            base("stf_amna", shopId="shp_gul", name="Amna", role="Stylist", phone="", email="", photoUrl=None, specializations=["svc_cut"],
                 schedule=SHIFT, timeOff=[], commissionRate=0.1, active=True, joinedOn="2026-01-01"),
        ],
        "coupons": [base("cpn_1", code="AURA15", name="15%", mode="percent", value=15, minSpend=0, startsOn=None, endsOn=None, maxUses=0, shopId=None, active=True)],
        "profiles": [],
    }


USERS = {
    "tok-ayesha": auth.AuthUser(id="u-ayesha", email="ayesha@gmail.com", name="Ayesha Rizwan", phone="", email_verified=True, provider="google"),
    "tok-other": auth.AuthUser(id="u-other", email="other@gmail.com", name="Other", phone="", email_verified=True, provider="email"),
}


@pytest.fixture(autouse=True)
def _reset_rate_limit():
    """The public endpoints' flood brake counts hits per IP in a module-level
    dict, so without this every test shares one 10-per-hour budget and the
    later ones get a 429 that has nothing to do with what they assert."""
    from app import public

    public._hits.clear()
    yield
    public._hits.clear()


@pytest.fixture
def store():
    s = MemoryStore(seed())
    set_store(s)
    yield s
    set_store(None)


@pytest.fixture
def client(store):
    async def fake_user(authorization: str | None = None):
        from fastapi import Header  # noqa: F401

        return None

    async def optional_user(authorization: str | None = __import__("fastapi").Header(default=None)):
        if not authorization:
            return None
        tok = authorization.split(" ", 1)[1]
        if tok not in USERS:
            raise auth.ApiError(401, "Your session has ended. Please sign in again.")
        return USERS[tok]

    app.dependency_overrides[auth.optional_user] = optional_user
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def H(tok: str = "tok-ayesha") -> dict:
    return {"Authorization": f"Bearer {tok}"}


def tomorrow(hhmm: str = "11:00") -> str:
    d = (local_now() + timedelta(days=1)).date()
    h, m = hhmm.split(":")
    return local_now().replace(year=d.year, month=d.month, day=d.day, hour=int(h), minute=int(m), second=0, microsecond=0).isoformat()


def in_days(n: int, hhmm: str = "11:00") -> str:
    d = (local_now() + timedelta(days=n)).date()
    h, m = hhmm.split(":")
    return local_now().replace(year=d.year, month=d.month, day=d.day, hour=int(h), minute=int(m), second=0, microsecond=0).isoformat()
