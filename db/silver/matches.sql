-- Silver schema and matches transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Structured matches table
CREATE TABLE IF NOT EXISTS silver.matches (
    match_id            UUID PRIMARY KEY,
    competition_id      UUID,
    round_number       INTEGER,
    round_label        TEXT,
    section_label      TEXT,
    pool               INTEGER,
    is_finals_series   BOOLEAN,
    state              TEXT,
    match_state        TEXT,
    timezone           TEXT,
    utc_offset_seconds INTEGER,
    match_day_utc      TIMESTAMPTZ,
    match_time_utc     TIMESTAMPTZ,
    match_time_local   TIMESTAMPTZ,
    competitor_one_id  UUID,
    competitor_two_id  UUID,
    location_id        UUID,
    result_id          UUID,
    source_event_hash  TEXT,
    source_event_at    TIMESTAMPTZ,
    created_at         TIMESTAMPTZ DEFAULT NOW(),
    updated_at         TIMESTAMPTZ DEFAULT NOW()
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_matches_competition_id ON silver.matches(competition_id);
CREATE INDEX IF NOT EXISTS idx_matches_round ON silver.matches(round_number);
CREATE INDEX IF NOT EXISTS idx_matches_updated_at ON silver.matches(updated_at);

-- Refresh function to upsert from bronze.latest_events (endpoint = 'matches')
CREATE OR REPLACE FUNCTION silver.refresh_matches()
RETURNS JSON AS $$
DECLARE
    v_inserted INTEGER := 0;
    v_updated  INTEGER := 0;
BEGIN
    WITH parsed AS (
        SELECT
            -- source row context
            le.body_hash                           AS source_event_hash,
            le.created_at                          AS source_event_at,
            -- expand JSON payload
            inc                                     AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'matches'
          AND le.status_code = 200
          AND (inc->>'type') = 'match'
    ), shaped AS (
        SELECT
            -- IDs
            NULLIF(inc->>'id','')::uuid                                            AS match_id,
            COALESCE(NULLIF((inc->'includes'->'competition'->>'id'),'')::uuid, NULL) AS competition_id,
            -- Competitors
            NULLIF((inc->'includes'->'competitorOne'->>'id'),'')::uuid              AS competitor_one_id,
            NULLIF((inc->'includes'->'competitorTwo'->>'id'),'')::uuid              AS competitor_two_id,
            -- Location (first element if present)
            NULLIF((inc->'includes'->'matchLocation'->0->>'id'),'')::uuid          AS location_id,
            NULLIF((inc->'includes'->'result'->>'id'),'')::uuid                     AS result_id,
            -- Attributes
            (inc->'attributes'->>'round')::int                                      AS round_number,
            inc->'attributes'->>'roundLabel'                                        AS round_label,
            inc->'attributes'->>'sectionLabel'                                      AS section_label,
            (inc->'attributes'->>'pool')::int                                       AS pool,
            COALESCE((inc->'attributes'->>'isFinalsSeries')::bool, false)           AS is_finals_series,
            inc->'attributes'->>'state'                                             AS state,
            inc->'attributes'->>'matchState'                                        AS match_state,
            inc->'attributes'->>'timezone'                                          AS timezone,
            COALESCE((inc->'attributes'->>'timeUTCOffset')::int,
                     (inc->'attributes'->>'dayUTCOffset')::int, 0)                  AS utc_offset_seconds,
            -- Timestamps
            CASE WHEN (inc->'attributes'->>'matchDayUtc') IS NOT NULL
                 THEN to_timestamp((inc->'attributes'->>'matchDayUtc')::bigint)
                 ELSE NULL END                                                      AS match_day_utc,
            CASE WHEN (inc->'attributes'->>'matchTimeUtc') IS NOT NULL
                 THEN to_timestamp((inc->'attributes'->>'matchTimeUtc')::bigint)
                 ELSE NULL END                                                      AS match_time_utc,
            CASE WHEN (inc->'attributes'->>'matchTimeUtc') IS NOT NULL
                 THEN to_timestamp(((inc->'attributes'->>'matchTimeUtc')::bigint +
                                     COALESCE((inc->'attributes'->>'timeUTCOffset')::int,
                                              (inc->'attributes'->>'dayUTCOffset')::int, 0)))
                 ELSE NULL END                                                      AS match_time_local,
            -- Source
            source_event_hash,
            source_event_at
        FROM parsed
    )
    -- First insert new rows
    INSERT INTO silver.matches (
        match_id, competition_id, round_number, round_label, section_label,
        pool, is_finals_series, state, match_state, timezone, utc_offset_seconds,
        match_day_utc, match_time_utc, match_time_local,
        competitor_one_id, competitor_two_id, location_id, result_id,
        source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.match_id, s.competition_id, s.round_number, s.round_label, s.section_label,
        s.pool, s.is_finals_series, s.state, s.match_state, s.timezone, s.utc_offset_seconds,
        s.match_day_utc, s.match_time_utc, s.match_time_local,
        s.competitor_one_id, s.competitor_two_id, s.location_id, s.result_id,
        s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    ON CONFLICT (match_id) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- Then update changed rows
    WITH shaped AS (
        SELECT
            -- IDs
            NULLIF(inc->>'id','')::uuid                                            AS match_id,
            COALESCE(NULLIF((inc->'includes'->'competition'->>'id'),'')::uuid, NULL) AS competition_id,
            NULLIF((inc->'includes'->'competitorOne'->>'id'),'')::uuid              AS competitor_one_id,
            NULLIF((inc->'includes'->'competitorTwo'->>'id'),'')::uuid              AS competitor_two_id,
            NULLIF((inc->'includes'->'matchLocation'->0->>'id'),'')::uuid          AS location_id,
            NULLIF((inc->'includes'->'result'->>'id'),'')::uuid                     AS result_id,
            (inc->'attributes'->>'round')::int                                      AS round_number,
            inc->'attributes'->>'roundLabel'                                        AS round_label,
            inc->'attributes'->>'sectionLabel'                                      AS section_label,
            (inc->'attributes'->>'pool')::int                                       AS pool,
            COALESCE((inc->'attributes'->>'isFinalsSeries')::bool, false)           AS is_finals_series,
            inc->'attributes'->>'state'                                             AS state,
            inc->'attributes'->>'matchState'                                        AS match_state,
            inc->'attributes'->>'timezone'                                          AS timezone,
            COALESCE((inc->'attributes'->>'timeUTCOffset')::int,
                     (inc->'attributes'->>'dayUTCOffset')::int, 0)                  AS utc_offset_seconds,
            CASE WHEN (inc->'attributes'->>'matchDayUtc') IS NOT NULL
                 THEN to_timestamp((inc->'attributes'->>'matchDayUtc')::bigint)
                 ELSE NULL END                                                      AS match_day_utc,
            CASE WHEN (inc->'attributes'->>'matchTimeUtc') IS NOT NULL
                 THEN to_timestamp((inc->'attributes'->>'matchTimeUtc')::bigint)
                 ELSE NULL END                                                      AS match_time_utc,
            CASE WHEN (inc->'attributes'->>'matchTimeUtc') IS NOT NULL
                 THEN to_timestamp(((inc->'attributes'->>'matchTimeUtc')::bigint +
                                     COALESCE((inc->'attributes'->>'timeUTCOffset')::int,
                                              (inc->'attributes'->>'dayUTCOffset')::int, 0)))
                 ELSE NULL END                                                      AS match_time_local,
            source_event_hash,
            source_event_at
        FROM (
            SELECT le.body_hash AS source_event_hash,
                   le.created_at AS source_event_at,
                   inc
            FROM bronze.latest_events le,
                 LATERAL jsonb_array_elements(le.payload->'include') inc
            WHERE le.endpoint = 'matches'
              AND le.status_code = 200
              AND (inc->>'type') = 'match'
        ) x
    )
    UPDATE silver.matches m
    SET competition_id      = s.competition_id,
        round_number        = s.round_number,
        round_label         = s.round_label,
        section_label       = s.section_label,
        pool                = s.pool,
        is_finals_series    = s.is_finals_series,
        state               = s.state,
        match_state         = s.match_state,
        timezone            = s.timezone,
        utc_offset_seconds  = s.utc_offset_seconds,
        match_day_utc       = s.match_day_utc,
        match_time_utc      = s.match_time_utc,
        match_time_local    = s.match_time_local,
        competitor_one_id   = s.competitor_one_id,
        competitor_two_id   = s.competitor_two_id,
        location_id         = s.location_id,
        result_id           = s.result_id,
        source_event_hash   = s.source_event_hash,
        source_event_at     = s.source_event_at,
        updated_at          = NOW()
    FROM shaped s
    WHERE m.match_id = s.match_id
      AND (m.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
