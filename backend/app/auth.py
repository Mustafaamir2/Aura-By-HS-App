"""Who is calling.

The app signs customers in with Supabase Auth (Google, email + password with
verification, password reset). It sends the session's access token as
`Authorization: Bearer …`; we ask Supabase who that token belongs to, so the
same check works whatever signing keys the project uses.
"""
from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass
from typing import Any

import httpx
from fastapi import Depends, Header

from .config import get_settings
from .core import ApiError, digits, now_iso, stamped
from .store import Store, get_store


@dataclass
class AuthUser:
    id: str
    email: str
    name: str
    phone: str
    email_verified: bool
    provider: str


_cache: dict[str, tuple[float, AuthUser]] = {}
_TTL = 120.0


async def _lookup(token: str) -> AuthUser:
    key = hashlib.sha256(token.encode()).hexdigest()
    hit = _cache.get(key)
    if hit and hit[0] > time.time():
        return hit[1]
    s = get_settings()
    if not s.supabase_url:
        raise ApiError(503, "Sign-in is not configured on the server.")
    async with httpx.AsyncClient(timeout=10) as http:
        r = await http.get(
            f"{s.supabase_url}/auth/v1/user",
            headers={"apikey": s.service_key, "Authorization": f"Bearer {token}"},
        )
    if r.status_code != 200:
        raise ApiError(401, "Your session has ended. Please sign in again.")
    u: dict[str, Any] = r.json()
    meta = u.get("user_metadata") or {}
    user = AuthUser(
        id=str(u["id"]),
        email=(u.get("email") or "").lower(),
        name=meta.get("full_name") or meta.get("name") or (u.get("email") or "").split("@")[0],
        phone=u.get("phone") or meta.get("phone") or "",
        email_verified=bool(u.get("email_confirmed_at") or meta.get("email_verified")),
        provider=(u.get("app_metadata") or {}).get("provider", "email"),
    )
    _cache[key] = (time.time() + _TTL, user)
    return user


async def optional_user(authorization: str | None = Header(default=None)) -> AuthUser | None:
    if not authorization or not authorization.lower().startswith("bearer "):
        return None
    return await _lookup(authorization.split(" ", 1)[1].strip())


async def current_user(user: AuthUser | None = Depends(optional_user)) -> AuthUser:
    if user is None:
        raise ApiError(401, "Please sign in to continue.")
    return user


async def staff_profile(store: Store, user: AuthUser) -> dict | None:
    """A POS login (owner or branch) has a row in `profiles`; customers do not."""
    rows = await store.list("profiles", email=user.email)
    return rows[0] if rows and rows[0].get("active") else None


async def account_for(user: AuthUser, store: Store) -> dict:
    """The customer's app account, created on first use."""
    acc = await store.get("customer_accounts", user.id)
    if acc:
        return acc
    acc = stamped(
        {
            "id": user.id,
            # Accounts belong to head office; branches see the customer records instead.
            "shopId": None,
            "email": user.email,
            "name": user.name,
            "phone": digits(user.phone),
            "birthday": None,
            "gender": "female",
            "skinType": "",
            "allergies": "",
            "notes": "",
            "marketing": True,
            "provider": user.provider,
            # One customer record per branch the person has visited: {shopId: customerId}.
            "customerIds": {},
            "lastSeenAt": now_iso(),
            "deleted": False,
        }
    )
    await store.put("customer_accounts", acc)
    return acc


async def current_account(user: AuthUser = Depends(current_user), store: Store = Depends(get_store)) -> dict:
    acc = await account_for(user, store)
    if acc.get("deleted"):
        raise ApiError(403, "This account was deleted. Contact the salon to restore it.")
    return acc
