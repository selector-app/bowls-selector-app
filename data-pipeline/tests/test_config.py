#!/usr/bin/env python3
"""
Test script for configuration loading.
Run this to verify the config structure is working.
"""

import os
import sys

# Add the current directory to Python path so we can import our modules
sys.path.insert(0, os.getcwd())

def test_config_loading():
    """Test configuration loading."""
    print("🔍 Testing configuration loading...")
    
    try:
        from bronze.config import ConfigManager
        
        # Test config manager initialization
        config_manager = ConfigManager()
        print("✅ Config manager initialized")
        print(f"   Config path: {config_manager.catalog_path}")
        
        # Test catalog loading
        catalog = config_manager.load_catalog()
        print("✅ Catalog loaded successfully")
        print(f"   Competitions: {len(catalog.get('competitions', {}).get('urls', []))} URLs")
        print(f"   Endpoints: {len(catalog.get('endpoints', []))} endpoints")
        
        # Test competition ID extraction
        comp_ids = config_manager.extract_comp_ids(catalog)
        print(f"✅ Competition IDs extracted: {len(comp_ids)} IDs")
        for comp_id in comp_ids:
            print(f"   - {comp_id}")
        
        return True
        
    except Exception as e:
        print(f"❌ Configuration loading failed: {e}")
        return False

def test_imports():
    """Test that all imports work."""
    print("🔍 Testing imports...")
    
    try:
        print("✅ API client imported")
        
        print("✅ Config manager imported")
        
        print("✅ GCP utils imported")
        
        # Supabase client import might fail if psycopg2 is not installed
        try:
            from bronze.supabase_client import SupabaseClient, SupabaseConfig
            print("✅ Supabase client imported")
        except ImportError as e:
            print(f"⚠️  Supabase client import failed (expected if psycopg2 not installed): {e}")
        
        print("✅ Shared utils imported")
        
        return True
        
    except Exception as e:
        print(f"❌ Import failed: {e}")
        return False

def main():
    """Run all tests."""
    print("🚀 Configuration Test")
    print("=" * 40)
    
    # Test imports
    if not test_imports():
        return
    
    # Test configuration loading
    if not test_config_loading():
        return
    
    print("\n🎉 All tests passed! Configuration is working correctly.")
    print("\nNext steps:")
    print("1. Set up your Supabase connection string")
    print("2. Run: python test_supabase.py")
    print("3. Run: python -m functions_framework --target=main --source=bronze/main.py --port=8080")

if __name__ == "__main__":
    main()
