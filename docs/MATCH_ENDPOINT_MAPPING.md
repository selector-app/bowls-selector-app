# Match Endpoint Field Mapping

This document defines how to map data from the `match` endpoint (individual match detail) to the silver layer tables.

## Data Source

**Endpoint**: `/match/{match_id}`  
**Bronze table**: `bronze.raw_events` where `endpoint = 'match'`

## JSON Structure Overview

```json
{
  "data": {
    "match": [{"id": "...", "type": "match"}]
  },
  "include": [
    // Array of various object types:
    // - match (1)
    // - competitor (2) 
    // - multiFormatResult (1)
    // - rinkMatch (4)
    // - rinkMatchResult (4)
    // - competitorPlayer (32)
    // - entrant (118)
    // - competition (1)
    // - owner (3)
    // - CompetitorFieldOfPlay (1)
  ]
}
```

---

## 1. competition_matches Table Mapping

### Source Object
**Type**: `match` (from `include` array)  
**Filter**: `WHERE (inc->>'type') = 'match'`

### Field Mappings

| Silver Column | JSON Path | Data Type | Notes |
|--------------|-----------|-----------|-------|
| `match_id` | `inc->>'id'` | UUID | Primary key |
| `result_id` | `inc->'includes'->'result'->>'id'` | UUID | References multiFormatResult |
| `competition_id` | `inc->'includes'->'competition'->>'id'` | UUID | |
| `competitor_one_id` | `inc->'includes'->'competitorOne'->>'id'` | UUID | |
| `competitor_two_id` | `inc->'includes'->'competitorTwo'->>'id'` | UUID | |
| `section` | `inc->'attributes'->>'pool'` | INTEGER | Pool number |
| `round` | `inc->'attributes'->>'round'` | INTEGER | |
| `state` | `inc->'attributes'->>'state'` | TEXT | e.g., "PLAYED" |
| `timezone` | `inc->'attributes'->>'timezone'` | TEXT | e.g., "Australia/Melbourne" |
| `match_day_utc` | `inc->'attributes'->>'matchDayUtc'` | BIGINT | Unix timestamp |
| `match_time_utc` | `inc->'attributes'->>'matchTimeUtc'` | BIGINT | Unix timestamp |

### Additional Available Fields (not currently in schema)
- `inc->'attributes'->>'matchState'` - duplicate of state
- `inc->'attributes'->>'roundLabel'` - e.g., "Round 14"
- `inc->'attributes'->>'sectionLabel'` - e.g., "Section 6"
- `inc->'attributes'->>'isBye'` - boolean
- `inc->'attributes'->>'isFinalsSeries'` - boolean

### SQL Changes Required
```sql
-- Add to WHERE clause in both INSERT and UPDATE CTEs:
WHERE le.endpoint IN ('matches', 'match')  -- was: le.endpoint = 'matches'
  AND le.status_code = 200
  AND (inc->>'type') = 'match'
```

---

## 2. competition_results Table Mapping

### Source Object
**Type**: `multiFormatResult` (from `include` array)  
**Filter**: `WHERE (inc->>'type') IN ('result', 'multiFormatResult')`

### Field Mappings

| Silver Column | JSON Path | Data Type | Notes |
|--------------|-----------|-----------|-------|
| `result_id` | `inc->>'id'` | UUID | Primary key |
| `match_id` | `inc->'includes'->'match'->>'id'` | UUID | Foreign key |
| `status` | `inc->'attributes'->>'status'` | TEXT | e.g., "success" |
| `is_completed` | `inc->'attributes'->>'isCompleted'` | BOOLEAN | |
| `is_confirmed` | `inc->'attributes'->>'isConfirmed'` | BOOLEAN | |
| `is_finalised` | `inc->'attributes'->>'isFinalized'` | BOOLEAN | Note: "isFinalized" not "isFinalised" |
| `competitor_one_score` | `inc->'attributes'->>'competitorOneScore'` | INTEGER | Total shots |
| `competitor_two_score` | `inc->'attributes'->>'competitorTwoScore'` | INTEGER | Total shots |
| `winner_competitor_number` | `inc->'attributes'->>'winnerCompetitorNumber'` | INTEGER | 1 or 2 |

### Additional Available Fields (multiFormatResult specific)
- `inc->'attributes'->>'competitorOneMatchPoints'` - INTEGER
- `inc->'attributes'->>'competitorTwoMatchPoints'` - INTEGER
- `inc->'attributes'->>'competitorOneSidesWon'` - INTEGER (rinks won)
- `inc->'attributes'->>'competitorTwoSidesWon'` - INTEGER (rinks won)
- `inc->'attributes'->>'competitorOneSidePoints'` - INTEGER
- `inc->'attributes'->>'competitorTwoSidePoints'` - INTEGER
- `inc->'attributes'->>'competitorOneTotalPoints'` - INTEGER
- `inc->'attributes'->>'competitorTwoTotalPoints'` - INTEGER
- `inc->'attributes'->>'scoringMethod'` - TEXT (e.g., "shots")
- `inc->'attributes'->>'winningCriteria'` - TEXT (e.g., "Shots")
- `inc->'attributes'->>'winnerId'` - UUID

