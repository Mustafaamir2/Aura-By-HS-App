"""Hosted payment pages — what a customer sees after tapping "Pay" in the app,
or opening a payment link the salon sent on WhatsApp.

GET  /pay/{token}                     choose a method (or ?method=… to go straight on)
GET  /pay/{token}/start?method=…      hands over to JazzCash / Easypaisa (or the test simulator)
GET  /pay/{token}/bank                bank details and receipt upload
POST /pay/{token}/bank                receipt uploaded → waits for the salon to check it
POST /pay/{token}/jazzcash/return     JazzCash's signed result
*    /pay/{token}/easypaisa/return    Easypaisa step 2 (auth_token) → Confirm
*    /pay/{token}/easypaisa/done      Easypaisa's final status
GET  /pay/{token}/simulate            test checkout used when no merchant keys are set
GET  /pay/{token}/result              outcome, with a button back to the app
"""
from __future__ import annotations

import html
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse

from ..config import get_settings
from ..core import money
from ..data import settings
from ..store import Store, get_store
from . import easypaisa, jazzcash
from .service import METHOD_LABEL, by_token, can_pay, record_attempt, settle

router = APIRouter(include_in_schema=False)

MAX_SLIP = 6 * 1024 * 1024
SLIP_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "application/pdf": "pdf"}


def esc(x: object) -> str:
    return html.escape(str(x if x is not None else ""))


def page(title: str, body: str, status: int = 200) -> HTMLResponse:
    return HTMLResponse(
        f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(title)} · Aura by HS</title>
