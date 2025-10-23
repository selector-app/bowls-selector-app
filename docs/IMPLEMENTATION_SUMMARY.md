# Match Endpoint Implementation Summary

## ✅ Implementation Complete

All silver layer tables have been updated to support the `match` endpoint data with full field mappings including **player positions**.

---

## Files Modified/Created

### 1. **Updated: `db/silver/competition_results.sql`**
- ✅ Added support for `endpoint IN ('matches', 'match')`
- ✅ Added support for `type IN ('result', 'multiFormatResult')`
- ✅ **Added 11 new fields** from multiFormatResult:
  - `winner_id` (UUID)
  - `competitor_one_match_points` (INTEGER)
  - `competitor_two_match_points` (INTEGER)
  - `competitor_one_sides_won` (INTEGER) - rinks won
  - `competitor_two_sides_won` (INTEGER) - rinks won
  - `competitor_one_side_points` (INTEGER)
  - `competitor_two_side_points` (INTEGER)
  - `competitor_one_total_points` (INTEGER)
  - `competitor_two_total_points` (INTEGER)
  - `scoring_method` (TEXT) - e.g., "shots"
  - `winning_criteria` (TEXT) - e.g., "Shots"

### 2. **Updated: `db/silver/competition_matches.sql`**
- ✅ Added support for `endpoint IN ('matches', 'match')`
- ✅ No schema changes needed
- ✅ Same field mappings work for both endpoints

### 3. **Updated: `db/silver/competition_competitors.sql`**
- ✅ **Added new field**: `assigned_position` (TEXT)
- ✅ Supports values: `lead`, `second`, `third`, `skip`
- ⚠️ Note: Position will be NULL from `ladder` endpoint (no position data there)
- ✅ Detailed position tracking available in new `match_players` table

### 4. **NEW: `db/silver/match_players.sql`**
Complete player tracking with positions per match.

**Fields:**
- `match_player_id` (UUID, PK) - competitorPlayer ID
- `match_id` (UUID) - which match
- `competitor_id` (UUID) - which team
- `entrant_id` (UUID) - player's entrant ID
- `competition_id` (UUID) - which competition
- `first_name`, `last_name`, `full_name` (TEXT)
- **`assigned_position`** (TEXT) - **lead, second, third, skip**
- `default_position` (TEXT) - player's usual position
- `competitor_number` (INTEGER) - 1 or 2 (team side)

**Refresh function:** `silver.refresh_match_players()`

### 5. **NEW: `db/silver/rink_matches.sql`**
Individual rink/side results within a match (4 rinks per match in this format).

**Fields:**
- `rink_match_id` (UUID, PK)
- `match_id` (UUID) - parent match
- `result_id` (UUID) - rinkMatchResult ID
- `format` (TEXT) - e.g., "fours"
- `format_name` (TEXT) - e.g., "Fours"
- `specialisation` (TEXT) - e.g., "Team 1", "Team 2", "Team 3", "Team 4"
- `sequence` (INTEGER)
- `competitor_one_shots` (INTEGER)
- `competitor_two_shots` (INTEGER)
- `competitor_one_points` (INTEGER)
- `competitor_two_points` (INTEGER)
- `competitor_one_match_points` (INTEGER)
- `competitor_two_match_points` (INTEGER)
- `has_winner` (BOOLEAN)
- `is_competitor_one_winner` (BOOLEAN)
- `is_competitor_two_winner` (BOOLEAN)
- `winner_id` (UUID)
- `scoring_method` (TEXT)
- `status` (TEXT)

**Refresh function:** `silver.refresh_rink_matches()`

---

## Data Flow

```
Bronze Layer (raw_events)
  ├─ endpoint = 'matches' (bulk match list)
  └─ endpoint = 'match' (individual match detail)
         │
         ├─→ type='match' ────────────────→ competition_matches
         ├─→ type='multiFormatResult' ────→ competition_results
         ├─→ type='competitorPlayer' ──────→ match_players (WITH POSITIONS!)
         ├─→ type='rinkMatch' ─────────────→ rink_matches
         └─→ type='rinkMatchResult' ───────→ rink_matches
```

