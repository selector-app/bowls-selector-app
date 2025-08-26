# Silver Schema ER Diagram

All entities are in the `silver` schema. Relationships and cardinalities are inferred from the SQL definitions and refresh logic; some FKs are implicit (not enforced in DDL).

```mermaid
erDiagram
    COMPETITIONS {
        UUID competition_id PK
        TEXT name
        TEXT format
        TEXT timezone
        BIGINT start_date_utc
        BIGINT end_date_utc
        TEXT competition_type
        TEXT competition_status
        TEXT result_type
        TEXT competition_event_name
    }

    COMPETITION_MATCHES {
        UUID match_id PK
        UUID result_id
        UUID competition_id
        UUID competitor_one_id
        UUID competitor_two_id
        INT section
        INT round
        TEXT state
        TEXT timezone
        BIGINT match_day_utc
        BIGINT match_time_utc
    }

    COMPETITION_RESULTS {
        UUID result_id PK
        UUID match_id
        TEXT status
        BOOLEAN is_completed
        BOOLEAN is_confirmed
        BOOLEAN is_finalised
        INT competitor_one_score
        INT competitor_two_score
        INT winner_competitor_number
    }

    COMPETITION_COMPETITORS {
        UUID competitor_id PK
        UUID competition_id PK
        TEXT first_name
        TEXT last_name
        BOOLEAN is_competing
        INTEGER matches_played
    }

    LADDER_ROWS {
        UUID competition_id PK
        INT section_number PK
        TEXT competitor_id PK
        INT position
        INT played
        INT wins
        INT losses
        INT draws
        INT byes
        INT points
        INT score
        INT against_score
        INT score_difference
        DECIMAL score_percentage
    }

    %% Relationships
    COMPETITIONS ||--o{ COMPETITION_MATCHES : contains
    COMPETITIONS ||--o{ COMPETITION_COMPETITORS : has
    COMPETITIONS ||--o{ LADDER_ROWS : has

    %% One match has at most one result (and results belong to one match)
    COMPETITION_MATCHES ||--o| COMPETITION_RESULTS : has_result

    %% A competitor (in a competition) can appear in many matches.
    %% These are conceptual composite FKs: (competitor_id, competition_id) in COMPETITION_COMPETITORS
    %% maps to (competitor_one_id, competition_id) / (competitor_two_id, competition_id) in COMPETITION_MATCHES
    COMPETITION_COMPETITORS ||--o{ COMPETITION_MATCHES : appears_as_competitor_one
    COMPETITION_COMPETITORS ||--o{ COMPETITION_MATCHES : appears_as_competitor_two
```

## Notes and Assumptions

- COMPETITION_MATCHES.competition_id, result_id, competitor_one_id, competitor_two_id are nullable in DDL; cardinalities above reflect intended semantics from refresh logic.
- COMPETITION_RESULTS.match_id and COMPETITION_MATCHES.result_id indicate a conceptual 1:1 relationship, but either side may be null depending on source data timing.
- LADDER_ROWS.competitor_id is TEXT (not UUID) per source payload; it is not directly linked to COMPETITION_COMPETITORS.competitor_id. Use competition_id to group ladder rows within competitions.
- COMPETITIONS table now includes competition_event_name from CompetitionEvent objects in the competition endpoint.
- LADDER_ROWS table has been normalized - competition metadata (name, status, dates, type, format) and player_name removed as they're available via JOIN to COMPETITIONS and COMPETITION_COMPETITORS tables respectively.
- Timestamps are stored as BIGINT UTC epoch values for date/time fields and TIMESTAMPTZ for source event metadata.

## How to Render

- Many Markdown renderers with Mermaid support will render this automatically. If needed, use the Mermaid Live Editor to preview the diagram.
