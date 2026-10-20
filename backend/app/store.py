"""Data access.

Every POS table has the shape {id, data jsonb, updated_at}, where `data` is the
whole record (see the POS's supabase/schema.sql). This module reads and writes
those records through Supabase's REST API with the service key, which is the
only key that may act for a customer. `MemoryStore` has the same interface and
backs the tests.
"""
from __future__ import annotations

import copy
from typing import Any, Protocol
from urllib.parse import quote

import httpx

from .config import get_settings
from .core import ApiError, now_iso

Record = dict[str, Any]


class Store(Protocol):
    async def list(self, table: str, **eq: Any) -> list[Record]: ...
    async def get(self, table: str, id: str) -> Record | None: ...
    async def put(self, table: str, row: Record) -> Record: ...
    async def insert(self, table: str, row: Record) -> Record: ...
    async def delete(self, table: str, id: str) -> None: ...
    async def upload(self, bucket: str, path: str, content: bytes, content_type: str) -> str: ...
    async def signed_url(self, bucket: str, path: str, seconds: int = 3600) -> str | None: ...


def _friendly(text: str) -> str:
    """Postgres raises readable sentences for business rules (e.g. double booking)."""
    try:
        import json

        body = json.loads(text)
        msg = body.get("message") or body.get("msg") or text
    except Exception:  # noqa: BLE001 - any non-JSON body is passed through
        msg = text
    return str(msg)[:300]


class RestStore:
    def __init__(self, url: str, key: str):
        self.url = url
        self.key = key
        self.http = httpx.AsyncClient(
            timeout=20,
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
        )

    def _filters(self, eq: dict[str, Any]) -> dict[str, str]:
        params: dict[str, str] = {}
        for k, v in eq.items():
            col = "id" if k == "id" else f"data->>{k}"
            if v is None:
                params[col] = "is.null"
            elif isinstance(v, bool):
                params[col] = f"eq.{str(v).lower()}"
            elif isinstance(v, (list, tuple)):
                params[col] = "in.(" + ",".join(f'"{x}"' for x in v) + ")"
            else:
                params[col] = f"eq.{v}"
        return params

    async def list(self, table: str, **eq: Any) -> list[Record]:
        out: list[Record] = []
        page = 1000
        start = 0
        while True:
            r = await self.http.get(
                f"{self.url}/rest/v1/{table}",
                params={"select": "data", "order": "id", **self._filters(eq)},
                headers={"Range": f"{start}-{start + page - 1}"},
            )
            if r.status_code >= 400:
                raise ApiError(502, f"Database error on {table}: {_friendly(r.text)}")
            rows = [x["data"] for x in r.json()]
            out.extend(rows)
            if len(rows) < page:
                return out
            start += page

    async def get(self, table: str, id: str) -> Record | None:
        rows = await self.list(table, id=id)
        return rows[0] if rows else None

    async def put(self, table: str, row: Record) -> Record:
        r = await self.http.post(
            f"{self.url}/rest/v1/{table}",
            json={"id": row["id"], "data": row},
            headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
        )
        if r.status_code >= 400:
            raise ApiError(409 if r.status_code in (400, 409) else 502, _friendly(r.text))
        return row

    async def insert(self, table: str, row: Record) -> Record:
        r = await self.http.post(
            f"{self.url}/rest/v1/{table}",
            json={"id": row["id"], "data": row},
            headers={"Prefer": "return=minimal"},
        )
        if r.status_code >= 400:
            raise ApiError(409 if r.status_code in (400, 409) else 502, _friendly(r.text))
        return row

    async def delete(self, table: str, id: str) -> None:
        r = await self.http.delete(f"{self.url}/rest/v1/{table}", params={"id": f"eq.{id}"})
        if r.status_code >= 400:
            raise ApiError(502, _friendly(r.text))

    async def upload(self, bucket: str, path: str, content: bytes, content_type: str) -> str:
        r = await self.http.post(
            f"{self.url}/storage/v1/object/{bucket}/{quote(path)}",
            content=content,
            headers={"Content-Type": content_type, "x-upsert": "true"},
        )
        if r.status_code >= 400:
            raise ApiError(502, f"Could not store the file: {_friendly(r.text)}")
        return path

    async def signed_url(self, bucket: str, path: str, seconds: int = 3600) -> str | None:
        r = await self.http.post(
            f"{self.url}/storage/v1/object/sign/{bucket}/{quote(path)}", json={"expiresIn": seconds}
        )
        if r.status_code >= 400:
            return None
        signed = r.json().get("signedURL") or r.json().get("signedUrl")
        if not signed:
            return None
        return f"{self.url}/storage/v1{signed}" if signed.startswith("/") else signed


