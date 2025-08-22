"""
Silver layer refresh helpers.

Provides functions to trigger in-database transformations that build
structured Silver tables from Bronze raw JSON.
"""

from __future__ import annotations

import json
import os
from typing import Any

import psycopg2


def _get_dsn() -> str | None:
    return os.getenv("SUPABASE_DB_URL") or os.getenv("PG_DSN")


def refresh_matches() -> dict[str, Any]:
    """
    Call the Postgres function silver.refresh_matches() and return its JSON result.

    Returns a dict with inserted/updated counts, or a message if skipped.
    """
    dsn = _get_dsn()
    if not dsn:
        return {"skipped": True, "reason": "no database DSN configured"}

    with psycopg2.connect(dsn) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("SELECT silver.refresh_matches();")
            row = cur.fetchone()
            if not row:
                return {"result": None}
            payload = row[0]
            # Payload may be a stringified JSON depending on driver settings
            if isinstance(payload, str):
                try:
                    return json.loads(payload)
                except Exception:
                    return {"result": payload}
            if isinstance(payload, dict):
                return payload
            return {"result": payload}


def refresh_ladder() -> dict[str, Any]:
    """
    Call the Postgres function silver.refresh_ladder() and return its JSON result.

    Returns a dict with inserted/updated counts, or a message if skipped.
    """
    dsn = _get_dsn()
    if not dsn:
        return {"skipped": True, "reason": "no database DSN configured"}

    with psycopg2.connect(dsn) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("SELECT silver.refresh_ladder();")
            row = cur.fetchone()
            if not row:
                return {"result": None}
            payload = row[0]
            if isinstance(payload, str):
                try:
                    return json.loads(payload)
                except Exception:
                    return {"result": payload}
            if isinstance(payload, dict):
                return payload
            return {"result": payload}
