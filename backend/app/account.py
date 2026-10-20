"""The signed-in customer's profile."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .auth import AuthUser, current_account, current_user
from .core import bad, digits, now_iso
from .store import Store, get_store

router = APIRouter(prefix="/v1", tags=["account"])


def view(acc: dict, user: AuthUser | None = None) -> dict:
    keys = ("id", "email", "name", "phone", "birthday", "gender", "skinType", "allergies", "notes", "marketing", "provider", "createdAt")
    out = {k: acc.get(k) for k in keys}
    out["emailVerified"] = user.email_verified if user else None
    out["profileComplete"] = bool(acc.get("name") and len(digits(acc.get("phone"))) >= 10)
    return out


class ProfileIn(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=20)
    birthday: str | None = Field(default=None, max_length=10)
    gender: str | None = None
    skinType: str | None = Field(default=None, max_length=40)
    allergies: str | None = Field(default=None, max_length=500)
    notes: str | None = Field(default=None, max_length=1000)
    marketing: bool | None = None


@router.get("/me")
async def me(user: AuthUser = Depends(current_user), acc: dict = Depends(current_account)):
    return view(acc, user)


@router.put("/me")
async def update_me(body: ProfileIn, user: AuthUser = Depends(current_user), acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    patch = body.model_dump(exclude_none=True)
    if "name" in patch and len(patch["name"].strip()) < 2:
        raise bad("Enter your full name.")
    if "phone" in patch:
        p = digits(patch["phone"])
        if not (len(p) == 11 and p.startswith("03")):
            raise bad("Enter a Pakistani mobile number like 0300 1234567.")
        patch["phone"] = p
    if "gender" in patch and patch["gender"] not in ("female", "male", "other", "unspecified"):
        raise bad("Choose a valid option.")
    acc = {**acc, **patch, "updatedAt": now_iso()}
    await store.put("customer_accounts", acc)
    # Keep each branch's customer card in step with what the customer typed.
    for cid in (acc.get("customerIds") or {}).values():
        c = await store.get("customers", cid)
        if c:
            c = {**c, "name": acc["name"] or c["name"], "email": acc.get("email") or c.get("email"), "birthday": acc.get("birthday") or c.get("birthday"), "sensitivities": acc.get("allergies") or c.get("sensitivities", ""), "updatedAt": now_iso()}
            if acc.get("phone"):
                c["phone"] = acc["phone"]
            await store.put("customers", c)
    return view(acc, user)


@router.delete("/me")
async def delete_me(acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    """Closes the app account. Branch records stay (bills must be kept), but the
    personal details on the account are cleared and upcoming bookings cancelled."""
    at = now_iso()
    for cid in (acc.get("customerIds") or {}).values():
        for a in await store.list("appointments", customerId=cid):
            if a.get("status") in ("pending", "confirmed"):
                a = {**a, "status": "cancelled", "cancelReason": "Customer deleted their app account", "updatedAt": at,
                     "history": [*(a.get("history") or []), {"status": "cancelled", "at": at, "byUserId": acc["id"], "byUserName": "Customer (app)", "note": "Account deleted"}]}
                await store.put("appointments", a)
    acc = {**acc, "deleted": True, "name": "Deleted account", "phone": "", "birthday": None, "allergies": "", "notes": "", "marketing": False, "updatedAt": at}
    await store.put("customer_accounts", acc)
    return {"ok": True}
