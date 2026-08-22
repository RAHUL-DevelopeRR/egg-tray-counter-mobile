from __future__ import annotations

import asyncio
from dataclasses import dataclass

from app.schemas.scan import ScanResponse


@dataclass(frozen=True)
class StoredScan:
    fingerprint: str
    response: ScanResponse


class InMemoryScanRepository:
    """Development idempotency store; replaceable with Supabase/Postgres."""

    def __init__(self) -> None:
        self._records: dict[str, StoredScan] = {}
        self._scan_locks: dict[str, asyncio.Lock] = {}
        self._lock = asyncio.Lock()

    async def lock_for(self, scan_id: str) -> asyncio.Lock:
        """Serialize idempotency checks and work for one scan identifier."""
        async with self._lock:
            return self._scan_locks.setdefault(scan_id, asyncio.Lock())

    async def get(self, scan_id: str) -> StoredScan | None:
        async with self._lock:
            return self._records.get(scan_id)

    async def save(self, scan_id: str, fingerprint: str, response: ScanResponse) -> None:
        async with self._lock:
            self._records[scan_id] = StoredScan(fingerprint=fingerprint, response=response)
