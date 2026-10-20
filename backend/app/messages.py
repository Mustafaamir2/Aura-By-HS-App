"""Chat between a customer and head office (the "Aura Concierge") or a branch.

A thread is one customer with one desk: key "hq" for head office or a shop id.
Staff answer from the POS's Messages screen (same table, live updates).
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, UploadFile
from pydantic import BaseModel, Field

from .auth import current_account
from .core import bad, not_found, now_iso, stamped, uid
from .store import Store, get_store

router = APIRouter(prefix="/v1", tags=["messages"])
IMAGE_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


def thread_id(account_id: str, key: str) -> str:
    return f"{account_id}:{key}"


async def desk(store: Store, key: str) -> tuple[str | None, str, str]:
    """(shopId, title, subtitle) for a thread key."""
    if key == "hq":
        return None, "Aura Concierge", "Head office · bridal, packages & feedback"
    shop = await store.get("shops", key)
    if not shop or not shop.get("active", True):
        raise not_found("That branch")
    return shop["id"], shop["name"], shop.get("addressLine") or "Front desk"


async def view(store: Store, m: dict) -> dict:
    out = {k: m.get(k) for k in ("id", "from", "authorName", "text", "at", "readByStaff", "readByCustomer")}
    out["imageUrl"] = await store.signed_url("chat-images", m["imagePath"]) if m.get("imagePath") else None
    return out


@router.get("/threads")
async def threads(acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    rows = await store.list("messages", accountId=acc["id"])
    groups: dict[str, list[dict]] = {}
    for m in rows:
        groups.setdefault(m["threadId"].split(":", 1)[1], []).append(m)
    out = []
    for key, msgs in groups.items():
        msgs.sort(key=lambda m: m["at"])
        shop_id, title, sub = await desk(store, key)
        last = msgs[-1]
        out.append({"key": key, "kind": "concierge" if key == "hq" else "branch", "shopId": shop_id, "title": title, "subtitle": sub,
                    "lastText": last.get("text") or ("📷 Photo" if last.get("imagePath") else ""), "lastAt": last["at"], "lastFromMe": last["from"] == "customer",
                    "unread": sum(1 for m in msgs if m["from"] != "customer" and not m.get("readByCustomer"))})
    seen = acc.get("announcementsReadAt") or ""
    ann = sorted([a for a in await store.list("announcements") if a.get("active", True)], key=lambda a: a.get("createdAt", ""))
    out.sort(key=lambda t: t["lastAt"], reverse=True)
    return {
        "announcements": {"unread": sum(1 for a in ann if a.get("createdAt", "") > seen), "items": [{k: a.get(k) for k in ("id", "title", "body", "imageUrl", "createdAt")} for a in reversed(ann)]},
        "threads": out,
    }


@router.post("/announcements/read")
async def read_announcements(acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    await store.put("customer_accounts", {**acc, "announcementsReadAt": now_iso(), "updatedAt": now_iso()})
    return {"ok": True}


@router.get("/threads/{key}/messages")
async def messages(key: str, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    shop_id, title, sub = await desk(store, key)
    rows = sorted(await store.list("messages", threadId=thread_id(acc["id"], key)), key=lambda m: m["at"])
    for m in rows:
        if m["from"] != "customer" and not m.get("readByCustomer"):
            m = {**m, "readByCustomer": True, "updatedAt": now_iso()}
            await store.put("messages", m)
    rows = sorted(await store.list("messages", threadId=thread_id(acc["id"], key)), key=lambda m: m["at"])
    return {"key": key, "title": title, "subtitle": sub, "shopId": shop_id, "messages": [await view(store, m) for m in rows]}


class MessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


async def _post(store: Store, acc: dict, key: str, text: str, image_path: str | None) -> dict:
    shop_id, _, _ = await desk(store, key)
    at = now_iso()
    m = stamped({
        "id": uid("msg"), "threadId": thread_id(acc["id"], key), "shopId": shop_id, "accountId": acc["id"],
        "customerName": acc.get("name") or "Customer", "customerPhone": acc.get("phone") or "", "customerEmail": acc.get("email") or "",
        "from": "customer", "authorName": acc.get("name") or "Customer", "text": text.strip(), "imagePath": image_path, "at": at,
        "readByStaff": False, "readByCustomer": True,
    })
    await store.put("messages", m)
    return await view(store, m)


@router.post("/threads/{key}/messages")
async def send(key: str, body: MessageIn, acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    return {"message": await _post(store, acc, key, body.text, None)}


@router.post("/threads/{key}/photo")
async def send_photo(key: str, file: UploadFile = File(...), text: str = Form(""), acc: dict = Depends(current_account), store: Store = Depends(get_store)):
    kind = IMAGE_TYPES.get(file.content_type or "")
    if not kind:
        raise bad("Send a JPG, PNG or WebP photo.")
    content = await file.read()
    if len(content) > 6 * 1024 * 1024:
        raise bad("That photo is larger than 6 MB.")
    path = f"{acc['id']}/{uid('img')}.{kind}"
    await store.upload("chat-images", path, content, file.content_type or "image/jpeg")
    return {"message": await _post(store, acc, key, text[:2000], path)}
