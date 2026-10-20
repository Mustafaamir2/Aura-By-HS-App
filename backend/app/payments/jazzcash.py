"""JazzCash hosted checkout ("Page Redirection", API v1.1).

The customer is sent to JazzCash's own page with a signed form; JazzCash posts
the result back to our return URL, signed the same way. Card numbers and wallet
PINs never pass through this server.

Docs: JazzCash Merchant Integration Guide → Page Redirection v1.1.
"""
from __future__ import annotations

import hashlib
import hmac
from datetime import datetime, timedelta

from ..config import get_settings
from ..core import tz

SANDBOX = "https://sandbox.jazzcash.com.pk/CustomerPortal/transactionmanagement/merchantform/"
LIVE = "https://payments.jazzcash.com.pk/CustomerPortal/transactionmanagement/merchantform/"

# "000" paid; "121" approved; "124" order placed, awaiting cash at a JazzCash shop.
SUCCESS = {"000", "121"}
PENDING = {"124", "157"}


def secure_hash(fields: dict[str, str], salt: str) -> str:
    """HMAC-SHA256 over the salt and every non-empty pp_ value, sorted by field name."""
    values = [str(fields[k]) for k in sorted(fields) if k.lower().startswith("pp") and k != "pp_SecureHash" and str(fields[k]) != ""]
    message = "&".join([salt, *values])
    return hmac.new(salt.encode(), message.encode(), hashlib.sha256).hexdigest().upper()


def checkout_form(*, txn_ref: str, amount: float, description: str, bill_ref: str, return_url: str, card: bool) -> tuple[str, dict[str, str]]:
    s = get_settings()
    now = datetime.now(tz())
    fields = {
        "pp_Version": "1.1",
        # MWALLET = JazzCash account; MPAY = debit / credit card.
        "pp_TxnType": "MPAY" if card else "MWALLET",
        "pp_Language": "EN",
        "pp_MerchantID": s.jazzcash_merchant_id,
        "pp_SubMerchantID": "",
        "pp_Password": s.jazzcash_password,
        "pp_BankID": "",
        "pp_ProductID": "",
        "pp_TxnRefNo": txn_ref,
        "pp_Amount": str(int(round(amount * 100))),  # in paisa
        "pp_TxnCurrency": "PKR",
        "pp_TxnDateTime": now.strftime("%Y%m%d%H%M%S"),
        "pp_BillReference": bill_ref[:20],
        "pp_Description": description[:100],
        "pp_TxnExpiryDateTime": (now + timedelta(hours=24)).strftime("%Y%m%d%H%M%S"),
        "pp_ReturnURL": return_url,
        "ppmpf_1": "",
        "ppmpf_2": "",
        "ppmpf_3": "",
        "ppmpf_4": "",
        "ppmpf_5": "",
    }
    fields["pp_SecureHash"] = secure_hash(fields, s.jazzcash_salt)
    return (LIVE if s.live else SANDBOX), fields


def verify(fields: dict[str, str]) -> bool:
    s = get_settings()
    got = (fields.get("pp_SecureHash") or "").upper()
    return bool(got) and hmac.compare_digest(got, secure_hash(fields, s.jazzcash_salt))


def outcome(fields: dict[str, str]) -> str:
    code = fields.get("pp_ResponseCode", "")
    if code in SUCCESS:
        return "paid"
    if code in PENDING:
        return "processing"
    return "failed"
