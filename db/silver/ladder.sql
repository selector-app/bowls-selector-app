-- Silver schema and ladder transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Structured ladder rows table
CREATE TABLE IF NOT EXISTS silver.ladder_rows (
    competition_id       UUID      NOT NULL,
    section_number       INTEGER   NOT NULL,
    competitor_id        TEXT      NOT NULL,
    player_name          TEXT      NOT NULL,
    position             INTEGER   NOT NULL,
    played               INTEGER   NOT NULL,
    wins                 INTEGER   NOT NULL,
    losses               INTEGER   NOT NULL,
    draws                INTEGER   NOT NULL,
    byes                 INTEGER   NOT NULL,
    points               INTEGER   NOT NULL,
    score                INTEGER   NOT NULL,
    against_score        INTEGER   NOT NULL,
    score_difference     INTEGER   NOT NULL,
    score_percentage     DECIMAL(6,2) NOT NULL,
    competition_name     TEXT,
    competition_status   TEXT,
    start_date_utc       BIGINT,
    end_date_utc         BIGINT,
    competition_type     TEXT,
    competition_type_label TEXT,
    format               TEXT,
    row_json             JSONB     NOT NULL,
    source_event_hash    TEXT,
    source_event_at      TIMESTAMPTZ,
    created_at           TIMESTAMPTZ DEFAULT NOW(),
    updated_at           TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (competition_id, section_number, competitor_id)
);

CREATE INDEX IF NOT EXISTS idx_ladder_competition_section
  ON silver.ladder_rows(competition_id, section_number);

CREATE OR REPLACE FUNCTION silver.refresh_ladder()
RETURNS JSON AS $$
DECLARE
    v_inserted INTEGER := 0;
    v_updated  INTEGER := 0;