class MemoryStore:
    """In-memory twin of RestStore for tests and offline development."""

    def __init__(self, tables: dict[str, list[Record]] | None = None):
        self.tables: dict[str, dict[str, Record]] = {}
        self.files: dict[str, bytes] = {}
        for t, rows in (tables or {}).items():
            self.tables[t] = {r["id"]: copy.deepcopy(r) for r in rows}
        # Mirrors the database trigger that refuses a double booking.
        self.prevent_double_booking = True

    def _t(self, table: str) -> dict[str, Record]:
        return self.tables.setdefault(table, {})

    async def list(self, table: str, **eq: Any) -> list[Record]:
        def match(r: Record) -> bool:
            for k, v in eq.items():
                have = r.get(k)
                if isinstance(v, (list, tuple)):
                    if have not in v:
                        return False
                elif v is None:
                    if have is not None:
                        return False
                elif str(have).lower() != str(v).lower() if isinstance(v, bool) else str(have) != str(v):
                    return False
            return True

        return [copy.deepcopy(r) for _, r in sorted(self._t(table).items()) if match(r)]

    async def get(self, table: str, id: str) -> Record | None:
        r = self._t(table).get(id)
        return copy.deepcopy(r) if r else None

    def _check(self, table: str, row: Record) -> None:
        if table != "appointments" or not self.prevent_double_booking:
            return
        if row.get("status") in ("cancelled", "no-show"):
            return
        from .core import parse_iso

        s = parse_iso(row["startAt"]).timestamp()
        e = s + row["durationMin"] * 60
        for other in self._t(table).values():
            if other["id"] == row["id"] or other.get("staffId") != row.get("staffId"):
                continue
            if other.get("status") in ("cancelled", "no-show"):
                continue
            os_ = parse_iso(other["startAt"]).timestamp()
            oe = os_ + other["durationMin"] * 60
            if os_ < e and oe > s:
                raise ApiError(409, "That stylist was just booked for this time by someone else. Pick another slot.")

    async def put(self, table: str, row: Record) -> Record:
        self._check(table, row)
        self._t(table)[row["id"]] = copy.deepcopy(row)
        return row

    async def insert(self, table: str, row: Record) -> Record:
        if row["id"] in self._t(table):
            raise ApiError(409, "duplicate key")
        return await self.put(table, row)

    async def delete(self, table: str, id: str) -> None:
        self._t(table).pop(id, None)

    async def upload(self, bucket: str, path: str, content: bytes, content_type: str) -> str:
        self.files[f"{bucket}/{path}"] = content
        return path

    async def signed_url(self, bucket: str, path: str, seconds: int = 3600) -> str | None:
        return f"memory://{bucket}/{path}" if f"{bucket}/{path}" in self.files else None


_store: Store | None = None


def get_store() -> Store:
    global _store
    if _store is None:
        s = get_settings()
        if not (s.supabase_url and s.service_key):
            raise ApiError(503, "The server is not connected to the database yet (SUPABASE_URL / SUPABASE_SERVICE_KEY).")
        _store = RestStore(s.supabase_url, s.service_key)
    return _store


def set_store(store: Store | None) -> None:
    global _store
    _store = store


def touch(row: Record) -> Record:
    return {**row, "updatedAt": now_iso()}
