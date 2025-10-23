-- Silver schema and rink matches transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Rink matches table for individual rink/side results within a match
CREATE TABLE IF NOT EXISTS silver.rink_matches (
    rink_match_id              UUID PRIMARY KEY,
    match_id                   UUID NOT NULL,
    result_id                  UUID,
    format                     TEXT,
    format_name                TEXT,
    specialisation             TEXT,
    sequence                   INTEGER,
    competitor_one_shots       INTEGER,
    competitor_two_shots       INTEGER,
    competitor_one_points      INTEGER,
    competitor_two_points      INTEGER,
    competitor_one_match_points INTEGER,
    competitor_two_match_points INTEGER,
    has_winner                 BOOLEAN,
    is_competitor_one_winner   BOOLEAN,
    is_competitor_two_winner   BOOLEAN,
    winner_id                  UUID,
    scoring_method             TEXT,
    status                     TEXT,
    source_event_hash          TEXT,
    source_event_at            TIMESTAMPTZ,
    created_at                 TIMESTAMPTZ DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ DEFAULT NOW()
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_rink_matches_match_id ON silver.rink_matches(match_id);
CREATE INDEX IF NOT EXISTS idx_rink_matches_result_id ON silver.rink_matches(result_id);
CREATE INDEX IF NOT EXISTS idx_rink_matches_updated_at ON silver.rink_matches(updated_at);

-- Refresh function to upsert from bronze.latest_events (endpoint = 'match')
CREATE OR REPLACE FUNCTION silver.refresh_rink_matches()
RETURNS JSON AS $$
DECLARE
    v_inserted INTEGER := 0;
    v_updated  INTEGER := 0;
BEGIN
    -- First, insert/update rinkMatch metadata
    WITH parsed_rink_match AS (
        SELECT
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'match'
          AND le.status_code = 200
          AND (inc->>'type') = 'rinkMatch'
    ), rink_match_shaped AS (
        SELECT
            (inc->>'id')::uuid AS rink_match_id,
            CASE WHEN (inc->'includes'->'match'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'match'->>'id')::uuid ELSE NULL END AS match_id,
            CASE WHEN (inc->'includes'->'result'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'result'->>'id')::uuid ELSE NULL END AS result_id,
            inc->'attributes'->>'format' AS format,
            inc->'attributes'->>'formatName' AS format_name,
            inc->'attributes'->>'specialisation' AS specialisation,
            (inc->'attributes'->>'sequence')::integer AS sequence,
            source_event_hash,
            source_event_at
        FROM parsed_rink_match
        WHERE inc->>'id' IS NOT NULL
    ),
    -- Now get the rinkMatchResult data
    parsed_result AS (
        SELECT
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'match'
          AND le.status_code = 200
          AND (inc->>'type') = 'rinkMatchResult'
    ), result_shaped AS (
        SELECT
            (inc->>'id')::uuid AS result_id,
            (inc->'attributes'->>'competitorOneShots')::integer AS competitor_one_shots,
            (inc->'attributes'->>'competitorTwoShots')::integer AS competitor_two_shots,
            (inc->'attributes'->>'competitorOnePoints')::integer AS competitor_one_points,
            (inc->'attributes'->>'competitorTwoPoints')::integer AS competitor_two_points,
            (inc->'attributes'->>'competitorOneMatchPoints')::integer AS competitor_one_match_points,
            (inc->'attributes'->>'competitorTwoMatchPoints')::integer AS competitor_two_match_points,
            (inc->'attributes'->>'hasWinner')::boolean AS has_winner,
            (inc->'attributes'->>'isCompetitorOneWinner')::boolean AS is_competitor_one_winner,
            (inc->'attributes'->>'isCompetitorTwoWinner')::boolean AS is_competitor_two_winner,
            CASE WHEN (inc->'attributes'->>'winnerId') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'attributes'->>'winnerId')::uuid ELSE NULL END AS winner_id,
            inc->'attributes'->>'scoringMethod' AS scoring_method,
            inc->'attributes'->>'status' AS status
        FROM parsed_result
        WHERE inc->>'id' IS NOT NULL
    ),
    combined AS (
        SELECT
            rm.rink_match_id,
            rm.match_id,
            rm.result_id,
            rm.format,
            rm.format_name,
            rm.specialisation,
            rm.sequence,
            r.competitor_one_shots,
            r.competitor_two_shots,
            r.competitor_one_points,
            r.competitor_two_points,
            r.competitor_one_match_points,
            r.competitor_two_match_points,
            r.has_winner,
            r.is_competitor_one_winner,
            r.is_competitor_two_winner,
            r.winner_id,
            r.scoring_method,
            r.status,
            rm.source_event_hash,
            rm.source_event_at
        FROM rink_match_shaped rm
        LEFT JOIN result_shaped r ON rm.result_id = r.result_id
    )
    INSERT INTO silver.rink_matches (
        rink_match_id, match_id, result_id, format, format_name, specialisation, sequence,
        competitor_one_shots, competitor_two_shots,
        competitor_one_points, competitor_two_points,
        competitor_one_match_points, competitor_two_match_points,
        has_winner, is_competitor_one_winner, is_competitor_two_winner,
        winner_id, scoring_method, status,
        source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        c.rink_match_id, c.match_id, c.result_id, c.format, c.format_name, c.specialisation, c.sequence,
        c.competitor_one_shots, c.competitor_two_shots,
        c.competitor_one_points, c.competitor_two_points,
        c.competitor_one_match_points, c.competitor_two_match_points,
        c.has_winner, c.is_competitor_one_winner, c.is_competitor_two_winner,
        c.winner_id, c.scoring_method, c.status,
        c.source_event_hash, c.source_event_at, NOW(), NOW()
    FROM combined c
    ON CONFLICT (rink_match_id) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- Update changed rows
    WITH parsed_rink_match AS (
        SELECT
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'match'
          AND le.status_code = 200
          AND (inc->>'type') = 'rinkMatch'
    ), rink_match_shaped AS (
        SELECT
            (inc->>'id')::uuid AS rink_match_id,
            CASE WHEN (inc->'includes'->'match'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'match'->>'id')::uuid ELSE NULL END AS match_id,
            CASE WHEN (inc->'includes'->'result'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'result'->>'id')::uuid ELSE NULL END AS result_id,
            inc->'attributes'->>'format' AS format,
            inc->'attributes'->>'formatName' AS format_name,
            inc->'attributes'->>'specialisation' AS specialisation,
            (inc->'attributes'->>'sequence')::integer AS sequence,
            source_event_hash,
            source_event_at
        FROM parsed_rink_match
        WHERE inc->>'id' IS NOT NULL
    ),
    parsed_result AS (
        SELECT
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'match'
          AND le.status_code = 200
          AND (inc->>'type') = 'rinkMatchResult'
    ), result_shaped AS (
        SELECT
            (inc->>'id')::uuid AS result_id,
            (inc->'attributes'->>'competitorOneShots')::integer AS competitor_one_shots,
            (inc->'attributes'->>'competitorTwoShots')::integer AS competitor_two_shots,
            (inc->'attributes'->>'competitorOnePoints')::integer AS competitor_one_points,
            (inc->'attributes'->>'competitorTwoPoints')::integer AS competitor_two_points,
            (inc->'attributes'->>'competitorOneMatchPoints')::integer AS competitor_one_match_points,
            (inc->'attributes'->>'competitorTwoMatchPoints')::integer AS competitor_two_match_points,
            (inc->'attributes'->>'hasWinner')::boolean AS has_winner,
            (inc->'attributes'->>'isCompetitorOneWinner')::boolean AS is_competitor_one_winner,
            (inc->'attributes'->>'isCompetitorTwoWinner')::boolean AS is_competitor_two_winner,
            CASE WHEN (inc->'attributes'->>'winnerId') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'attributes'->>'winnerId')::uuid ELSE NULL END AS winner_id,
            inc->'attributes'->>'scoringMethod' AS scoring_method,
            inc->'attributes'->>'status' AS status
        FROM parsed_result
        WHERE inc->>'id' IS NOT NULL
    ),
    combined AS (
        SELECT
            rm.rink_match_id,
            rm.match_id,
            rm.result_id,
            rm.format,
            rm.format_name,
            rm.specialisation,
            rm.sequence,
            r.competitor_one_shots,
            r.competitor_two_shots,
            r.competitor_one_points,
            r.competitor_two_points,
            r.competitor_one_match_points,
            r.competitor_two_match_points,
            r.has_winner,
            r.is_competitor_one_winner,
            r.is_competitor_two_winner,
            r.winner_id,
            r.scoring_method,
            r.status,
            rm.source_event_hash,
            rm.source_event_at
        FROM rink_match_shaped rm
        LEFT JOIN result_shaped r ON rm.result_id = r.result_id
    )
    UPDATE silver.rink_matches rm
    SET match_id                     = c.match_id,
        result_id                    = c.result_id,
        format                       = c.format,
        format_name                  = c.format_name,
        specialisation               = c.specialisation,
        sequence                     = c.sequence,
        competitor_one_shots         = c.competitor_one_shots,
        competitor_two_shots         = c.competitor_two_shots,
        competitor_one_points        = c.competitor_one_points,
        competitor_two_points        = c.competitor_two_points,
        competitor_one_match_points  = c.competitor_one_match_points,
        competitor_two_match_points  = c.competitor_two_match_points,
        has_winner                   = c.has_winner,
        is_competitor_one_winner     = c.is_competitor_one_winner,
        is_competitor_two_winner     = c.is_competitor_two_winner,
        winner_id                    = c.winner_id,
        scoring_method               = c.scoring_method,
        status                       = c.status,
        source_event_hash            = c.source_event_hash,
        source_event_at              = c.source_event_at,
        updated_at                   = NOW()
    FROM combined c
    WHERE rm.rink_match_id = c.rink_match_id
      AND (rm.source_event_hash IS DISTINCT FROM c.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
