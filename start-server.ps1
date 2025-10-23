$env:ENDPOINTS_FILE = "c:\DEV\bowls-selector-app\data-pipeline\config\endpoints.json"
uv run python -m functions_framework --target=main --source=data-pipeline/main.py --port=8080
