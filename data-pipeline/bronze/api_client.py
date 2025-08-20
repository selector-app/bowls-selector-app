"""
API client module for BowlsLink Results API interactions.

Handles HTTP requests, JSON parsing, rate limiting, and response processing.
"""

import time
import hashlib
from typing import Any, Dict, List, Tuple
import httpx
import orjson


class BowlsLinkAPIClient:
    """HTTP client for BowlsLink Results API with polite rate limiting."""
    
    def __init__(self, user_agent: str = "RinkSheetETL/1.0 (+contact:you@example)", 
                 throttle_seconds: float = 0.3):
        """
        Initialize the API client.
        
        Args:
            user_agent: User-Agent string for requests
            throttle_seconds: Delay between requests to be polite to the API
        """
        self.user_agent = user_agent
        self.throttle_seconds = throttle_seconds
        
        # HTTP client configuration
        self.timeout = httpx.Timeout(20.0, connect=10.0)
        self.limits = httpx.Limits(max_connections=10, max_keepalive_connections=10)
        self.headers = {
            "User-Agent": user_agent, 
            "Accept": "application/json"
        }
    
    def _body_sha(self, content: bytes) -> str:
        """
        Return a SHA-256 hex digest for the given bytes.
        
        Treats None or empty bodies as an empty byte string to keep behavior consistent.
        Useful as a stable fingerprint of the response body for dedupe/auditing.
        """
        return hashlib.sha256(content or b"").hexdigest()
    
    def get_json(self, client: httpx.Client, url: str) -> Tuple[int, Any, str]:
        """
        Perform a GET and parse JSON if the content-type is JSON.
        
        Returns a tuple: (status_code, parsed_json_or_None, body_sha256).
        If parsing fails or content-type is not application/json, obj is None.
        """
        resp = client.get(url)
        content = resp.content if resp.content else b"{}"
        obj = None
        
        if resp.headers.get("content-type", "").startswith("application/json"):
            try:
                obj = orjson.loads(content)
            except Exception:
                obj = None
                
        return resp.status_code, obj, self._body_sha(content)
    
    def is_empty_response(self, status: int, obj: Any) -> bool:
        """
        Determine if an API response should be considered "empty".
        
        "Empty" means any of:
          - HTTP status >= 400
          - Parsed JSON is None
          - An empty list/dict, or dicts known to contain empty `matches`, `data`, or `ladderRows`
        """
        if status >= 400:
            return True
        elif obj is None:
            return True
        elif obj == {} or obj == []:
            return True
        elif isinstance(obj, dict):
            if "matches" in obj and isinstance(obj["matches"], list) and len(obj["matches"]) == 0:
                return True
            elif "data" in obj and isinstance(obj["data"], list) and len(obj["data"]) == 0:
                return True
            elif "data" in obj and isinstance(obj["data"], dict) and "matches" in obj["data"] and len(obj["data"]["matches"]) == 0:
                return True
            # Check for ladder data
            elif "data" in obj and isinstance(obj["data"], dict) and "ladderRows" in obj["data"] and len(obj["data"]["ladderRows"]) == 0:
                return True
        elif isinstance(obj, list) and len(obj) == 0:
            return True
            
        return False
    
    def _get_client(self) -> httpx.Client:
        """Get an HTTP client instance."""
        return httpx.Client(timeout=self.timeout, limits=self.limits, headers=self.headers)
    
    def discover_rounds(self, comp_id: str, matches_template: str, cap: int = 24) -> Tuple[int, int]:
        """
        Heuristically detect the inclusive round range for a competition.
        
        Probes rounds 1..cap on endpoints that contain {round} and stops after the
        first gap once at least one non-empty response was observed. This balances
        thoroughness with minimal request volume.
        
        Returns (start, end). If no non-empty response is ever found, returns (1, 1)
        to signal that probing was attempted but yielded nothing.
        """
        start, end = 1, 0
        
        with self._get_client() as client:
            for r in range(1, cap + 1):
                url = matches_template.format(competition_id=comp_id, round=r)
                
                try:
                    status, obj, _ = self.get_json(client, url)
                except Exception:
                    break
                    
                empty = self.is_empty_response(status, obj)
                
                if empty:
                    if end > 0:  # we had data, now a gap → stop
                        break
                else:
                    end = r
                    
                time.sleep(self.throttle_seconds)
        
        if end == 0:
            end = 1  # nothing found; still return something so we log the attempt
            
        return start, end
    
    def discover_sections(self, comp_id: str, ladder_template: str, cap: int = 30) -> Tuple[int, int]:
        """
        Heuristically detect the inclusive section range for a competition ladder.
        
        Probes sections 1..cap on endpoints that contain {section} and stops after the
        first gap once at least one non-empty response was observed. This balances
        thoroughness with minimal request volume.
        
        Returns (start, end). If no non-empty response is ever found, returns (1, 1)
        to signal that probing was attempted but yielded nothing.
        """
        start, end = 1, 0
        
        with self._get_client() as client:
            for s in range(1, cap + 1):
                url = ladder_template.format(competition_id=comp_id, section=s)
                
                try:
                    status, obj, _ = self.get_json(client, url)
                except Exception:
                    break
                    
                empty = self.is_empty_response(status, obj)
                
                if empty:
                    if end > 0:  # we had data, now a gap → stop
                        break
                else:
                    end = s
                    
                time.sleep(self.throttle_seconds)
        
        if end == 0:
            end = 1  # nothing found; still return something so we log the attempt
            
        return start, end
    
    def execute_requests(self, jobs: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """
        Execute a list of HTTP jobs and return results and errors.
        
        Args:
            jobs: List of job dicts with keys: endpoint, competition_id, round, url
            
        Returns:
            Tuple of (results, errors) where:
            - results: List of successful responses with metadata
            - errors: List of failed requests with error details
        """
        results = []
        errors = []
        
        with httpx.Client(timeout=self.timeout, limits=self.limits, headers=self.headers) as client:
            for job in jobs:
                try:
                    status, obj, bhash = self.get_json(client, job["url"])
                    results.append({
                        "endpoint": job["endpoint"],
                        "competition_id": job["competition_id"],
                        "round": job["round"],
                        "section": job.get("section"),
                        "url": job["url"],
                        "status_code": status,
                        "body_hash": bhash,
                        "payload": (obj if obj is not None else {})
                    })
                except Exception as e:
                    errors.append({"url": job["url"], "error": str(e)})
                    
                time.sleep(self.throttle_seconds)
        
        return results, errors
