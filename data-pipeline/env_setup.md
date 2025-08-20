# Environment Setup for Supabase

## 1. Get Your Supabase Connection String

1. Go to your Supabase project dashboard
2. Navigate to **Settings → Database**
3. Copy the "Connection string" (looks like: `postgresql://postgres:[password]@[host]:5432/postgres`)

## 2. Set Environment Variable

### Windows PowerShell:
```powershell
$env:SUPABASE_DB_URL="postgresql://postgres:[YOUR-PASSWORD]@[YOUR-HOST]:5432/postgres"
```

### Windows Command Prompt:
```cmd
set SUPABASE_DB_URL=postgresql://postgres:[YOUR-PASSWORD]@[YOUR-HOST]:5432/postgres
```

### Linux/Mac:
```bash
export SUPABASE_DB_URL="postgresql://postgres:[YOUR-PASSWORD]@[YOUR-HOST]:5432/postgres"
```

## 3. Alternative: Create .env file

Create a `.env` file in the data-pipeline directory:
```
SUPABASE_DB_URL=postgresql://postgres:[YOUR-PASSWORD]@[YOUR-HOST]:5432/postgres
ENDPOINTS_FILE=endpoints.json
THROTTLE_S=0.3
```

Then load it with python-dotenv (add to requirements.txt):
```
python-dotenv==1.0.0
```

## 4. Test Connection

Run this to test if Supabase is configured:
```python
from supabase_client import SupabaseConfig
print("Supabase available:", SupabaseConfig.is_available())
```
