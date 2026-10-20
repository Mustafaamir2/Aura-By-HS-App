"""Easypaisa hosted checkout ("Easypay", plug-in integration).

1. We post a form, including `merchantHashedReq` (the request encrypted with the
   store's hash key), to Easypaisa's Index page; the customer pays there with
   their Easypaisa account or card.
2. Easypaisa returns an `auth_token` to our first postback URL; we pass it on to
   the Confirm page with a second postback URL.
3. Easypaisa posts the final `status` there. When inquiry credentials are set we
   double-check the order with Easypaisa's inquiry API before marking it paid.
"""
from __future__ import annotations

import base64
from datetime import datetime, timedelta

import httpx
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

from ..config import get_settings
from ..core import tz

STAGING = "https://easypaystg.easypaisa.com.pk"
LIVE = "https://easypay.easypaisa.com.pk"


def base_url() -> str:
    return LIVE if get_settings().live else STAGING


def hashed_request(fields: dict[str, str], hash_key: str) -> str:
    """AES/ECB/PKCS5 over the sorted query string, base64 — Easypaisa's merchantHashedReq."""
    plain = "&".join(f"{k}={fields[k]}" for k in sorted(fields) if fields[k] != "")
    padder = padding.PKCS7(128).padder()
    data = padder.update(plain.encode()) + padder.finalize()
    # The hash key from the Easypaisa merchant portal is 16 characters (AES-128).
    enc = Cipher(algorithms.AES(hash_key.encode()), modes.ECB()).encryptor()
    return base64.b64encode(enc.update(data) + enc.finalize()).decode()


def checkout_form(*, order_ref: str, amount: float, postback_url: str, email: str, mobile: str, card: bool) -> tuple[str, dict[str, str]]:
    s = get_settings()
    fields = {
        "amount": f"{amount:.1f}",
        "autoRedirect": "1",
        "emailAddr": email,
        "expiryDate": (datetime.now(tz()) + timedelta(hours=24)).strftime("%Y%m%d %H%M%S"),
        "mobileNum": mobile,
        "orderRefNum": order_ref,
        "paymentMethod": "CC_PAYMENT_METHOD" if card else "MA_PAYMENT_METHOD",
        "postBackURL": postback_url,
        "storeId": s.easypaisa_store_id,
    }
    fields["merchantHashedReq"] = hashed_request({k: v for k, v in fields.items()}, s.easypaisa_hash_key)
    return f"{base_url()}/easypay/Index.jsf", fields


def confirm_form(auth_token: str, postback_url: str) -> tuple[str, dict[str, str]]:
    return f"{base_url()}/easypay/Confirm.jsf", {"auth_token": auth_token, "postBackURL": postback_url}


async def inquire(order_ref: str) -> str | None:
    """'PAID', 'FAILED', … from Easypaisa itself, or None when inquiry is not set up."""
    s = get_settings()
    if not (s.easypaisa_username and s.easypaisa_password):
        return None
    cred = base64.b64encode(f"{s.easypaisa_username}:{s.easypaisa_password}".encode()).decode()
    async with httpx.AsyncClient(timeout=15) as http:
        r = await http.post(
            f"{base_url()}/easypay-service/rest/v4/inquire-transaction",
            headers={"Credentials": cred, "Content-Type": "application/json"},
            json={"orderId": order_ref, "storeId": s.easypaisa_store_id, "accountNum": ""},
        )
    if r.status_code != 200:
        return None
    body = r.json()
    if body.get("responseCode") != "0000":
        return None
    return str(body.get("transactionStatus") or "").upper() or None