<style>
:root{{--m:#7A181C;--g:#C9A45C;--bg:#FBF7F2;--b:#EAE0D6;--t:#1F1A17;--mu:#7B6D66}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--t);font:15px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}}
main{{max-width:440px;margin:0 auto;padding:20px 16px 40px}}
.brand{{display:flex;align-items:center;gap:10px;margin-bottom:18px}}.dot{{width:38px;height:38px;border-radius:50%;background:linear-gradient(135deg,#E6C98A,#C9A45C);display:grid;place-items:center;color:var(--m);font-weight:800}}
h1{{font:600 22px Georgia,serif;margin:0 0 4px}}.mu{{color:var(--mu);font-size:13px}}
.amt{{background:linear-gradient(135deg,#7A181C,#9B2C2C);color:#fff;border-radius:22px;padding:18px;margin:14px 0}}
.amt b{{display:block;font:600 30px Georgia,serif}}.card{{background:#fff;border:1px solid var(--b);border-radius:18px;padding:14px;margin:10px 0}}
.btn{{display:flex;align-items:center;gap:12px;width:100%;padding:14px;border-radius:16px;border:1px solid var(--b);background:#fff;font:600 15px inherit;color:var(--t);text-decoration:none;margin:8px 0;cursor:pointer}}
.ic{{width:38px;height:38px;border-radius:11px;display:grid;place-items:center;color:#fff;font-weight:800;font-size:13px}}
.primary{{background:var(--m);color:#fff;justify-content:center;border:0}}.row{{display:flex;justify-content:space-between;gap:10px;padding:4px 0}}
.ok{{color:#2E8B57}}.warn{{color:#B7791F}}.bad{{color:#C62E3A}}input,textarea{{width:100%;padding:12px;border:1px solid var(--b);border-radius:12px;font:inherit}}
.badge{{display:inline-block;padding:2px 8px;border-radius:99px;background:#F6EBD3;color:var(--m);font-size:12px;font-weight:700}}
</style></head><body><main><div class="brand"><div class="dot">A</div><div><b>Aura by HS</b><div class="mu">Secure payment</div></div></div>{body}</main></body></html>""",
        status_code=status,
    )


ICON = {
    "jazzcash": ("#C8102E", "JC"),
    "easypaisa": ("#00A651", "EP"),
    "card": ("#1A1F71", "VISA"),
    "bank-transfer": ("#7A181C", "BANK"),
}


def summary(p: dict) -> str:
    return f"""<div class="amt"><span class="mu" style="color:#E6C98A;letter-spacing:.2em;font-size:11px">AMOUNT TO PAY</span>
<b>{esc(money(p['amount']))}</b><span style="opacity:.85">{esc(p.get('refLabel'))}</span></div>
<div class="mu">For {esc(p.get('customerName') or 'customer')} · {esc(p['paymentNo'])}</div>"""


def back_to_app(p: dict) -> str:
    s = get_settings()
    base = p.get("returnUrl") or s.app_return_url
    sep = "&" if "?" in base else "?"
    return f"{base}{sep}{urlencode({'payment': p['paymentNo'], 'status': p['status']})}"


@router.get("/pay/{tok}", response_class=HTMLResponse)
async def choose(tok: str, method: str | None = None, store: Store = Depends(get_store)):
    p = await by_token(store, tok)
    if not can_pay(p):
        return RedirectResponse(f"/pay/{tok}/result", status_code=303)
    if method:
        return RedirectResponse(f"/pay/{tok}/start?{urlencode({'method': method})}", status_code=303)
    cfg = (await settings(store))["onlinePayments"]
    buttons = "".join(
        f'<a class="btn" href="/pay/{esc(tok)}/start?method={m}"><span class="ic" style="background:{ICON[m][0]}">{ICON[m][1]}</span>'
        f'{esc(METHOD_LABEL[m])}<span class="mu" style="margin-left:auto">›</span></a>'
        for m in ("jazzcash", "easypaisa", "card", "bank-transfer")
        if cfg["methods"].get(m)
    )
    return page("Pay", f"<h1>Choose how to pay</h1>{summary(p)}{buttons}<p class='mu'>🔒 You pay on JazzCash’s or Easypaisa’s own secure page. Aura never sees your PIN or card number.</p>")


def autopost(url: str, fields: dict[str, str], note: str) -> HTMLResponse:
    inputs = "".join(f'<input type="hidden" name="{esc(k)}" value="{esc(v)}">' for k, v in fields.items())
    return page(
        "Redirecting",
        f"""<h1>{esc(note)}</h1><p class="mu">Taking you to the secure payment page…</p>
<form id="f" method="post" action="{esc(url)}">{inputs}<button class="btn primary" type="submit">Continue</button></form>
<script>document.getElementById('f').submit()</script>""",
    )


@router.get("/pay/{tok}/start", response_class=HTMLResponse)
async def start(tok: str, method: str, store: Store = Depends(get_store)):
    p = await by_token(store, tok)
    if not can_pay(p):
        return RedirectResponse(f"/pay/{tok}/result", status_code=303)
    cfg = (await settings(store))["onlinePayments"]
    if method not in METHOD_LABEL or not cfg["methods"].get(method):
        return page("Not available", f"<h1>{esc(METHOD_LABEL.get(method, method))} is not available</h1><a class='btn' href='/pay/{esc(tok)}'>Choose another way</a>", 400)
    if method == "bank-transfer":
        p = await record_attempt(store, p, method=method, gateway="manual", status="pending")
        return RedirectResponse(f"/pay/{tok}/bank", status_code=303)

    s = get_settings()
    base = s.public_url
    card = method == "card"
    # Cards go through JazzCash's card checkout unless only Easypaisa is set up.
    gateway = "jazzcash" if method == "jazzcash" or (card and s.jazzcash_ready) else "easypaisa" if method == "easypaisa" or card else None
    ready = s.jazzcash_ready if gateway == "jazzcash" else s.easypaisa_ready
    if not ready:
        if s.live:
            return page("Unavailable", "<h1>This payment method is being set up</h1><p class='mu'>Please choose another way or pay at the salon.</p>", 503)
        p = await record_attempt(store, p, method=method, gateway="simulator", status="processing")
        return RedirectResponse(f"/pay/{tok}/simulate", status_code=303)

    if gateway == "jazzcash":
        ref = ("T" + p["paymentNo"].replace("-", "") + str(len(p.get("attempts") or [])))[:20]
        p = await record_attempt(store, p, method=method, gateway="jazzcash", gatewayRef=ref, status="processing")
        url, fields = jazzcash.checkout_form(
            txn_ref=ref, amount=p["amount"], description=p.get("refLabel") or "Aura by HS", bill_ref=p["paymentNo"].replace("-", ""),
            return_url=f"{base}/pay/{tok}/jazzcash/return", card=card,
        )
        return autopost(url, fields, "JazzCash")

    ref = p["paymentNo"].replace("-", "") + str(len(p.get("attempts") or []))
    p = await record_attempt(store, p, method=method, gateway="easypaisa", gatewayRef=ref, status="processing")
    url, fields = easypaisa.checkout_form(
        order_ref=ref, amount=p["amount"], postback_url=f"{base}/pay/{tok}/easypaisa/return",
        email="", mobile=(p.get("customerPhone") or "")[-11:], card=card,
    )
    return autopost(url, fields, "Easypaisa")


@router.post("/pay/{tok}/jazzcash/return")
async def jazzcash_return(tok: str, request: Request, store: Store = Depends(get_store)):
    p = await by_token(store, tok)
    fields = {k: str(v) for k, v in (await request.form()).items()}
    if not jazzcash.verify(fields):
        await record_attempt(store, p, status="failed", gatewayMessage="Signature check failed", gateway="jazzcash")
        return RedirectResponse(f"/pay/{tok}/result?e=signature", status_code=303)
    if fields.get("pp_TxnRefNo") != p.get("gatewayRef") or int(fields.get("pp_Amount") or 0) != int(round(p["amount"] * 100)):
        await record_attempt(store, p, status="failed", gatewayMessage="Reference or amount mismatch", gateway="jazzcash")
        return RedirectResponse(f"/pay/{tok}/result?e=mismatch", status_code=303)
    await settle(store, p, status=jazzcash.outcome(fields), gateway="jazzcash", gateway_ref=fields.get("pp_RetreivalReferenceNo") or fields.get("pp_TxnRefNo"), message=f"{fields.get('pp_ResponseCode')} {fields.get('pp_ResponseMessage', '')}".strip())
    return RedirectResponse(f"/pay/{tok}/result", status_code=303)


@router.api_route("/pay/{tok}/easypaisa/return", methods=["GET", "POST"])
async def easypaisa_return(tok: str, request: Request, store: Store = Depends(get_store)):
    await by_token(store, tok)
    data = dict(request.query_params) | ({k: str(v) for k, v in (await request.form()).items()} if request.method == "POST" else {})
    auth = data.get("auth_token")
    if not auth:
        return RedirectResponse(f"/pay/{tok}/result?e=cancelled", status_code=303)
    url, fields = easypaisa.confirm_form(auth, f"{get_settings().public_url}/pay/{tok}/easypaisa/done")
    return autopost(url, fields, "Confirming with Easypaisa")


@router.api_route("/pay/{tok}/easypaisa/done", methods=["GET", "POST"])
async def easypaisa_done(tok: str, request: Request, store: Store = Depends(get_store)):
    p = await by_token(store, tok)
    data = dict(request.query_params) | ({k: str(v) for k, v in (await request.form()).items()} if request.method == "POST" else {})
    status = data.get("status", "")
    order = data.get("orderRefNumber") or p.get("gatewayRef")
    outcome = "paid" if status == "0000" else "failed"
    if outcome == "paid":
        # The redirect itself is not signed; ask Easypaisa when inquiry is configured.
        checked = await easypaisa.inquire(order or "")
        if checked is not None and checked != "PAID":
            outcome = "processing" if checked in ("PENDING", "INITIATED") else "failed"
    await settle(store, p, status=outcome, gateway="easypaisa", gateway_ref=order, message=f"{status} {data.get('desc', '')}".strip())
    return RedirectResponse(f"/pay/{tok}/result", status_code=303)


@router.get("/pay/{tok}/simulate", response_class=HTMLResponse)
async def simulate(tok: str, store: Store = Depends(get_store)):
    if get_settings().live:
        return page("Unavailable", "<h1>Not available</h1>", 404)
    p = await by_token(store, tok)
    if not can_pay(p):
        return RedirectResponse(f"/pay/{tok}/result", status_code=303)
    m = p.get("method") or "jazzcash"
    color, label = ICON.get(m, ICON["jazzcash"])
    return page(
        "Test checkout",
        f"""<span class="badge">TEST MODE — no real money</span>
<div class="amt" style="background:{color}"><span style="letter-spacing:.2em;font-size:11px;opacity:.8">{esc(METHOD_LABEL.get(m, m).upper())} CHECKOUT</span>
<b>{esc(money(p['amount']))}</b><span style="opacity:.85">to Aura by HS · {esc(p.get('refLabel'))}</span></div>
<p class="mu">The salon has not connected its {esc(METHOD_LABEL.get(m, m))} merchant account yet, so this page stands in for the real one. Approving records a paid test payment.</p>
<form method="post" action="/pay/{esc(tok)}/simulate"><input type="hidden" name="decision" value="approve">
<button class="btn primary" type="submit">Approve {esc(money(p['amount']))}</button></form>
<form method="post" action="/pay/{esc(tok)}/simulate"><input type="hidden" name="decision" value="decline">
<button class="btn" type="submit" style="justify-content:center">Decline</button></form>""",
    )


@router.post("/pay/{tok}/simulate")
async def simulate_post(tok: str, decision: str = Form(...), store: Store = Depends(get_store)):
    if get_settings().live:
        return page("Unavailable", "<h1>Not available</h1>", 404)
    p = await by_token(store, tok)
    if can_pay(p):
        await settle(store, p, status="paid" if decision == "approve" else "failed", gateway="simulator", gateway_ref=f"SIM{p['paymentNo'][-5:]}", message="Test payment approved" if decision == "approve" else "Declined in test checkout")
    return RedirectResponse(f"/pay/{tok}/result", status_code=303)


@router.get("/pay/{tok}/bank", response_class=HTMLResponse)
async def bank(tok: str, store: Store = Depends(get_store)):
    p = await by_token(store, tok)
    if not can_pay(p):
        return RedirectResponse(f"/pay/{tok}/result", status_code=303)
    b = (await settings(store))["onlinePayments"]["bank"]
    rows = "".join(
        f"<div class='row'><span class='mu'>{esc(k)}</span><b>{esc(v)}</b></div>"
        for k, v in (("Bank", b["bankName"]), ("Account title", b["accountTitle"]), ("Account no.", b["accountNumber"]), ("IBAN", b["iban"]), ("Raast ID", b["raastId"]), ("Amount", money(p["amount"])), ("Reference", p["paymentNo"]))
        if v
    )
    return page(
        "Bank transfer",
        f"""<h1>Bank transfer</h1>{summary(p)}<div class="card">{rows or '<span class="mu">Ask the salon for its bank details.</span>'}</div>
<p class="mu">Send the exact amount with reference <b>{esc(p['paymentNo'])}</b>, then upload the receipt. The salon confirms it, usually within a few hours.</p>
<form method="post" enctype="multipart/form-data" action="/pay/{esc(tok)}/bank">
<input type="file" name="slip" accept="image/*,application/pdf" required><br><br>
<textarea name="note" rows="2" placeholder="Sender name or transaction ID (optional)"></textarea>
<button class="btn primary" type="submit">Upload receipt</button></form>
<a class="btn" style="justify-content:center" href="/pay/{esc(tok)}">Pay another way</a>""",
    )


async def save_slip(store: Store, p: dict, slip: UploadFile, note: str) -> dict:
    from ..core import bad

    content = await slip.read()
    kind = SLIP_TYPES.get(slip.content_type or "")
    if not kind:
        raise bad("Upload a photo (JPG, PNG) or PDF of the receipt.")
    if len(content) > MAX_SLIP:
        raise bad("That file is larger than 6 MB.")
    path = f"{p['shopId']}/{p['id']}-{len(p.get('attempts') or [])}.{kind}"
    await store.upload("payment-slips", path, content, slip.content_type or "application/octet-stream")
    return await record_attempt(store, p, method="bank-transfer", gateway="manual", status="verifying", slipPath=path, payerNote=note.strip()[:300])


@router.post("/pay/{tok}/bank")
async def bank_post(tok: str, slip: UploadFile = File(...), note: str = Form(""), store: Store = Depends(get_store)):
    p = await by_token(store, tok)
    if can_pay(p):
        await save_slip(store, p, slip, note)
    return RedirectResponse(f"/pay/{tok}/result", status_code=303)


@router.get("/pay/{tok}/result", response_class=HTMLResponse)
async def result(tok: str, store: Store = Depends(get_store)):
    p = await by_token(store, tok)
    st = p["status"]
    head = {
        "paid": ("✓ Payment successful", "ok", f"{money(p['amount'])} received. Thank you!"),
        "verifying": ("Receipt received", "warn", "The salon will confirm your transfer shortly. You’ll see it in the app."),
        "processing": ("Payment processing", "warn", "Waiting for confirmation from the payment provider."),
        "failed": ("Payment not completed", "bad", p.get("gatewayMessage") or "No money was taken. You can try again."),
        "rejected": ("Payment not accepted", "bad", p.get("rejectReason") or "Please contact the salon."),
        "expired": ("This link has expired", "bad", "Ask the salon for a new payment link."),
        "cancelled": ("This payment was cancelled", "bad", ""),
        "pending": ("Payment not completed", "warn", "You can choose a payment method again."),
    }[st]
    retry = f"<a class='btn' style='justify-content:center' href='/pay/{esc(tok)}'>Try again</a>" if can_pay(p) else ""
    return page(
        head[0],
        f"""<h1 class="{head[1]}">{esc(head[0])}</h1><p>{esc(head[2])}</p>{summary(p)}
<a class="btn primary" href="{esc(back_to_app(p))}">{'Back to the website' if p.get('returnUrl') else 'Back to the Aura app'}</a>{retry}""",
    )
