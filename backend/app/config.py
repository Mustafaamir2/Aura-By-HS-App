from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


@dataclass(frozen=True)
class Settings:
    supabase_url: str = field(default_factory=lambda: _env("SUPABASE_URL").rstrip("/"))
    # The service_role key: full database access. Server only — never in the app or website.
    service_key: str = field(default_factory=lambda: _env("SUPABASE_SERVICE_KEY"))
    # Public URL of this API, used for payment return addresses and pay links.
    public_url: str = field(default_factory=lambda: _env("PUBLIC_URL", "http://localhost:8000").rstrip("/"))
    # Where the app is sent back after a payment (deep link). The web page also offers a button.
    app_return_url: str = field(default_factory=lambda: _env("APP_RETURN_URL", "aurabyhs://payment"))
    cors_origins: tuple[str, ...] = field(
        default_factory=lambda: tuple(o.strip() for o in _env("CORS_ORIGINS", "*").split(",") if o.strip())
    )
    timezone: str = field(default_factory=lambda: _env("TIMEZONE", "Asia/Karachi"))

    # "live" | "sandbox" | "simulator". With no merchant keys every gateway runs as a
    # simulator so the whole flow can be tried end to end without a merchant account.
    payment_mode: str = field(default_factory=lambda: _env("PAYMENT_MODE", "sandbox").lower())

    jazzcash_merchant_id: str = field(default_factory=lambda: _env("JAZZCASH_MERCHANT_ID"))
    jazzcash_password: str = field(default_factory=lambda: _env("JAZZCASH_PASSWORD"))
    jazzcash_salt: str = field(default_factory=lambda: _env("JAZZCASH_INTEGRITY_SALT"))

    easypaisa_store_id: str = field(default_factory=lambda: _env("EASYPAISA_STORE_ID"))
    easypaisa_hash_key: str = field(default_factory=lambda: _env("EASYPAISA_HASH_KEY"))
    # Optional: credentials for the transaction-inquiry API, used to double-check a result.
    easypaisa_username: str = field(default_factory=lambda: _env("EASYPAISA_USERNAME"))
    easypaisa_password: str = field(default_factory=lambda: _env("EASYPAISA_PASSWORD"))

    @property
    def jazzcash_ready(self) -> bool:
        return bool(self.jazzcash_merchant_id and self.jazzcash_password and self.jazzcash_salt) and self.payment_mode != "simulator"

    @property
    def easypaisa_ready(self) -> bool:
        return bool(self.easypaisa_store_id and self.easypaisa_hash_key) and self.payment_mode != "simulator"

    @property
    def live(self) -> bool:
        return self.payment_mode == "live"


@lru_cache
def get_settings() -> Settings:
    return Settings()
