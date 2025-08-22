# Architecture Overview

This repository contains a production-oriented pipeline that ingests data from the BowlsLink Results API and stores it in a Supabase/Postgres database. It follows a data-lake style layering model: Bronze → Silver → Gold.

## Layers

- Bronze (data-pipeline/bronze/)
  - HTTP acquisition and orchestration
  - Configuration-driven job generation for endpoints × competitions × rounds/sections
  - Optional persistence of raw JSON payloads in `bronze.raw_events`
  - Cloud Functions Gen2 entrypoint: `data-pipeline/main.py` (wrapper to `bronze/main.py`)

- Silver (data-pipeline/silver/)
  - Placeholder for cleansing, schema enforcement, and normalization
  - Not yet implemented

- Gold (data-pipeline/gold/)
  - Placeholder for business logic and reporting-ready models
  - Not yet implemented

## Key Modules

- `bronze/main.py`
  - Orchestrates a request: loads config, generates jobs, calls APIs, optionally stores results, returns a JSON summary.
- `bronze/config.py` (`ConfigManager`)
  - Loads a catalog (`config/endpoints.json`)
  - Extracts competition IDs from URLs/IDs
  - Renders concrete jobs (expanding rounds/sections; supports auto-discovery via API probing)
- `bronze/api_client.py` (`BowlsLinkAPIClient`)
  - `httpx` client with politeness/throttling
  - JSON parsing and empty-response heuristics
  - Optional auto-discovery of rounds/sections
- `bronze/supabase_client.py` (`SupabaseClient`)
  - Inserts raw events and catalog snapshots via `psycopg2`
  - Utility read/cleanup methods
- `bronze/gcp_utils.py`
  - Lightweight helpers for logging and environment detection in GCP
- `shared/utils.py`
  - Environment loading via `.env`
  - Logging setup
  - Config path resolution and env validation helpers

## Configuration

- `data-pipeline/config/endpoints.json`
  - `competitions.urls` or `competitions.ids`: sources of competition UUIDs
  - `rounds` and `sections`: choose `manual` or `auto` ranges
  - `endpoints`: URL templates, may include `{round}` and/or `{section}` placeholders
- Environment variables
  - `ENDPOINTS_FILE` → usually `config/endpoints.json`
  - `THROTTLE_S` → API politeness delay (seconds)
  - `SUPABASE_DB_URL` or `PG_DSN` → Postgres DSN

## Data Model (Bronze)

Supabase SQL in `db/bronze/supabase_schema.sql`:
- `bronze.raw_events`
  - Captures raw payloads, HTTP status, request URL, competition_id, round/section, content hash
- `bronze.endpoint_catalog`
  - Snapshots of the catalog for reproducibility/auditing
- `bronze.latest_events` (view)
  - Last event per competition × endpoint × round × section

## Runtime Flow (Cloud Function)

1. HTTP request hits Cloud Function `main` (Gen2) defined in `data-pipeline/main.py`.
2. Delegates to `bronze/main.py:main(request)`.
3. Load catalog (`ConfigManager.load_catalog()`), extract competition IDs, generate jobs.
4. Execute jobs via `BowlsLinkAPIClient` with throttling.
5. Optionally write raw events and catalog snapshot to Supabase.
6. Return JSON summary with counts, errors, and optional GCP metadata.

## Design Decisions

- `httpx` for robust HTTP and timeouts; `orjson` for fast JSON.
- Store raw JSON in Bronze to preserve provenance and flexibility.
- Keep GCP-specific code minimal so local dev remains straightforward.
- Use GitHub Actions to deploy both function and Cloud Scheduler in one pipeline.

## Future Extensions

- Silver transforms (cleaning, schema checks, dedupe) and quality reports.
- Gold models (domain-specific aggregates and reporting tables/views).
- More granular tests and typed interfaces.
- Observability (structured logs/sinks, metrics, alerting).