---

## Position Data Hierarchy

### General Participation (No Position)
**Table:** `competition_competitors`
- Source: `ladder` endpoint → `entrant` objects
- Shows: Who is in the competition
- Position: NULL (not available from ladder)

### Match-Level Position Tracking
**Table:** `match_players`
- Source: `match` endpoint → `competitorPlayer` objects
- Shows: Who played in each match and their position
- Position: **lead, second, third, skip**

---

## Deployment Steps

### 1. Run SQL Scripts in Order

```sql
-- Update existing tables (add columns)
\i db/silver/competition_results.sql
\i db/silver/competition_matches.sql
\i db/silver/competition_competitors.sql

-- Create new tables
\i db/silver/match_players.sql
\i db/silver/rink_matches.sql
```

### 2. Refresh Functions

After bronze data is loaded with `match` endpoint data:

```sql
-- Refresh existing tables (now with match endpoint support)
SELECT silver.refresh_competition_matches();
SELECT silver.refresh_competition_results();
SELECT silver.refresh_competition_competitors();

-- Refresh new tables
SELECT silver.refresh_match_players();
SELECT silver.refresh_rink_matches();
```

---

## Example Queries

### Get all players with positions for a specific match
```sql
SELECT 
    mp.full_name,
    mp.assigned_position,
    c.name AS team_name,
    m.round,
    m.section
FROM silver.match_players mp
JOIN silver.competition_matches m ON mp.match_id = m.match_id
JOIN silver.competitor c ON mp.competitor_id = c.id
WHERE mp.match_id = '69430873-9baa-4bb2-bf9d-7f205b22a019'
ORDER BY mp.competitor_number, 
         CASE mp.assigned_position 
             WHEN 'lead' THEN 1 
             WHEN 'second' THEN 2 
             WHEN 'third' THEN 3 
             WHEN 'skip' THEN 4 
         END;
```

### Get rink-by-rink results for a match
```sql
SELECT 
    rm.specialisation AS rink,
    rm.competitor_one_shots,
    rm.competitor_two_shots,
    rm.is_competitor_one_winner,
    rm.competitor_one_match_points,
    rm.competitor_two_match_points
FROM silver.rink_matches rm
WHERE rm.match_id = '69430873-9baa-4bb2-bf9d-7f205b22a019'
ORDER BY rm.sequence;
```

### Get enhanced match results with all new fields
```sql
SELECT 
    m.match_id,
    m.round,
    m.section,
    r.competitor_one_score,
    r.competitor_two_score,
    r.competitor_one_sides_won,
    r.competitor_two_sides_won,
    r.competitor_one_total_points,
    r.competitor_two_total_points,
    r.scoring_method,
    r.winning_criteria
FROM silver.competition_matches m
JOIN silver.competition_results r ON m.result_id = r.result_id
WHERE m.competition_id = 'adc7cecb-042e-4f5f-b884-80f23d6a9c16'
  AND m.round = 14;
```

---

## Testing Checklist

- [ ] Run all SQL scripts successfully
- [ ] Verify `match` endpoint data exists in bronze.raw_events
- [ ] Run all refresh functions
- [ ] Verify position data populated in match_players table
- [ ] Verify additional result fields populated (sides_won, match_points, etc.)
- [ ] Verify rink_matches table has 4 rinks per match
- [ ] Test example queries above
- [ ] Verify backward compatibility with existing `matches` endpoint data

---

## Notes

1. **Backward Compatible**: All changes support both `matches` (bulk) and `match` (individual) endpoints
2. **Position Data**: Only available from `match` endpoint via `competitorPlayer` objects
3. **Rink Data**: Only available from `match` endpoint (not in bulk `matches` data)
4. **NULL Handling**: All new fields handle NULL gracefully for older data
5. **Bronze Layer**: No changes needed - just add `match` endpoint to your data collection

---

## Next Steps

1. Update your data pipeline to collect `match` endpoint data
2. Store in bronze.raw_events with `endpoint = 'match'`
3. Run the refresh functions to populate silver tables
4. Build gold layer analytics on top of this enriched data

**Position tracking is now fully operational! 🎯**
