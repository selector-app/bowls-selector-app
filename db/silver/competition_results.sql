-- Silver schema and competition results transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Structured competition results table with enhanced multiFormatResult fields
CREATE TABLE IF NOT EXISTS silver.competition_results (
    result_id                     UUID PRIMARY KEY,
    match_id                      UUID,
    status                        TEXT,
    is_completed                  BOOLEAN,
    is_confirmed                  BOOLEAN,
    is_finalised                  BOOLEAN,
    competitor_one_score          INTEGER,
    competitor_two_score          INTEGER,
    winner_competitor_number      INTEGER,
    winner_id                     UUID,
    competitor_one_match_points   INTEGER,
    competitor_two_match_points   INTEGER,
    competitor_one_sides_won      INTEGER,
    competitor_two_sides_won      INTEGER,
    competitor_one_side_points    INTEGER,
    competitor_two_side_points    INTEGER,
    competitor_one_total_points   INTEGER,
    competitor_two_total_points   INTEGER,
    scoring_method                TEXT,
    winning_criteria              TEXT,
    source_event_hash             TEXT,
    source_event_at               TIMESTAMPTZ,
    created_at                    TIMESTAMPTZ DEFAULT NOW(),
    updated_at                    TIMESTAMPTZ DEFAULT NOW()
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_competition_results_match_id ON silver.competition_results(match_id);
CREATE INDEX IF NOT EXISTS idx_competition_results_updated_at ON silver.competition_results(updated_at);

-- Refresh function to upsert from bronze.latest_events (endpoints: 'matches' or 'match')
CREATE OR REPLACE FUNCTION silver.refresh_competition_results()
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
        WHERE le.endpoint IN ('matches', 'match')
          AND le.status_code = 200
          AND (inc->>'type') IN ('result', 'multiFormatResult')
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS result_id,
            CASE WHEN (inc->'includes'->'match'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'match'->>'id')::uuid ELSE NULL END AS match_id,
            inc->'attributes'->>'status' AS status,
            (inc->'attributes'->>'isCompleted')::boolean AS is_completed,
            (inc->'attributes'->>'isConfirmed')::boolean AS is_confirmed,
            (inc->'attributes'->>'isFinalized')::boolean AS is_finalised,
            (inc->'attributes'->>'competitorOneScore')::integer AS competitor_one_score,
            (inc->'attributes'->>'competitorTwoScore')::integer AS competitor_two_score,
            (inc->'attributes'->>'winnerCompetitorNumber')::integer AS winner_competitor_number,
            CASE WHEN (inc->'attributes'->>'winnerId') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'attributes'->>'winnerId')::uuid ELSE NULL END AS winner_id,
            (inc->'attributes'->>'competitorOneMatchPoints')::integer AS competitor_one_match_points,
            (inc->'attributes'->>'competitorTwoMatchPoints')::integer AS competitor_two_match_points,
            (inc->'attributes'->>'competitorOneSidesWon')::integer AS competitor_one_sides_won,
            (inc->'attributes'->>'competitorTwoSidesWon')::integer AS competitor_two_sides_won,
            (inc->'attributes'->>'competitorOneSidePoints')::integer AS competitor_one_side_points,
            (inc->'attributes'->>'competitorTwoSidePoints')::integer AS competitor_two_side_points,
            (inc->'attributes'->>'competitorOneTotalPoints')::integer AS competitor_one_total_points,
            (inc->'attributes'->>'competitorTwoTotalPoints')::integer AS competitor_two_total_points,
            inc->'attributes'->>'scoringMethod' AS scoring_method,
            inc->'attributes'->>'winningCriteria' AS winning_criteria,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
    )
    INSERT INTO silver.competition_results (
        result_id, match_id, status, is_completed, is_confirmed, is_finalised,
        competitor_one_score, competitor_two_score, winner_competitor_number, winner_id,
        competitor_one_match_points, competitor_two_match_points,
        competitor_one_sides_won, competitor_two_sides_won,
        competitor_one_side_points, competitor_two_side_points,
        competitor_one_total_points, competitor_two_total_points,
        scoring_method, winning_criteria,
        source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.result_id, s.match_id, s.status, s.is_completed, s.is_confirmed, s.is_finalised,
        s.competitor_one_score, s.competitor_two_score, s.winner_competitor_number, s.winner_id,
        s.competitor_one_match_points, s.competitor_two_match_points,
        s.competitor_one_sides_won, s.competitor_two_sides_won,
        s.competitor_one_side_points, s.competitor_two_side_points,
        s.competitor_one_total_points, s.competitor_two_total_points,
        s.scoring_method, s.winning_criteria,
        s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    ON CONFLICT (result_id) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- Update changed rows
    WITH parsed AS (
        SELECT
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint IN ('matches', 'match')
          AND le.status_code = 200
          AND (inc->>'type') IN ('result', 'multiFormatResult')
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS result_id,
            CASE WHEN (inc->'includes'->'match'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'match'->>'id')::uuid ELSE NULL END AS match_id,
            inc->'attributes'->>'status' AS status,
            (inc->'attributes'->>'isCompleted')::boolean AS is_completed,
            (inc->'attributes'->>'isConfirmed')::boolean AS is_confirmed,
            (inc->'attributes'->>'isFinalized')::boolean AS is_finalised,
            (inc->'attributes'->>'competitorOneScore')::integer AS competitor_one_score,
            (inc->'attributes'->>'competitorTwoScore')::integer AS competitor_two_score,
            (inc->'attributes'->>'winnerCompetitorNumber')::integer AS winner_competitor_number,
            CASE WHEN (inc->'attributes'->>'winnerId') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'attributes'->>'winnerId')::uuid ELSE NULL END AS winner_id,
            (inc->'attributes'->>'competitorOneMatchPoints')::integer AS competitor_one_match_points,
            (inc->'attributes'->>'competitorTwoMatchPoints')::integer AS competitor_two_match_points,
            (inc->'attributes'->>'competitorOneSidesWon')::integer AS competitor_one_sides_won,
            (inc->'attributes'->>'competitorTwoSidesWon')::integer AS competitor_two_sides_won,
            (inc->'attributes'->>'competitorOneSidePoints')::integer AS competitor_one_side_points,
            (inc->'attributes'->>'competitorTwoSidePoints')::integer AS competitor_two_side_points,
            (inc->'attributes'->>'competitorOneTotalPoints')::integer AS competitor_one_total_points,
            (inc->'attributes'->>'competitorTwoTotalPoints')::integer AS competitor_two_total_points,
            inc->'attributes'->>'scoringMethod' AS scoring_method,
            inc->'attributes'->>'winningCriteria' AS winning_criteria,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
    )
    UPDATE silver.competition_results cr
    SET match_id                     = s.match_id,
        status                       = s.status,
        is_completed                 = s.is_completed,
        is_confirmed                 = s.is_confirmed,
        is_finalised                 = s.is_finalised,
        competitor_one_score         = s.competitor_one_score,
        competitor_two_score         = s.competitor_two_score,
        winner_competitor_number     = s.winner_competitor_number,
        winner_id                    = s.winner_id,
        competitor_one_match_points  = s.competitor_one_match_points,
        competitor_two_match_points  = s.competitor_two_match_points,
        competitor_one_sides_won     = s.competitor_one_sides_won,
        competitor_two_sides_won     = s.competitor_two_sides_won,
        competitor_one_side_points   = s.competitor_one_side_points,
        competitor_two_side_points   = s.competitor_two_side_points,
        competitor_one_total_points  = s.competitor_one_total_points,
        competitor_two_total_points  = s.competitor_two_total_points,
        scoring_method               = s.scoring_method,
        winning_criteria             = s.winning_criteria,
        source_event_hash            = s.source_event_hash,
        source_event_at              = s.source_event_at,
        updated_at                   = NOW()
    FROM shaped s
    WHERE cr.result_id = s.result_id
      AND (cr.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
