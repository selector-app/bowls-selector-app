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


def _execute_refresh_function(function_name: str) -> dict[str, Any]:
    """
    Execute a silver refresh function and return its JSON result.
    
    Args:
        function_name: Name of the silver function to execute (e.g., 'refresh_ladder')
    
    Returns:
        A dict with inserted/updated counts, or a message if skipped.
    """
    dsn = _get_dsn()
    if not dsn:
        return {"skipped": True, "reason": "no database DSN configured"}

    with psycopg2.connect(dsn) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(f"SELECT silver.{function_name}();")
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


def refresh_competition_matches() -> dict[str, Any]:
    """
    Call the Postgres function silver.refresh_competition_matches() and return its JSON result.
    """
    return _execute_refresh_function("refresh_competition_matches")


def refresh_competitions() -> dict[str, Any]:
    """
    Call the Postgres function silver.refresh_competitions() and return its JSON result.
    """
    return _execute_refresh_function("refresh_competitions")


def refresh_competition_competitors() -> dict[str, Any]:
    """
    Call the Postgres function silver.refresh_competition_competitors() and return its JSON result.
    """
    return _execute_refresh_function("refresh_competition_competitors")


def refresh_competition_results() -> dict[str, Any]:
    """
    Call the Postgres function silver.refresh_competition_results() and return its JSON result.
    """
    return _execute_refresh_function("refresh_competition_results")


def refresh_ladder() -> dict[str, Any]:
    """
    Call the Postgres function silver.refresh_ladder() and return its JSON result.
    """
    return _execute_refresh_function("refresh_ladder")


def refresh_all_silver() -> dict[str, Any]:
    """
    Refresh all silver tables in parallel. Since all functions read from the same
    bronze.latest_events table, they can be called together safely.
    
    Returns a dict with results from all refresh functions.
    """
    dsn = _get_dsn()
    if not dsn:
        return {"skipped": True, "reason": "no database DSN configured"}

    results = {}
    functions = [
        "refresh_competition_matches",
        "refresh_competitions", 
        "refresh_competition_competitors",
        "refresh_competition_results",
        "refresh_ladder"
    ]
    
    with psycopg2.connect(dsn) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            for func_name in functions:
                try:
                    cur.execute(f"SELECT silver.{func_name}();")
                    row = cur.fetchone()
                    if row:
                        payload = row[0]
                        if isinstance(payload, str):
                            try:
                                results[func_name] = json.loads(payload)
                            except Exception:
                                results[func_name] = {"result": payload}
                        elif isinstance(payload, dict):
                            results[func_name] = payload
                        else:
                            results[func_name] = {"result": payload}
                    else:
                        results[func_name] = {"result": None}
                except Exception as e:
                    results[func_name] = {"error": str(e)}
    
    return results
