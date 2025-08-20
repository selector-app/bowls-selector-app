-- Supabase database schema for BowlsLink data pipeline
-- Run this in your Supabase SQL editor

-- Create bronze schema
CREATE SCHEMA IF NOT EXISTS bronze;

-- Raw events table to store API responses
CREATE TABLE IF NOT EXISTS bronze.raw_events (
    id BIGSERIAL PRIMARY KEY,
    source VARCHAR(50) NOT NULL,
    endpoint VARCHAR(100) NOT NULL,
    request_url TEXT NOT NULL,
    status_code INTEGER NOT NULL,
    competition_id VARCHAR(36) NOT NULL,
    round_number INTEGER,
    section_number INTEGER,
    etl_version VARCHAR(20) NOT NULL,
    body_hash VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Endpoint catalog snapshots table
CREATE TABLE IF NOT EXISTS bronze.endpoint_catalog (
    id BIGSERIAL PRIMARY KEY,
    catalog_json JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_raw_events_competition_id ON bronze.raw_events(competition_id);
CREATE INDEX IF NOT EXISTS idx_raw_events_endpoint ON bronze.raw_events(endpoint);
CREATE INDEX IF NOT EXISTS idx_raw_events_section ON bronze.raw_events(section_number);
CREATE INDEX IF NOT EXISTS idx_raw_events_round ON bronze.raw_events(round_number);
CREATE INDEX IF NOT EXISTS idx_raw_events_created_at ON bronze.raw_events(created_at);
CREATE INDEX IF NOT EXISTS idx_raw_events_body_hash ON bronze.raw_events(body_hash);

-- Create a view for easy querying of latest events
CREATE OR REPLACE VIEW bronze.latest_events AS
SELECT DISTINCT ON (competition_id, endpoint, round_number, section_number)
    id,
    source,
    endpoint,
    request_url,
    status_code,
    competition_id,
    round_number,
    section_number,
    etl_version,
    body_hash,
    payload,
    created_at
FROM bronze.raw_events
ORDER BY competition_id, endpoint, round_number, section_number, created_at DESC;

-- Optional: Create a function to clean up old data
CREATE OR REPLACE FUNCTION bronze.cleanup_old_events(days_old INTEGER DEFAULT 30)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM bronze.raw_events 
    WHERE created_at < NOW() - INTERVAL '1 day' * days_old;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
