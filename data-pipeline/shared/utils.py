"""
Shared utilities for the BowlsLink data pipeline.

Common functions used across bronze, silver, and gold layers.
"""

import logging
import os

# Load environment variables from .env file if it exists
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


def load_environment() -> None:
    """
    Load environment variables from .env file if it exists.
    This should be called early in the application startup.
    """
    try:
        from dotenv import load_dotenv
        load_dotenv()
    except ImportError:
        pass


def setup_logging(level: str = "INFO", 
                 format_string: str | None = None) -> logging.Logger:
    """
    Set up logging configuration for the pipeline.
    
    Args:
        level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        format_string: Custom format string for log messages
        
    Returns:
        Configured logger instance
    """
    if format_string is None:
        format_string = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    
    logging.basicConfig(
        level=getattr(logging, level.upper()),
        format=format_string,
        datefmt="%Y-%m-%d %H:%M:%S"
    )
    
    return logging.getLogger(__name__)


def get_config_path(config_name: str) -> str:
    """
    Get the path to a configuration file in the config directory.
    
    Args:
        config_name: Name of the config file (e.g., 'endpoints.json')
        
    Returns:
        Full path to the config file
    """
    # Get the current working directory and look for config/endpoints.json
    current_dir = os.getcwd()
    config_path = os.path.join(current_dir, 'config', config_name)
    
    # If not found in current directory, try relative to the shared module
    if not os.path.exists(config_path):
        # Get the directory where this file is located
        shared_dir = os.path.dirname(os.path.abspath(__file__))
        # Go up one level to data-pipeline, then into config
        config_dir = os.path.join(os.path.dirname(shared_dir), 'config')
        config_path = os.path.join(config_dir, config_name)
    
    return config_path


def validate_environment() -> dict:
    """
    Validate that required environment variables are set.
    
    Returns:
        Dictionary of validated environment variables
    """
    required_vars = {
        'ENDPOINTS_FILE': os.getenv('ENDPOINTS_FILE', 'endpoints.json'),
        'THROTTLE_S': os.getenv('THROTTLE_S', '0.3'),
    }
    
    optional_vars = {
        'SUPABASE_DB_URL': os.getenv('SUPABASE_DB_URL'),
        'PG_DSN': os.getenv('PG_DSN'),
    }
    
    # Validate required variables
    for var_name, value in required_vars.items():
        if not value:
            raise ValueError(f"Required environment variable {var_name} is not set")
    
    return {**required_vars, **optional_vars}
