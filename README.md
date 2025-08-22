# bowls-selector-app
Repository for the Bowls Selector application, with a focus on a production-ready data pipeline that ingests BowlsLink API data and stores it in a Supabase/Postgres database. The pipeline is designed for Google Cloud Functions Gen2 and is scheduled to run daily.

## Repository Structure

```
.
├── .github/workflows/
│   └── cd-main.yml          # CI/CD: deploy Cloud Function + Scheduler, run DB migrations
├── data-pipeline/            # Python ETL (Bronze → Silver → Gold architecture)
│   ├── bronze/               # Ingestion + orchestration entrypoint
│   ├── shared/               # Shared utilities (env, logging)
│   ├── config/               # Endpoints catalog (endpoints.json)
│   ├── tests/                # Lightweight smoke tests
│   ├── main.py               # Cloud Function wrapper (Gen2)
│   └── README.md             # Detailed pipeline docs
├── db/
│   └── bronze/
│       └── supabase_schema.sql  # Tables + indexes + view for raw events
└── README.md                 # (this file)
```

## Quick Start

If you only need the pipeline, see `data-pipeline/README.md` for a deeper dive. Below is the short version:

1) Prereqs: Python 3.11+, Postgres/Supabase connection string

2) Install dependencies (from `data-pipeline/`):
```bash
pip install -r requirements.txt
```

3) Configure environment (in `data-pipeline/.env`):
```
SUPABASE_DB_URL=postgresql://postgres:[PASSWORD]@[HOST]:5432/postgres
ENDPOINTS_FILE=config/endpoints.json
THROTTLE_S=0.3
```

4) Create DB objects in Supabase (run in SQL Editor):
```
-- copy from db/bronze/supabase_schema.sql
```

5) Run locally (from `data-pipeline/`):
```bash
python -m functions_framework --target=main --source=main.py --port=8080
```

## Documentation

- Architecture: `docs/ARCHITECTURE.md`
- Deployment (GitHub Actions → Cloud Functions + Scheduler): `docs/DEPLOYMENT.md`
- Local development guide: `docs/LOCAL_DEV.md`
- Pipeline details and examples: `data-pipeline/README.md`

## Notes and Next Steps

- Silver/Gold layers are scaffolded for future transformations and business logic.
- The GitHub Actions workflow expects certain secrets (see Deployment docs).
- Consider adding a test workflow (pytest) and a formatter/linter in future iterations.
