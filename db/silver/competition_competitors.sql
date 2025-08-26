-- Silver schema and competition competitors transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Structured competition competitors table
CREATE TABLE IF NOT EXISTS silver.competition_competitors (
    competitor_id      UUID      NOT NULL,
    competition_id     UUID      NOT NULL,
    name               TEXT      NOT NULL,
    source_event_hash  TEXT,
    source_event_at    TIMESTAMPTZ,
    created_at         TIMESTAMPTZ DEFAULT NOW(),
    updated_at         TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (competitor_id, competition_id)
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_competition_competitors_competition_id ON silver.competition_competitors(competition_id);
CREATE INDEX IF NOT EXISTS idx_competition_competitors_updated_at ON silver.competition_competitors(updated_at);

-- Refresh function to upsert from bronze.latest_events (endpoint = 'matches')
CREATE OR REPLACE FUNCTION silver.refresh_competition_competitors()
RETURNS JSON AS $$
DECLARE
    v_inserted INTEGER := 0;
    v_updated  INTEGER := 0;
BEGIN
    WITH parsed AS (
        SELECT
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'matches'
          AND le.status_code = 200
          AND (inc->>'type') = 'competitor'
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS competitor_id,
            CASE WHEN (inc->'includes'->'competition'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competition'->>'id')::uuid ELSE NULL END AS competition_id,
            inc->'attributes'->>'name' AS name,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
          AND inc->'includes'->'competition'->>'id' IS NOT NULL
          AND inc->'attributes'->>'name' IS NOT NULL
    )
    INSERT INTO silver.competition_competitors (
        competitor_id, competition_id, name,
        source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.competitor_id, s.competition_id, s.name,
        s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    WHERE s.competition_id IS NOT NULL
    ON CONFLICT (competitor_id, competition_id) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- Update changed rows
    WITH parsed AS (
        SELECT
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'matches'
          AND le.status_code = 200
          AND (inc->>'type') = 'competitor'
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS competitor_id,
            CASE WHEN (inc->'includes'->'competition'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competition'->>'id')::uuid ELSE NULL END AS competition_id,
            inc->'attributes'->>'name' AS name,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
          AND inc->'includes'->'competition'->>'id' IS NOT NULL
          AND inc->'attributes'->>'name' IS NOT NULL
    )
    UPDATE silver.competition_competitors cc
    SET name              = s.name,
        source_event_hash = s.source_event_hash,
        source_event_at   = s.source_event_at,
        updated_at        = NOW()
    FROM shaped s
    WHERE cc.competitor_id = s.competitor_id
      AND cc.competition_id = s.competition_id
      AND s.competition_id IS NOT NULL
      AND (cc.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
