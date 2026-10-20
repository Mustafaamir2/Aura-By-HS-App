"""Payments from the app: create a payment, follow it, upload a transfer receipt."""
from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, UploadFile
from pydantic import BaseModel, Field

from ..auth import current_account
from ..config import get_settings
from ..core import ApiError, not_found, now_iso
from ..data import active_shop
from ..store import Store, get_store
from . import service
from .pages import save_slip

router = APIRouter(prefix="/v1/payments", tags=["payments"])


class VoucherIn(BaseModel):
    value: float = Field(ge=500, le=500000)
    recipientName: str = Field(min_length=1, max_length=120)
    recipientPhone: str = Field(default="", max_length=20)
    shopId: str


class PaymentIn(BaseModel):
    purpose: str
    refId: str | None = None
    plan: str = "advance"
    amount: float | None = None
    method: str | None = None
    voucher: VoucherIn | None = None


def links(p: dict) -> dict:
    base = get_settings().public_url
    out = {"payUrl": f"{base}/pay/{p['token']}"}
    if p.get("method"):
        out["startUrl"] = f"{base}/pay/{p['token']}/start?method={p['method']}"
    return out


async def own(store: Store, acc: dict, id: str) -> dict:
    p = await store.get("online_payments", id)
    if not p or p.get("accountId") != acc["id"]:
        raise not_found("That payment")
    return p


@router.post("")
async def create(body: PaymentIn, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    voucher = body.voucher.model_dump() if body.voucher else None
    shop_id = None
    if voucher:
        shop_id = (await active_shop(store, voucher["shopId"]))["id"]
    p = await service.create(
        store, purpose=body.purpose, ref_id=body.refId, plan=body.plan, amount=body.amount, method=body.method,
        created_by="app", channel="app", account=acc, shop_id=shop_id, voucher=voucher,
    )
    return {"payment": service.public_view(p), **links(p)}


@router.get("")
async def mine(acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    rows = sorted(await store.list("online_payments", accountId=acc["id"]), key=lambda p: p["createdAt"], reverse=True)
    return {"payments": [service.public_view(p) for p in rows]}


@router.get("/{id}")
async def one(id: str, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    p = await own(store, acc, id)
    return {"payment": service.public_view(p), **links(p)}


@router.post("/{id}/slip")
async def slip(id: str, file: UploadFile = File(...), note: str = Form(""), acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    p = await own(store, acc, id)
    if not service.can_pay(p):
        raise ApiError(409, "This payment is already closed.")
    p = {**p, "method": "bank-transfer"}
    p = await save_slip(store, p, file, note)
    return {"payment": service.public_view(p)}


@router.post("/{id}/cancel")
async def cancel(id: str, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    p = await own(store, acc, id)
    if p["status"] in ("pending", "failed"):
        p = {**p, "status": "cancelled", "updatedAt": now_iso()}
        await store.put("online_payments", p)
    return {"payment": service.public_view(p)}
