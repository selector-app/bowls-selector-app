-- Silver schema and competitions transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Structured competitions table
CREATE TABLE IF NOT EXISTS silver.competitions (
    competition_id       UUID PRIMARY KEY,
    name                 TEXT,
    format               TEXT,
    timezone             TEXT,
    start_date_utc       BIGINT,
    end_date_utc         BIGINT,
    competition_type     TEXT,
    competition_status   TEXT,
    result_type          TEXT,
    source_event_hash    TEXT,
    source_event_at      TIMESTAMPTZ,
    created_at           TIMESTAMPTZ DEFAULT NOW(),
    updated_at           TIMESTAMPTZ DEFAULT NOW()
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_competitions_updated_at ON silver.competitions(updated_at);
CREATE INDEX IF NOT EXISTS idx_competitions_status ON silver.competitions(competition_status);

-- Refresh function to upsert from bronze.latest_events (endpoint = 'matches')
CREATE OR REPLACE FUNCTION silver.refresh_competitions()
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
          AND (inc->>'type') = 'competition'
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS competition_id,
            inc->'attributes'->>'name' AS name,
            inc->'attributes'->>'format' AS format,
            inc->'attributes'->>'timezone' AS timezone,
            (inc->'attributes'->>'startDateUtc')::bigint AS start_date_utc,
            (inc->'attributes'->>'endDateUtc')::bigint AS end_date_utc,
            inc->'attributes'->>'competitionType' AS competition_type,
            inc->'attributes'->>'competitionStatus' AS competition_status,
            inc->'attributes'->>'resultType' AS result_type,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
    )
    INSERT INTO silver.competitions (
        competition_id, name, format, timezone, start_date_utc, end_date_utc,
        competition_type, competition_status, result_type,
        source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.competition_id, s.name, s.format, s.timezone, s.start_date_utc, s.end_date_utc,
        s.competition_type, s.competition_status, s.result_type,
        s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    ON CONFLICT (competition_id) DO NOTHING;

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
          AND (inc->>'type') = 'competition'
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS competition_id,
            inc->'attributes'->>'name' AS name,
            inc->'attributes'->>'format' AS format,
            inc->'attributes'->>'timezone' AS timezone,
            (inc->'attributes'->>'startDateUtc')::bigint AS start_date_utc,
            (inc->'attributes'->>'endDateUtc')::bigint AS end_date_utc,
            inc->'attributes'->>'competitionType' AS competition_type,
            inc->'attributes'->>'competitionStatus' AS competition_status,
            inc->'attributes'->>'resultType' AS result_type,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
    )
    UPDATE silver.competitions c
    SET name               = s.name,
        format             = s.format,
        timezone           = s.timezone,
        start_date_utc     = s.start_date_utc,
        end_date_utc       = s.end_date_utc,
        competition_type   = s.competition_type,
        competition_status = s.competition_status,
        result_type        = s.result_type,
        source_event_hash  = s.source_event_hash,
        source_event_at    = s.source_event_at,
        updated_at         = NOW()
    FROM shaped s
    WHERE c.competition_id = s.competition_id
      AND (c.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