BEGIN
    -- Insert new rows
    WITH parsed AS (
        SELECT
            le.competition_id::uuid AS competition_id,
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            lr AS lr,
            comp.c AS comp
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') AS lr,
             LATERAL (
                 SELECT c 
                 FROM jsonb_array_elements(le.payload->'include') AS c 
                 WHERE c->>'type' = 'competition' 
                 LIMIT 1
             ) AS comp(c)
        WHERE le.endpoint = 'ladder'
          AND le.status_code = 200
          AND le.payload ? 'include'
          AND lr->>'type' = 'ladderRow'
    ), shaped AS (
        SELECT
            competition_id,
            (lr->'attributes'->>'pool')::int AS section_number,
            lr->'attributes'->>'competitorId' AS competitor_id,
            lr->'attributes'->'fields'->>'name' AS player_name,
            (lr->'attributes'->'fields'->>'position')::int AS position,
            (lr->'attributes'->'fields'->>'played')::int AS played,
            (lr->'attributes'->'fields'->>'wins')::int AS wins,
            (lr->'attributes'->'fields'->>'losses')::int AS losses,
            (lr->'attributes'->'fields'->>'draws')::int AS draws,
            (lr->'attributes'->'fields'->>'byes')::int AS byes,
            (lr->'attributes'->'fields'->>'points')::int AS points,
            (lr->'attributes'->'fields'->>'score')::int AS score,
            (lr->'attributes'->'fields'->>'againstScore')::int AS against_score,
            (lr->'attributes'->'fields'->>'scoreDifference')::int AS score_difference,
            (lr->'attributes'->'fields'->>'scorePercentage')::decimal AS score_percentage,
            comp->'attributes'->>'name' AS competition_name,
            comp->'attributes'->>'competitionStatus' AS competition_status,
            (comp->'attributes'->>'startDateUtc')::bigint AS start_date_utc,
            (comp->'attributes'->>'endDateUtc')::bigint AS end_date_utc,
            comp->'attributes'->>'competitionType' AS competition_type,
            comp->'attributes'->>'competitionTypeLabel' AS competition_type_label,
            comp->'attributes'->>'format' AS format,
            lr AS row_json,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE lr->'attributes'->>'competitorId' IS NOT NULL
          AND lr->'attributes'->'fields'->>'name' IS NOT NULL
          AND lr->'attributes'->'fields'->>'position' IS NOT NULL
    )
    INSERT INTO silver.ladder_rows (
        competition_id, section_number, competitor_id, player_name,
        position, played, wins, losses, draws, byes, points, 
        score, against_score, score_difference, score_percentage,
        competition_name, competition_status, start_date_utc, end_date_utc,
        competition_type, competition_type_label, format,
        row_json, source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.competition_id, s.section_number, s.competitor_id, s.player_name,
        s.position, s.played, s.wins, s.losses, s.draws, s.byes, s.points,
        s.score, s.against_score, s.score_difference, s.score_percentage,
        s.competition_name, s.competition_status, s.start_date_utc, s.end_date_utc,
        s.competition_type, s.competition_type_label, s.format,
        s.row_json, s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    ON CONFLICT (competition_id, section_number, competitor_id) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- Update changed rows
    WITH parsed AS (
        SELECT
            le.competition_id::uuid AS competition_id,
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            lr AS lr,
            comp.c AS comp
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') AS lr,
             LATERAL (
                 SELECT c 
                 FROM jsonb_array_elements(le.payload->'include') AS c 
                 WHERE c->>'type' = 'competition' 
                 LIMIT 1
             ) AS comp(c)
        WHERE le.endpoint = 'ladder'
          AND le.status_code = 200
          AND le.payload ? 'include'
          AND lr->>'type' = 'ladderRow'
    ), shaped AS (
        SELECT
            competition_id,
            (lr->'attributes'->>'pool')::int AS section_number,
            lr->'attributes'->>'competitorId' AS competitor_id,
            lr->'attributes'->'fields'->>'name' AS player_name,
            (lr->'attributes'->'fields'->>'position')::int AS position,
            (lr->'attributes'->'fields'->>'played')::int AS played,
            (lr->'attributes'->'fields'->>'wins')::int AS wins,
            (lr->'attributes'->'fields'->>'losses')::int AS losses,
            (lr->'attributes'->'fields'->>'draws')::int AS draws,
            (lr->'attributes'->'fields'->>'byes')::int AS byes,
            (lr->'attributes'->'fields'->>'points')::int AS points,
            (lr->'attributes'->'fields'->>'score')::int AS score,
            (lr->'attributes'->'fields'->>'againstScore')::int AS against_score,
            (lr->'attributes'->'fields'->>'scoreDifference')::int AS score_difference,
            (lr->'attributes'->'fields'->>'scorePercentage')::decimal AS score_percentage,
            comp->'attributes'->>'name' AS competition_name,
            comp->'attributes'->>'competitionStatus' AS competition_status,
            (comp->'attributes'->>'startDateUtc')::bigint AS start_date_utc,
            (comp->'attributes'->>'endDateUtc')::bigint AS end_date_utc,
            comp->'attributes'->>'competitionType' AS competition_type,
            comp->'attributes'->>'competitionTypeLabel' AS competition_type_label,
            comp->'attributes'->>'format' AS format,
            lr AS row_json,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE lr->'attributes'->>'competitorId' IS NOT NULL
          AND lr->'attributes'->'fields'->>'name' IS NOT NULL
          AND lr->'attributes'->'fields'->>'position' IS NOT NULL
    )
    UPDATE silver.ladder_rows t
    SET player_name       = s.player_name,
        position          = s.position,
        played            = s.played,
        wins              = s.wins,
        losses            = s.losses,
        draws             = s.draws,
        byes              = s.byes,
        points            = s.points,
        score             = s.score,
        against_score     = s.against_score,
        score_difference  = s.score_difference,
        score_percentage  = s.score_percentage,
        competition_name  = s.competition_name,
        competition_status = s.competition_status,
        start_date_utc    = s.start_date_utc,
        end_date_utc      = s.end_date_utc,
        competition_type  = s.competition_type,
        competition_type_label = s.competition_type_label,
        format            = s.format,
        row_json          = s.row_json,
        source_event_hash = s.source_event_hash,
        source_event_at   = s.source_event_at,
        updated_at        = NOW()
    FROM shaped s
    WHERE t.competition_id = s.competition_id
      AND t.section_number = s.section_number
      AND t.competitor_id = s.competitor_id
      AND (t.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
