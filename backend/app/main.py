"""Entry point: `uvicorn app.main:app`."""
from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import account, bookings, catalog, messages, public
from .config import get_settings
from .payments import api as payments_api
from .payments import pages as payment_pages

app = FastAPI(title="Aura by HS API", version="1.0.0", description="Customer app, website and payment links for Aura by HS.")

app.add_middleware(
    CORSMiddleware,
    allow_origins=list(get_settings().cors_origins) or ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(StarletteHTTPException)
async def http_error(_: Request, exc: StarletteHTTPException):
    return JSONResponse({"error": exc.detail}, status_code=exc.status_code)


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, exc: RequestValidationError):
    first = exc.errors()[0] if exc.errors() else {}
    field = ".".join(str(x) for x in first.get("loc", [])[1:]) or "request"
    return JSONResponse({"error": f"Please check {field}: {first.get('msg', 'invalid value')}."}, status_code=422)


@app.get("/")
@app.get("/health")
async def health():
    s = get_settings()
    return {
        "ok": True,
        "service": "aura-api",
        "database": bool(s.supabase_url and s.service_key),
        "payments": {"mode": s.payment_mode, "jazzcash": s.jazzcash_ready, "easypaisa": s.easypaisa_ready},
    }


for r in (catalog.router, account.router, bookings.router, payments_api.router, messages.router, public.router, payment_pages.router):
    app.include_router(r)
