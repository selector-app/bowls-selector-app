"""
Configuration management for the BowlsLink data pipeline.

Handles loading the endpoints catalog, extracting competition IDs, and job generation.
"""

import os
import json
import re
from typing import Any, Dict, List
import httpx


class ConfigManager:
    """Manages configuration loading and job generation."""
    
    def __init__(self, catalog_path: str = None):
        """
        Initialize the configuration manager.
        
        Args:
            catalog_path: Path to the catalog JSON file. If None, uses ENDPOINTS_FILE env var or defaults to "endpoints.json"
        """
        if catalog_path:
            self.catalog_path = catalog_path
        else:
            # Try to get from environment variable, then fall back to config directory
            env_path = os.getenv("ENDPOINTS_FILE")
            if env_path:
                self.catalog_path = env_path
            else:
                # Try to find the config file in the config directory
                # Get the current working directory and look for config/endpoints.json
                import os as os_module
                current_dir = os_module.getcwd()
                config_path = os_module.path.join(current_dir, "config", "endpoints.json")
                
                if os_module.path.exists(config_path):
                    self.catalog_path = config_path
                else:
                    # Fallback to current directory
                    self.catalog_path = "endpoints.json"
        
        # Regex to extract competition UUID from Results Portal URLs
        self.comp_id_regex = re.compile(r"/competition/([0-9a-fA-F-]{36})")
    
    def load_catalog(self) -> Dict[str, Any]:
        """
        Load and parse the endpoints catalog JSON.
        
        Returns:
            Dict with keys like `competitions`, `rounds`, and `endpoints`.
        """
        with open(self.catalog_path, "r") as f:
            return json.load(f)
    
    def extract_comp_ids(self, cfg: Dict[str, Any]) -> List[str]:
        """
        Return a de-duplicated list of competition UUIDs from the catalog.
        
        Sources:
        - cfg["competitions"]["ids"]: literal UUID strings
        - cfg["competitions"]["urls"]: portal URLs that embed the UUID in the path
        
        Deduplication preserves the first occurrence order across sources.
        
        Args:
            cfg: The loaded catalog configuration
            
        Returns:
            List of unique competition IDs
        """
        out, seen = [], set()
        comp = cfg.get("competitions", {})
        
        # Extract from direct IDs
        for cid in comp.get("ids", []):
            if cid and cid not in seen:
                seen.add(cid)
                out.append(cid)
        
        # Extract from URLs
        for url in comp.get("urls", []):
            m = self.comp_id_regex.search(url)
            if m:
                cid = m.group(1)
                if cid not in seen:
                    seen.add(cid)
                    out.append(cid)
                    
        return out
    
    def is_rounded_endpoint(self, template: str) -> bool:
        """
        Detect if the endpoint template uses a {round} placeholder.
        
        Args:
            template: URL template string
            
        Returns:
            True if template contains {round} placeholder
        """
        return "{round}" in template
    
    def is_sectioned_endpoint(self, template: str) -> bool:
        """
        Detect if the endpoint template uses a {section} placeholder.
        
        Args:
            template: URL template string
            
        Returns:
            True if template contains {section} placeholder
        """
        return "{section}" in template
    
    def render_jobs(self, cfg: Dict[str, Any], comp_ids: List[str], 
                   api_client: Any) -> List[Dict[str, Any]]:
        """
        Expand the catalog into a concrete list of HTTP jobs to perform.
        
        For each endpoint template and competition ID, optionally expand over `round` or `section`
        depending on the catalog's configuration:
          - Rounds: "manual" uses `[start, end]` provided in the config, "auto" probes using `discover_rounds`
          - Sections: "manual" uses `[start, end]` provided in the config, "auto" probes using `discover_sections`
        
        Args:
            cfg: The loaded catalog configuration
            comp_ids: List of competition IDs to process
            api_client: API client instance for round/section discovery
            
        Returns:
            List of job dicts with keys: endpoint, competition_id, round, section, url
        """
        jobs = []
        rounds_cfg = cfg.get("rounds", {"mode": "manual", "start": 1, "end": 1})
        sections_cfg = cfg.get("sections", {"mode": "manual", "start": 1, "end": 1})
        
        for ep in cfg["endpoints"]:
            name, template = ep["name"], ep["url"]
            rounded = self.is_rounded_endpoint(template)
            sectioned = self.is_sectioned_endpoint(template)
            
            for comp_id in comp_ids:
                if rounded:
                    # Handle endpoints with round placeholders
                    mode = rounds_cfg.get("mode", "manual")
                    cap = int(rounds_cfg.get("cap", 24))
                    
                    if mode == "auto":
                        # Auto-discover round range
                        start, end = api_client.discover_rounds(comp_id, template, cap=cap)
                    else:
                        # Use manual round range
                        start = int(rounds_cfg.get("start", 1))
                        end = int(rounds_cfg.get("end", 1))
                    
                    # Generate jobs for each round
                    for r in range(start, end + 1):
                        jobs.append({
                            "endpoint": name,
                            "competition_id": comp_id,
                            "round": r,
                            "section": None,
                            "url": template.format(competition_id=comp_id, round=r)
                        })
                elif sectioned:
                    # Handle endpoints with section placeholders
                    mode = sections_cfg.get("mode", "manual")
                    cap = int(sections_cfg.get("cap", 30))
                    
                    if mode == "auto":
                        # Auto-discover section range
                        start, end = api_client.discover_sections(comp_id, template, cap=cap)
                    else:
                        # Use manual section range
                        start = int(sections_cfg.get("start", 1))
                        end = int(sections_cfg.get("end", 1))
                    
                    # Generate jobs for each section
                    for s in range(start, end + 1):
                        jobs.append({
                            "endpoint": name,
                            "competition_id": comp_id,
                            "round": None,
                            "section": s,
                            "url": template.format(competition_id=comp_id, section=s)
                        })
                else:
                    # Single call per competition (no rounds or sections)
                    jobs.append({
                        "endpoint": name,
                        "competition_id": comp_id,
                        "round": None,
                        "section": None,
                        "url": template.format(competition_id=comp_id)
                    })
        
        return jobs
