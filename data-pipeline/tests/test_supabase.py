#!/usr/bin/env python3
"""
Test script for Supabase connection and basic operations.
Run this to verify your Supabase setup is working.
"""

import os
import sys
import json

# Add the current directory to Python path so we can import our modules
sys.path.insert(0, os.getcwd())

from bronze.supabase_client import SupabaseClient, SupabaseConfig

def test_supabase_connection():
    """Test basic Supabase connectivity."""
    print("🔍 Testing Supabase configuration...")
    
    # Check if Supabase is configured
    if not SupabaseConfig.is_available():
        print("❌ Supabase not configured!")
        print("   Set SUPABASE_DB_URL environment variable or create a .env file")
        return False
    
    print("✅ Supabase configuration found")
    
    # Test connection
    try:
        connection_string = SupabaseConfig.get_connection_string()
        print(f"🔗 Connection string: {connection_string[:50]}...")
        
        # Create client and test connection
        client = SupabaseClient(connection_string)
        
        # Test a simple query
        with client._get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT version()")
                version = cur.fetchone()[0]
                print(f"✅ Database connection successful!")
                print(f"   PostgreSQL version: {version}")
        
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

def test_basic_operations():
    """Test basic database operations."""
    print("\n🧪 Testing basic operations...")
    
    try:
        client = SupabaseClient(SupabaseConfig.get_connection_string())
        
        # Test storing a catalog snapshot
        test_catalog = {
            "test": True,
            "timestamp": "2024-01-01T00:00:00Z"
        }
        
        success = client.store_catalog_snapshot(test_catalog)
        if success:
            print("✅ Catalog snapshot storage works")
        else:
            print("❌ Catalog snapshot storage failed")
        
        # Test getting event count
        count = client.get_event_count()
        print(f"✅ Event count query works: {count} events")
        
        # Test getting latest events
        events = client.get_latest_events(limit=5)
        print(f"✅ Latest events query works: {len(events)} events retrieved")
        
        return True
        
    except Exception as e:
        print(f"❌ Basic operations failed: {e}")
        return False

def main():
    """Run all tests."""
    print("🚀 Supabase Connection Test")
    print("=" * 40)
    
    # Test connection
    if not test_supabase_connection():
        return
    
    # Test operations
    if not test_basic_operations():
        return
    
    print("\n🎉 All tests passed! Supabase is ready to use.")
    print("\nNext steps:")
    print("1. Run your data pipeline: python -m functions_framework --target=main --source=bronze/main.py --port=8080")
    print("2. Check the response for 'stored_in_db' count")
    print("3. View your data in Supabase dashboard under Table Editor")

if __name__ == "__main__":
    main()