### SQL Changes Required
```sql
-- Update WHERE clause to handle both result types:
WHERE le.endpoint IN ('matches', 'match')  -- was: le.endpoint = 'matches'
  AND le.status_code = 200
  AND (inc->>'type') IN ('result', 'multiFormatResult')  -- was: (inc->>'type') = 'result'
```

---

## 3. competition_competitors Table Mapping

### Current Source (ladder endpoint)
**Type**: `entrant` from `ladder` endpoint  
**Has**: firstName, lastName, isCompeting, competitor reference

### New Source (match endpoint)
**Type**: `competitorPlayer` from `match` endpoint  
**Has**: firstName, lastName, assignedPosition, entrant reference

### Recommended Approach: Add Position Field

#### Option A: Extract from competitorPlayer (RECOMMENDED)
This gives us position data per match.

**Source Object**: `competitorPlayer` (from `include` array)  
**Filter**: `WHERE (inc->>'type') = 'competitorPlayer'`

| Silver Column | JSON Path | Data Type | Notes |
|--------------|-----------|-----------|-------|
| `competitor_id` | `inc->'includes'->'entrant'->'includes'->'competitor'->>'id'` | UUID | Via entrant |
| `competition_id` | `inc->'includes'->'match'->'includes'->'competition'->>'id'` | UUID | Via match |
| `first_name` | `inc->'attributes'->>'firstName'` | TEXT | Direct on competitorPlayer |
| `last_name` | `inc->'attributes'->>'lastName'` | TEXT | Direct on competitorPlayer |
| `is_competing` | `entrant->'attributes'->>'isCompeting'` | BOOLEAN | From linked entrant |
| **`assigned_position`** | `inc->'attributes'->>'assignedPosition'` | TEXT | **NEW FIELD** |
| `match_id` | `inc->'includes'->'match'->>'id'` | UUID | **NEW FIELD** (for tracking) |

**Position Values Found**:
- `lead`
- `second`
- `third`
- `skip`

#### Schema Changes Required
```sql
-- Add new columns to competition_competitors table:
ALTER TABLE silver.competition_competitors 
  ADD COLUMN IF NOT EXISTS assigned_position TEXT,
  ADD COLUMN IF NOT EXISTS match_id UUID;

-- Update primary key to include match_id (for per-match positions):
-- Option 1: Keep current PK (competitor_id, competition_id) - shows general participation
-- Option 2: Change to (competitor_id, competition_id, match_id) - tracks position per match
```

#### Option B: Continue using entrant from ladder endpoint
Keep current approach, add position from competitorPlayer separately.

---

## 4. New Table Recommendation: match_players

For detailed match-level player tracking with positions, consider a new table:

```sql
CREATE TABLE IF NOT EXISTS silver.match_players (
    match_player_id        UUID PRIMARY KEY,
    match_id               UUID NOT NULL,
    competitor_id          UUID NOT NULL,
    entrant_id             UUID NOT NULL,
    competition_id         UUID NOT NULL,
    rink_match_id          UUID,
    first_name             TEXT NOT NULL,
    last_name              TEXT NOT NULL,
    full_name              TEXT,
    assigned_position      TEXT,
    default_position       TEXT,
    competitor_number      INTEGER,  -- 1 or 2
    rink_number            INTEGER,  -- 1-4 for this match
    source_event_hash      TEXT,
    source_event_at        TIMESTAMPTZ,
    created_at             TIMESTAMPTZ DEFAULT NOW(),
    updated_at             TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_match_players_match_id ON silver.match_players(match_id);
CREATE INDEX IF NOT EXISTS idx_match_players_entrant_id ON silver.match_players(entrant_id);
CREATE INDEX IF NOT EXISTS idx_match_players_competitor_id ON silver.match_players(competitor_id);
```

This table would be populated from `competitorPlayer` objects in the `match` endpoint data.

---

## 5. Implementation Priority

### Phase 1: Extend Existing Tables (Minimal Changes)
1. ✅ **competition_matches**: Add `'match'` endpoint support
2. ✅ **competition_results**: Add `'multiFormatResult'` type support
3. ✅ **competition_competitors**: Add `assigned_position` column

### Phase 2: New Detailed Tables (Optional)
4. ⏳ **match_players**: New table for detailed match-level player tracking
5. ⏳ **rink_matches**: New table for individual rink match results
6. ⏳ **rink_match_players**: Link table for rink-level player positions

---

## Summary of Changes

### Minimal Implementation (Phase 1)
- **3 SQL files** to update
- **1 new column** (assigned_position)
- **Backward compatible** with existing data
- Handles both `matches` (bulk) and `match` (individual) endpoints

### Full Implementation (Phase 2)
- **3 new tables** for granular match data
- Complete player position tracking per match
- Rink-level results and player assignments
- Foundation for advanced analytics

**Recommendation**: Start with Phase 1 to get position data flowing, then evaluate if Phase 2 is needed based on reporting requirements.
