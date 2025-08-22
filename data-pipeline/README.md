# BowlsLink Data Pipeline

A modular data pipeline for ingesting and processing BowlsLink API data using a data lake architecture.

## Architecture Overview

This pipeline follows a **Bronze → Silver → Gold** data lake pattern:

- **Bronze Layer**: Raw data ingestion from external APIs
- **Silver Layer**: Data cleaning, validation, and transformation
- **Gold Layer**: Business logic, aggregations, and final datasets

## Project Structure

```
data-pipeline/
├── bronze/                 # Bronze layer ETL logic
│   ├── __init__.py
│   ├── api_client.py      # HTTP client for BowlsLink API
│   ├── config.py          # Configuration management
│   ├── gcp_utils.py       # GCP-specific utilities
│   ├── main.py            # Main entrypoint for bronze ETL
│   └── supabase_client.py # Database operations
├── silver/                 # Silver layer ETL
│   ├── __init__.py
│   └── refresh.py         # Calls in-DB silver refresh functions
├── gold/                   # Gold layer ETL (future)
│   └── __init__.py
├── shared/                 # Shared utilities across layers
│   ├── __init__.py
│   └── utils.py           # Common functions
├── config/                 # Configuration files
│   └── endpoints.json     # API endpoint definitions
├── requirements.txt        # Python dependencies
├── test_supabase.py       # Supabase connection test
└── env_setup.md           # Environment setup guide
```

## Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Configure Environment

Create a `.env` file in the `data-pipeline` directory:

```env
SUPABASE_DB_URL=postgresql://postgres:[YOUR-PASSWORD]@[YOUR-HOST]:5432/postgres
ENDPOINTS_FILE=config/endpoints.json
THROTTLE_S=0.3
```

### 3. Set Up Database

Run the SQL schemas in your Supabase SQL editor (or via psql):
```sql
-- Bronze (tables, indexes, cleanup, views)
-- Copy contents from db/bronze/supabase_schema.sql

-- Silver (matches + ladder transformations)
-- Copy contents from db/silver/matches.sql
-- Copy contents from db/silver/ladder.sql
```

### 4. Test Connection

```bash
python test_supabase.py
```

### 5. Run the Pipeline

```bash
python -m functions_framework --target=main --source=main.py --port=8080
```

Then make a request to `http://localhost:8080/`

Response includes Bronze ingest summary and Silver refresh results, e.g.:
```json
{
  "bronze": { "stored": 42, "errors": 0 },
  "silver": {
    "matches": { "inserted": 10, "updated": 2 },
    "ladder":  { "inserted": 80, "updated": 5 }
  }
}
```

## Configuration

### Endpoints Configuration

Edit `config/endpoints.json` to define which APIs to call:

```json
{
  "competitions": {
    "urls": ["https://results.bowlslink.com.au/competition/[UUID]"],
    "ids": []
  },
  "rounds": { "mode": "manual", "start": 1, "end": 1 },
  "sections": { "mode": "auto", "start": 1, "end": 20, "cap": 30 },
  "endpoints": [
    {
      "name": "matches",
      "url": "https://api.bowlslink.com.au/results-api/competition/{competition_id}/matches"
    },
    {
      "name": "ladder", 
      "url": "https://api.bowlslink.com.au/results-api/competition/{competition_id}/ladder?section={section}"
    }
  ]
}
```

### Environment Variables

- `SUPABASE_DB_URL`: PostgreSQL connection string for Supabase
- `ENDPOINTS_FILE`: Path to endpoints configuration (default: `config/endpoints.json`)
- `THROTTLE_S`: Delay between API requests in seconds (default: `0.3`)

## Data Flow

1. **Configuration Loading**: Load endpoints and competition IDs
2. **Job Generation**: Create HTTP requests for each endpoint × competition × round/section
3. **API Execution**: Execute requests with rate limiting
4. **Data Storage**: Store raw responses in Supabase bronze layer
5. **Response**: Return summary with results and errors

## Database Schema

### Bronze Layer Tables

- `bronze.raw_events`: Raw API responses with metadata
- `bronze.endpoint_catalog`: Configuration snapshots
- `bronze.latest_events`: View for latest events per competition/endpoint

### Example Queries

```sql
-- Get all ladder data for a competition
SELECT * FROM bronze.raw_events 
WHERE competition_id = '410f93c1-4c0e-41b1-8403-feae6b1ebc56' 
AND endpoint = 'ladder';

-- Get latest events
SELECT * FROM bronze.latest_events;

-- Count events by endpoint
SELECT endpoint, COUNT(*) as count 
FROM bronze.raw_events 
GROUP BY endpoint;

-- Silver: inspect ladder rows
SELECT *
FROM silver.ladder_rows
WHERE competition_id = '410f93c1-4c0e-41b1-8403-feae6b1ebc56'
ORDER BY section_number, position;
```

## Future Development

### Silver Layer
- Implemented: `silver.matches` + `silver.refresh_matches()`
- Implemented: `silver.ladder_rows` + `silver.refresh_ladder()`
- Next: Data validation and quality checks

### Gold Layer
- Business logic implementation
- Aggregations and summaries
- Final data models
- API endpoints for data access

## Troubleshooting

### Common Issues

1. **Import Errors**: Make sure you're running from the `data-pipeline` directory
2. **Configuration Not Found**: Check that `config/endpoints.json` exists
3. **Database Connection**: Verify your Supabase connection string
4. **API Rate Limiting**: Increase `THROTTLE_S` if getting rate limited

### Testing

```bash
# Test configuration and imports
python test_config.py

# Test Supabase connection
python test_supabase.py

# Test configuration loading
python -c "from bronze.config import ConfigManager; print(ConfigManager().load_catalog())"

# Test API client
python -c "from bronze.api_client import BowlsLinkAPIClient; print('API client ready')"
```

## Contributing

When adding new features:

1. Follow the modular structure
2. Add appropriate documentation
3. Update configuration as needed
4. Test thoroughly before committing
