-- Silver schema and competition matches transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Structured competition matches table
CREATE TABLE IF NOT EXISTS silver.competition_matches (
    match_id           UUID PRIMARY KEY,
    result_id          UUID,
    competition_id     UUID,
    competitor_one_id  UUID,
    competitor_two_id  UUID,
    section            INTEGER,
    round              INTEGER,
    state              TEXT,
    timezone           TEXT,
    match_day_utc      BIGINT,
    match_time_utc     BIGINT,
    source_event_hash  TEXT,
    source_event_at    TIMESTAMPTZ,
    created_at         TIMESTAMPTZ DEFAULT NOW(),
    updated_at         TIMESTAMPTZ DEFAULT NOW()
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_competition_matches_competition_id ON silver.competition_matches(competition_id);
CREATE INDEX IF NOT EXISTS idx_competition_matches_round ON silver.competition_matches(round);
CREATE INDEX IF NOT EXISTS idx_competition_matches_updated_at ON silver.competition_matches(updated_at);

-- Refresh function to upsert from bronze.latest_events (endpoint = 'matches')
CREATE OR REPLACE FUNCTION silver.refresh_competition_matches()
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
          AND (inc->>'type') = 'match'
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS match_id,
            CASE WHEN (inc->'includes'->'result'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'result'->>'id')::uuid ELSE NULL END AS result_id,
            CASE WHEN (inc->'includes'->'competition'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competition'->>'id')::uuid ELSE NULL END AS competition_id,
            CASE WHEN (inc->'includes'->'competitorOne'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competitorOne'->>'id')::uuid ELSE NULL END AS competitor_one_id,
            CASE WHEN (inc->'includes'->'competitorTwo'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competitorTwo'->>'id')::uuid ELSE NULL END AS competitor_two_id,
            (inc->'attributes'->>'pool')::int AS section,
            (inc->'attributes'->>'round')::int AS round,
            inc->'attributes'->>'state' AS state,
            inc->'attributes'->>'timezone' AS timezone,
            (inc->'attributes'->>'matchDayUtc')::bigint AS match_day_utc,
            (inc->'attributes'->>'matchTimeUtc')::bigint AS match_time_utc,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
    )
    INSERT INTO silver.competition_matches (
        match_id, result_id, competition_id,
        competitor_one_id, competitor_two_id,
        section, round, state, timezone,
        match_day_utc, match_time_utc,
        source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.match_id, s.result_id, s.competition_id,
        s.competitor_one_id, s.competitor_two_id,
        s.section, s.round, s.state, s.timezone,
        s.match_day_utc, s.match_time_utc,
        s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    ON CONFLICT (match_id) DO NOTHING;

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
          AND (inc->>'type') = 'match'
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS match_id,
            CASE WHEN (inc->'includes'->'result'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'result'->>'id')::uuid ELSE NULL END AS result_id,
            CASE WHEN (inc->'includes'->'competition'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competition'->>'id')::uuid ELSE NULL END AS competition_id,
            CASE WHEN (inc->'includes'->'competitorOne'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competitorOne'->>'id')::uuid ELSE NULL END AS competitor_one_id,
            CASE WHEN (inc->'includes'->'competitorTwo'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competitorTwo'->>'id')::uuid ELSE NULL END AS competitor_two_id,
            (inc->'attributes'->>'pool')::int AS section,
            (inc->'attributes'->>'round')::int AS round,
            inc->'attributes'->>'state' AS state,
            inc->'attributes'->>'timezone' AS timezone,
            (inc->'attributes'->>'matchDayUtc')::bigint AS match_day_utc,
            (inc->'attributes'->>'matchTimeUtc')::bigint AS match_time_utc,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
    )
    UPDATE silver.competition_matches m
    SET result_id         = s.result_id,
        competition_id    = s.competition_id,
        competitor_one_id = s.competitor_one_id,
        competitor_two_id = s.competitor_two_id,
        section           = s.section,
        round             = s.round,
        state             = s.state,
        timezone          = s.timezone,
        match_day_utc     = s.match_day_utc,
        match_time_utc    = s.match_time_utc,
        source_event_hash = s.source_event_hash,
        source_event_at   = s.source_event_at,
        updated_at        = NOW()
    FROM shaped s
    WHERE m.match_id = s.match_id
      AND (m.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
