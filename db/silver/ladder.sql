-- Silver schema and ladder transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Structured ladder rows table
CREATE TABLE IF NOT EXISTS silver.ladder_rows (
    competition_id       UUID      NOT NULL,
    section_number       INTEGER   NOT NULL,
    team_id              UUID,
    team_name            TEXT,
    team_key             TEXT      NOT NULL, -- COALESCE(team_id::text, lower(team_name))
    position             INTEGER,
    played               INTEGER,
    won                  INTEGER,
    lost                 INTEGER,
    drawn                INTEGER,
    points               INTEGER,
    shots_for            INTEGER,
    shots_against        INTEGER,
    shot_diff            INTEGER,
    row_json             JSONB     NOT NULL,
    source_event_hash    TEXT,
    source_event_at      TIMESTAMPTZ,
    created_at           TIMESTAMPTZ DEFAULT NOW(),
    updated_at           TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (competition_id, section_number, team_key)
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
            le.competition_id,
            COALESCE(le.section_number, -1) AS section_number,
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            lr AS lr
        FROM bronze.latest_events le,
             LATERAL (le.payload->'data'->'ladderRows') AS lrows,
             LATERAL jsonb_array_elements(lrows) AS lr
        WHERE le.endpoint = 'ladder'
          AND le.status_code = 200
          AND le.payload ? 'data'
          AND (le.payload->'data') ? 'ladderRows'
    ), shaped AS (
        SELECT
            NULLIF(COALESCE(lr->'team'->>'id', lr->>'teamId'), '')::uuid AS team_id,
            COALESCE(lr->'team'->>'name', lr->>'teamName')               AS team_name,
            LOWER(COALESCE(COALESCE(lr->'team'->>'id', lr->>'teamId'), COALESCE(lr->'team'->>'name', lr->>'teamName'))) AS team_key,
            COALESCE((lr->>'position')::int, (lr->>'rank')::int)         AS position,
            COALESCE((lr->>'played')::int, (lr->>'gamesPlayed')::int)    AS played,
            (lr->>'won')::int                                           AS won,
            (lr->>'lost')::int                                          AS lost,
            COALESCE((lr->>'drawn')::int, (lr->>'ties')::int)            AS drawn,
            COALESCE((lr->>'points')::int, (lr->>'matchPoints')::int, (lr->>'premiershipPoints')::int) AS points,
            COALESCE((lr->>'shotsFor')::int, (lr->>'for')::int)          AS shots_for,
            COALESCE((lr->>'shotsAgainst')::int, (lr->>'against')::int)  AS shots_against,
            COALESCE((lr->>'netShots')::int, (lr->>'shotDiff')::int)     AS shot_diff,
            lr                                                           AS row_json,
            competition_id,
            section_number,
            source_event_hash,
            source_event_at
        FROM parsed
    )
    INSERT INTO silver.ladder_rows (
        competition_id, section_number, team_id, team_name, team_key,
        position, played, won, lost, drawn, points, shots_for, shots_against, shot_diff,
        row_json, source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.competition_id, s.section_number, s.team_id, s.team_name, s.team_key,
        s.position, s.played, s.won, s.lost, s.drawn, s.points, s.shots_for, s.shots_against, s.shot_diff,
        s.row_json, s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    ON CONFLICT (competition_id, section_number, team_key) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- Update changed rows
    WITH parsed AS (
        SELECT
            le.competition_id,
            COALESCE(le.section_number, -1) AS section_number,
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            lr AS lr
        FROM bronze.latest_events le,
             LATERAL (le.payload->'data'->'ladderRows') AS lrows,
             LATERAL jsonb_array_elements(lrows) AS lr
        WHERE le.endpoint = 'ladder'
          AND le.status_code = 200
          AND le.payload ? 'data'
          AND (le.payload->'data') ? 'ladderRows'
    ), shaped AS (
        SELECT
            NULLIF(COALESCE(lr->'team'->>'id', lr->>'teamId'), '')::uuid AS team_id,
            COALESCE(lr->'team'->>'name', lr->>'teamName')               AS team_name,
            LOWER(COALESCE(COALESCE(lr->'team'->>'id', lr->>'teamId'), COALESCE(lr->'team'->>'name', lr->>'teamName'))) AS team_key,
            COALESCE((lr->>'position')::int, (lr->>'rank')::int)         AS position,
            COALESCE((lr->>'played')::int, (lr->>'gamesPlayed')::int)    AS played,
            (lr->>'won')::int                                           AS won,
            (lr->>'lost')::int                                          AS lost,
            COALESCE((lr->>'drawn')::int, (lr->>'ties')::int)            AS drawn,
            COALESCE((lr->>'points')::int, (lr->>'matchPoints')::int, (lr->>'premiershipPoints')::int) AS points,
            COALESCE((lr->>'shotsFor')::int, (lr->>'for')::int)          AS shots_for,
            COALESCE((lr->>'shotsAgainst')::int, (lr->>'against')::int)  AS shots_against,
            COALESCE((lr->>'netShots')::int, (lr->>'shotDiff')::int)     AS shot_diff,
            lr                                                           AS row_json,
            competition_id,
            section_number,
            source_event_hash,
            source_event_at
        FROM parsed
    )
    UPDATE silver.ladder_rows t
    SET team_id           = s.team_id,
        team_name         = s.team_name,
        position          = s.position,
        played            = s.played,
        won               = s.won,
        lost              = s.lost,
        drawn             = s.drawn,
        points            = s.points,
        shots_for         = s.shots_for,
        shots_against     = s.shots_against,
        shot_diff         = s.shot_diff,
        row_json          = s.row_json,
        source_event_hash = s.source_event_hash,
        source_event_at   = s.source_event_at,
        updated_at        = NOW()
    FROM shaped s
    WHERE t.competition_id = s.competition_id
      AND t.section_number = s.section_number
      AND t.team_key       = s.team_key
      AND (t.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
