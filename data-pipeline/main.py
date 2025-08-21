"""
Main entrypoint wrapper for Cloud Functions deployment.

This file serves as the entry point for Google Cloud Functions Gen2,
which requires a main.py file in the root of the source directory.
"""

from flask import Request
from bronze.main import main as bronze_main

def main(request: Request):
    """
    HTTP entrypoint for Cloud Functions.
    
    This is a simple wrapper that delegates to the actual main function
    in the bronze layer.
    """
    return bronze_main(request)
