-- Silver schema and competition competitors transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Structured competition competitors table
CREATE TABLE IF NOT EXISTS silver.competition_competitors (
    competitor_id      UUID      NOT NULL,
    competition_id     UUID      NOT NULL,
    first_name         TEXT      NOT NULL,
    last_name          TEXT      NOT NULL,
    is_competing       BOOLEAN   NOT NULL,
    source_event_hash  TEXT,
    source_event_at    TIMESTAMPTZ,
    created_at         TIMESTAMPTZ DEFAULT NOW(),
    updated_at         TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (competitor_id, competition_id)
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_competition_competitors_competition_id ON silver.competition_competitors(competition_id);
CREATE INDEX IF NOT EXISTS idx_competition_competitors_updated_at ON silver.competition_competitors(updated_at);

-- Refresh function to upsert from bronze.latest_events (endpoint = 'ladder')
CREATE OR REPLACE FUNCTION silver.refresh_competition_competitors()
RETURNS JSON AS $$
DECLARE
    v_inserted INTEGER := 0;
    v_updated  INTEGER := 0;
BEGIN
    WITH parsed AS (
        SELECT
            le.competition_id::uuid AS competition_id,
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'ladder'
          AND le.status_code = 200
          AND (inc->>'type') = 'entrant'
    ), shaped AS (
        SELECT
            (inc->'includes'->'competitor'->>'id')::uuid AS competitor_id,
            competition_id,
            inc->'attributes'->>'firstName' AS first_name,
            inc->'attributes'->>'lastName' AS last_name,
            (inc->'attributes'->>'isCompeting')::boolean AS is_competing,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->'includes'->'competitor'->>'id' IS NOT NULL
          AND inc->'attributes'->>'firstName' IS NOT NULL
          AND inc->'attributes'->>'lastName' IS NOT NULL
    )
    INSERT INTO silver.competition_competitors (
        competitor_id, competition_id, first_name, last_name, is_competing,
        source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.competitor_id, s.competition_id, s.first_name, s.last_name, s.is_competing,
        s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    ON CONFLICT (competitor_id, competition_id) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- Update changed rows
    WITH parsed AS (
        SELECT
            le.competition_id::uuid AS competition_id,
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'ladder'
          AND le.status_code = 200
          AND (inc->>'type') = 'entrant'
    ), shaped AS (
        SELECT
            (inc->'includes'->'competitor'->>'id')::uuid AS competitor_id,
            competition_id,
            inc->'attributes'->>'firstName' AS first_name,
            inc->'attributes'->>'lastName' AS last_name,
            (inc->'attributes'->>'isCompeting')::boolean AS is_competing,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->'includes'->'competitor'->>'id' IS NOT NULL
          AND inc->'attributes'->>'firstName' IS NOT NULL
          AND inc->'attributes'->>'lastName' IS NOT NULL
    )
    UPDATE silver.competition_competitors cc
    SET first_name        = s.first_name,
        last_name         = s.last_name,
        is_competing      = s.is_competing,
        source_event_hash = s.source_event_hash,
        source_event_at   = s.source_event_at,
        updated_at        = NOW()
    FROM shaped s
    WHERE cc.competitor_id = s.competitor_id
      AND cc.competition_id = s.competition_id
      AND (cc.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
