-- Silver schema and match players transformation

CREATE SCHEMA IF NOT EXISTS silver;

-- Match players table for detailed player tracking with positions
CREATE TABLE IF NOT EXISTS silver.match_players (
    match_player_id        UUID PRIMARY KEY,
    match_id               UUID NOT NULL,
    competitor_id          UUID NOT NULL,
    entrant_id             UUID NOT NULL,
    competition_id         UUID NOT NULL,
    first_name             TEXT NOT NULL,
    last_name              TEXT NOT NULL,
    full_name              TEXT,
    assigned_position      TEXT,
    default_position       TEXT,
    competitor_number      INTEGER,
    source_event_hash      TEXT,
    source_event_at        TIMESTAMPTZ,
    created_at             TIMESTAMPTZ DEFAULT NOW(),
    updated_at             TIMESTAMPTZ DEFAULT NOW()
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_match_players_match_id ON silver.match_players(match_id);
CREATE INDEX IF NOT EXISTS idx_match_players_entrant_id ON silver.match_players(entrant_id);
CREATE INDEX IF NOT EXISTS idx_match_players_competitor_id ON silver.match_players(competitor_id);
CREATE INDEX IF NOT EXISTS idx_match_players_competition_id ON silver.match_players(competition_id);
CREATE INDEX IF NOT EXISTS idx_match_players_updated_at ON silver.match_players(updated_at);

-- Refresh function to upsert from bronze.latest_events (endpoint = 'match')
CREATE OR REPLACE FUNCTION silver.refresh_match_players()
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
        WHERE le.endpoint = 'match'
          AND le.status_code = 200
          AND (inc->>'type') = 'competitorPlayer'
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS match_player_id,
            CASE WHEN (inc->'includes'->'match'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'match'->>'id')::uuid ELSE NULL END AS match_id,
            CASE WHEN (inc->'includes'->'competitor'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competitor'->>'id')::uuid ELSE NULL END AS competitor_id,
            CASE WHEN (inc->'includes'->'entrant'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'entrant'->>'id')::uuid ELSE NULL END AS entrant_id,
            -- Get competition_id from the match's includes
            CASE WHEN (inc->'includes'->'match'->'includes'->'competition'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'match'->'includes'->'competition'->>'id')::uuid ELSE NULL END AS competition_id,
            inc->'attributes'->>'firstName' AS first_name,
            inc->'attributes'->>'lastName' AS last_name,
            inc->'attributes'->>'fullName' AS full_name,
            inc->'attributes'->>'assignedPosition' AS assigned_position,
            inc->'attributes'->>'defaultPosition' AS default_position,
            NULL::integer AS competitor_number,  -- Will be determined by logic or additional data
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
          AND inc->'attributes'->>'firstName' IS NOT NULL
          AND inc->'attributes'->>'lastName' IS NOT NULL
    )
    INSERT INTO silver.match_players (
        match_player_id, match_id, competitor_id, entrant_id, competition_id,
        first_name, last_name, full_name,
        assigned_position, default_position, competitor_number,
        source_event_hash, source_event_at, created_at, updated_at
    )
    SELECT
        s.match_player_id, s.match_id, s.competitor_id, s.entrant_id, s.competition_id,
        s.first_name, s.last_name, s.full_name,
        s.assigned_position, s.default_position, s.competitor_number,
        s.source_event_hash, s.source_event_at, NOW(), NOW()
    FROM shaped s
    ON CONFLICT (match_player_id) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- Update changed rows
    WITH parsed AS (
        SELECT
            le.body_hash AS source_event_hash,
            le.created_at AS source_event_at,
            inc AS inc
        FROM bronze.latest_events le,
             LATERAL jsonb_array_elements(le.payload->'include') inc
        WHERE le.endpoint = 'match'
          AND le.status_code = 200
          AND (inc->>'type') = 'competitorPlayer'
    ), shaped AS (
        SELECT
            (inc->>'id')::uuid AS match_player_id,
            CASE WHEN (inc->'includes'->'match'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'match'->>'id')::uuid ELSE NULL END AS match_id,
            CASE WHEN (inc->'includes'->'competitor'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'competitor'->>'id')::uuid ELSE NULL END AS competitor_id,
            CASE WHEN (inc->'includes'->'entrant'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'entrant'->>'id')::uuid ELSE NULL END AS entrant_id,
            CASE WHEN (inc->'includes'->'match'->'includes'->'competition'->>'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN (inc->'includes'->'match'->'includes'->'competition'->>'id')::uuid ELSE NULL END AS competition_id,
            inc->'attributes'->>'firstName' AS first_name,
            inc->'attributes'->>'lastName' AS last_name,
            inc->'attributes'->>'fullName' AS full_name,
            inc->'attributes'->>'assignedPosition' AS assigned_position,
            inc->'attributes'->>'defaultPosition' AS default_position,
            NULL::integer AS competitor_number,
            source_event_hash,
            source_event_at
        FROM parsed
        WHERE inc->>'id' IS NOT NULL
          AND inc->'attributes'->>'firstName' IS NOT NULL
          AND inc->'attributes'->>'lastName' IS NOT NULL
    )
    UPDATE silver.match_players mp
    SET match_id            = s.match_id,
        competitor_id       = s.competitor_id,
        entrant_id          = s.entrant_id,
        competition_id      = s.competition_id,
        first_name          = s.first_name,
        last_name           = s.last_name,
        full_name           = s.full_name,
        assigned_position   = s.assigned_position,
        default_position    = s.default_position,
        competitor_number   = s.competitor_number,
        source_event_hash   = s.source_event_hash,
        source_event_at     = s.source_event_at,
        updated_at          = NOW()
    FROM shaped s
    WHERE mp.match_player_id = s.match_player_id
      AND (mp.source_event_hash IS DISTINCT FROM s.source_event_hash);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN json_build_object('inserted', v_inserted, 'updated', v_updated);
END;
$$ LANGUAGE plpgsql;
