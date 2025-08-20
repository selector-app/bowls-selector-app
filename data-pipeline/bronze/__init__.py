"""
Bronze layer ETL for BowlsLink data pipeline.

This module handles the raw data ingestion from external APIs
and stores it in the bronze layer of the data lake.
"""

from .api_client import BowlsLinkAPIClient
from .config import ConfigManager
from .gcp_utils import GCPLogger, GCPConfig
from .supabase_client import SupabaseClient, SupabaseConfig
from .main import main

__all__ = [
    'BowlsLinkAPIClient',
    'ConfigManager', 
    'GCPLogger',
    'GCPConfig',
    'SupabaseClient',
    'SupabaseConfig',
    'main'
]
