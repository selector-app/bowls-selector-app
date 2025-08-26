"""
Main entrypoint wrapper for Cloud Functions deployment.

This file serves as the entry point for Google Cloud Functions Gen2,
which requires a main.py file in the root of the source directory.
"""

from flask import Request, jsonify

from bronze.main import main as bronze_main
from silver.refresh import refresh_all_silver


def main(request: Request):
    """
    HTTP entrypoint for Cloud Functions.
    
    This is a simple wrapper that delegates to the actual main function
    in the bronze layer, then triggers Silver refresh.
    """
    # Run Bronze pipeline
    bronze_resp = bronze_main(request)

    # Normalize Flask response and status
    if isinstance(bronze_resp, tuple):
        resp, status = bronze_resp
    else:
        resp, status = bronze_resp, 200

    # Extract JSON safely
    data = None
    try:
        data = resp.get_json(silent=True)
    except Exception:
        data = None

    # Trigger Silver refresh (in-DB). Safe if DSN missing.
    silver_result = {"skipped": True, "reason": "unknown"}
    try:
        silver_result = refresh_all_silver()
    except Exception as e:
        silver_result = {"error": str(e)}

    # If we could read the JSON body, append silver result and return new response
    if isinstance(data, dict):
        data["silver"] = silver_result
        return jsonify(data), status

    # Fallback: return original response
    return resp, status
