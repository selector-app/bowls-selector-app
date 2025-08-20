"""
Main entrypoint for the BowlsLink data pipeline.

Orchestrates API calls, configuration management, and optional database storage.
"""

import os
import uuid
from typing import Dict, Any
from flask import Request, jsonify

# Load environment variables and setup logging
try:
    from shared.utils import load_environment, setup_logging
    load_environment()
    logger = setup_logging()
except ImportError:
    # Fallback if shared module not available
    try:
        from dotenv import load_dotenv
        load_dotenv()
    except ImportError:
        pass
    logger = None

from .api_client import BowlsLinkAPIClient
from .config import ConfigManager
from .gcp_utils import GCPLogger, GCPConfig
from .supabase_client import SupabaseClient, SupabaseConfig


def main(request: Request):
    """
    HTTP entrypoint expected by Functions Framework.
    
    Orchestrates the data pipeline:
      - Loads configuration and extracts competition IDs
      - Builds job list across endpoints x competitions x rounds
      - Executes HTTP requests with throttling
      - Optionally stores results in Supabase
      - Returns aggregated results and any error samples as JSON
    """
    # Generate request ID for tracking
    request_id = str(uuid.uuid4())
    
    # Initialize components
    logger = GCPLogger()
    config_manager = ConfigManager()
    api_client = BowlsLinkAPIClient(
        user_agent="RinkSheetETL/1.0 (+contact:you@example)",
        throttle_seconds=float(os.getenv("THROTTLE_S", "0.3"))
    )
    
    # Log request start
    logger.log_request_start(request_id)
    
    try:
        # Load configuration and extract competition IDs
        cfg = config_manager.load_catalog()
        comp_ids = config_manager.extract_comp_ids(cfg)
        
        if not comp_ids:
            logger.log_error(request_id, "No competitions provided")
            return jsonify({"status": "error", "reason": "no competitions provided"}), 400
        
        # Generate jobs
        jobs = config_manager.render_jobs(cfg, comp_ids, api_client)
        
        # Execute API requests
        results, errors = api_client.execute_requests(jobs)
        
        # Optionally store in Supabase if configured
        stored_count = 0
        if SupabaseConfig.is_available():
            try:
                supabase = SupabaseClient(SupabaseConfig.get_connection_string())
                stored_count = supabase.store_raw_events(results)
                supabase.store_catalog_snapshot(cfg)
            except Exception as e:
                logger.log_error(request_id, f"Supabase storage failed: {e}")
        
        # Log completion
        logger.log_request_complete(
            request_id, 
            results_count=len(results), 
            errors_count=len(errors),
            stored_count=stored_count
        )
        
        # Return response
        response_data = {
            "status": "ok",
            "request_id": request_id,
            "results": results,
            "errors": errors,
            "summary": {
                "total_jobs": len(jobs),
                "successful_requests": len(results),
                "failed_requests": len(errors),
                "stored_in_db": stored_count
            }
        }
        
        # Add GCP metadata if in GCP environment
        if GCPConfig.is_gcp_environment():
            response_data["gcp_metadata"] = GCPConfig.get_function_metadata()
        
        return jsonify(response_data)
        
    except Exception as e:
        logger.log_error(request_id, f"Unexpected error: {e}")
        return jsonify({
            "status": "error", 
            "reason": "unexpected error",
            "error": str(e),
            "request_id": request_id
        }), 500


if __name__ == "__main__":
    # For local development
    from functions_framework import create_app
    app = create_app(target="main", source="main.py")
    app.run(debug=True, host="0.0.0.0", port=8080)
