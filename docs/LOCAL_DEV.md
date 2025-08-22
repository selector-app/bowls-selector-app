# Local Development

This guide helps you run and iterate on the pipeline locally without GCP.

## Prerequisites

- Python 3.11+
- A Postgres/Supabase connection string (optional if you only want to hit APIs)

## Setup

1. Navigate to `data-pipeline/`
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Create `.env` (or export env vars):
   ```env
   SUPABASE_DB_URL=postgresql://postgres:[PASSWORD]@[HOST]:5432/postgres
   ENDPOINTS_FILE=config/endpoints.json
   THROTTLE_S=0.3
   ```

## Run Locally

Use Functions Framework to simulate the Cloud Function HTTP entrypoint:
```bash
python -m functions_framework --target=main --source=bronze/main.py --port=8080
```

Then call it:
```bash
curl -X POST http://localhost:8080/
```

Expected output: JSON with `status`, counts, and optional `errors`.

## Tests and Diagnostics

- Quick smoke test for config and imports:
  ```bash
  python tests/test_config.py
  ```
- Supabase connectivity test (requires DSN):
  ```bash
  python tests/test_supabase.py
  ```
- Print a rendered catalog (sanity check):
  ```bash
  python -c "from bronze.config import ConfigManager; print(ConfigManager().load_catalog())"
  ```

## Editing the Catalog

Edit `config/endpoints.json` to:
- Add/remove competition URLs or IDs
- Switch `rounds`/`sections` between `manual` and `auto`
- Add endpoints (optionally include `{round}` / `{section}` placeholders)

## Troubleshooting

- Import errors → ensure you are in `data-pipeline/` when running Python
- Missing config → check `ENDPOINTS_FILE` path and that `config/endpoints.json` exists
- Rate limiting → increase `THROTTLE_S`
- Database errors → verify DSN and that tables from `db/bronze/supabase_schema.sql` exist

## Recommended Next Steps

- Add/enable linting and formatting in your editor (e.g., Ruff, Black)
- Consider a containerized dev environment for parity with production
- Add unit tests for job rendering and API client behavior
