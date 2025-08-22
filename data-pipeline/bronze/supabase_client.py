"""
Supabase client for the BowlsLink data pipeline.

Handles database operations, data storage, and Supabase-specific functionality.
"""

import json
import os
from typing import Any

import psycopg2
from psycopg2.extras import RealDictCursor


class SupabaseClient:
    """Client for Supabase database operations."""
    
    def __init__(self, connection_string: str):
        """
        Initialize the Supabase client.
        
        Args:
            connection_string: PostgreSQL connection string for Supabase
        """
        self.connection_string = connection_string
    
    def _get_connection(self):
        """Get a database connection."""
        return psycopg2.connect(self.connection_string)
    
    def store_raw_events(self, events: list[dict[str, Any]]) -> int:
        """
        Store raw API events in the bronze layer.
        
        Args:
            events: List of event dictionaries with API response data
            
        Returns:
            Number of events successfully stored
        """
        stored_count = 0
        
        with self._get_connection() as conn:
            conn.autocommit = True
            
            with conn.cursor() as cur:
                for event in events:
                    try:
                        cur.execute("""
                            INSERT INTO bronze.raw_events(
                                source, endpoint, request_url, status_code,
                                competition_id, round_number, section_number, etl_version, body_hash, payload
                            )
                            SELECT %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                            WHERE NOT EXISTS (
                                SELECT 1 FROM bronze.raw_events r
                                WHERE r.endpoint = %s
                                  AND r.competition_id = %s
                                  AND COALESCE(r.round_number, -1) = COALESCE(%s, -1)
                                  AND COALESCE(r.section_number, -1) = COALESCE(%s, -1)
                                  AND r.body_hash = %s
                            )
                        """, (
                            "bowlslink",
                            event["endpoint"],
                            event["url"],
                            event["status_code"],
                            event["competition_id"],
                            event["round"],
                            event.get("section"),
                            "v1",
                            event["body_hash"],
                            json.dumps(event["payload"]),
                            # WHERE NOT EXISTS parameters
                            event["endpoint"],
                            event["competition_id"],
                            event["round"],
                            event.get("section"),
                            event["body_hash"],
                        ))
                        # rowcount is 1 when inserted, 0 when conflict prevented insert
                        stored_count += (cur.rowcount or 0)
                    except Exception as e:
                        print(f"Failed to store event: {e}")
                        continue
        
        return stored_count
    
    def store_catalog_snapshot(self, catalog: dict[str, Any]) -> bool:
        """
        Store a snapshot of the catalog configuration.
        
        Args:
            catalog: The catalog configuration dictionary
            
        Returns:
            True if successfully stored, False otherwise
        """
        try:
            with self._get_connection() as conn:
                conn.autocommit = True
                
                with conn.cursor() as cur:
                    cur.execute(
                        "INSERT INTO bronze.endpoint_catalog(catalog_json) VALUES (%s)",
                        (json.dumps(catalog),)
                    )
            return True
        except Exception as e:
            print(f"Failed to store catalog snapshot: {e}")
            return False
    
    def get_latest_events(self, competition_id: str = None, 
                         endpoint: str = None, section: int = None, limit: int = 100) -> list[dict[str, Any]]:
        """
        Retrieve the latest raw events from the database.
        
        Args:
            competition_id: Optional filter by competition ID
            endpoint: Optional filter by endpoint name
            section: Optional filter by section number
            limit: Maximum number of events to return
            
        Returns:
            List of event dictionaries
        """
        query = """
            SELECT * FROM bronze.raw_events 
            WHERE 1=1
        """
        params = []
        
        if competition_id:
            query += " AND competition_id = %s"
            params.append(competition_id)
        
        if endpoint:
            query += " AND endpoint = %s"
            params.append(endpoint)
        
        if section is not None:
            query += " AND section_number = %s"
            params.append(section)
        
        query += " ORDER BY created_at DESC LIMIT %s"
        params.append(limit)
        
        try:
            with self._get_connection() as conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    cur.execute(query, params)
                    return [dict(row) for row in cur.fetchall()]
        except Exception as e:
            print(f"Failed to retrieve events: {e}")
            return []
    
    def get_event_count(self, competition_id: str = None, 
                       endpoint: str = None, section: int = None) -> int:
        """
        Get the count of events in the database.
        
        Args:
            competition_id: Optional filter by competition ID
            endpoint: Optional filter by endpoint name
            section: Optional filter by section number
            
        Returns:
            Number of events matching the criteria
        """
        query = "SELECT COUNT(*) FROM bronze.raw_events WHERE 1=1"
        params = []
        
        if competition_id:
            query += " AND competition_id = %s"
            params.append(competition_id)
        
        if endpoint:
            query += " AND endpoint = %s"
            params.append(endpoint)
        
        if section is not None:
            query += " AND section_number = %s"
            params.append(section)
        
        try:
            with self._get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute(query, params)
                    return cur.fetchone()[0]
        except Exception as e:
            print(f"Failed to get event count: {e}")
            return 0
    
    def cleanup_old_events(self, days_old: int = 30) -> int:
        """
        Clean up events older than specified days.
        
        Args:
            days_old: Remove events older than this many days
            
        Returns:
            Number of events deleted
        """
        try:
            with self._get_connection() as conn:
                conn.autocommit = True
                
                with conn.cursor() as cur:
                    cur.execute("""
                        DELETE FROM bronze.raw_events 
                        WHERE created_at < NOW() - INTERVAL '%s days'
                    """, (days_old,))
                    return cur.rowcount
        except Exception as e:
            print(f"Failed to cleanup old events: {e}")
            return 0


class SupabaseConfig:
    """Configuration for Supabase connection."""
    
    @staticmethod
    def get_connection_string() -> str | None:
        """
        Get the Supabase connection string from environment.
        
        Returns:
            Connection string if available, None otherwise
        """
        return os.getenv("SUPABASE_DB_URL") or os.getenv("PG_DSN")
    
    @staticmethod
    def is_available() -> bool:
        """
        Check if Supabase is configured and available.
        
        Returns:
            True if connection string is available
        """
        return bool(SupabaseConfig.get_connection_string())
