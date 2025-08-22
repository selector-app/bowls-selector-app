# Deployment (GitHub Actions → GCP)

This repository contains a single GitHub Actions workflow that deploys a Google Cloud Function (Gen2), ensures a Cloud Scheduler job is created/updated, and applies database migrations against Supabase.

Workflow file: `.github/workflows/cd-main.yml`

## Prerequisites

- GCP project with billing enabled
- Service Account with permissions to deploy Cloud Functions Gen2, Cloud Run, Secret Manager, and Cloud Scheduler
- Supabase (or Postgres) connection string

## Required GitHub Secrets

- `GCP_PROJECT_ID` → your GCP project ID
- `GCP_REGION` → e.g., `australia-southeast1`
- `GCP_SA_KEY` → JSON key for a deploy-time Service Account
- `SUPABASE_DB_URI` → full Postgres DSN used for migrations and secret population

## What the Workflow Does

1. Checkout and authenticate to GCP
2. Optionally enable required APIs (idempotent)
3. Install `psql` client
4. Apply SQL files in `db/bronze/*.sql` to Supabase
5. Ensure a Secret Manager secret exists (name defaults to `PG_DSN`) and populate it with `SUPABASE_DB_URI`
6. Deploy Cloud Function (Gen2) with:
   - runtime: Python 3.11
   - source: `data-pipeline/`
   - entrypoint: `main` (wrapper to Bronze)
   - env var: `ENDPOINTS_FILE=config/endpoints.json`
   - secret: `PG_DSN` injected as an env-var at runtime
7. Compute the default runtime Service Account and grant it:
   - Secret Accessor on the secret `PG_DSN`
   - Cloud Run Invoker on the function's service
8. Create/Update a Cloud Scheduler job in the given `GCP_REGION` to call the function on a schedule (default: `30 9 * * *` in `Australia/Melbourne`)

## Customization Points

- Change schedule via `SCHED_CRON` and `SCHED_TZ` env values in the workflow
- Adjust memory/timeout in the `gcloud functions deploy` step
- Rename function (`FUNC_NAME`) or the Scheduler job (`SCHEDULER_JOB`) as needed
- If you already manage APIs and IAM elsewhere, you can remove the optional steps

## Verification

- After deployment, view the function in Cloud Console → Cloud Functions (Gen2)
- Check Cloud Run service logs for runtime output
- Confirm the Scheduler job exists and runs successfully
- Verify Secret Manager's secret has latest version with your DSN
- Query Supabase to confirm `bronze.raw_events` and `bronze.endpoint_catalog` exist

## Rollback

- Re-deploy previous commit via GitHub UI or CLI
- Temporarily pause Scheduler job if needed
- Database schema is idempotent; use migrations carefully for destructive changes
