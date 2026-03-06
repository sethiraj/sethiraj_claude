# API Test Runner

Execute API test cases against Swagger/OpenAPI specifications using Playwright as the HTTP engine. Supports bearer token acquisition, file-based parameters, and path/query/body resolution from spec definitions.

## Trigger conditions

Use this skill when the user wants to:
- Test or execute an API endpoint defined in a Swagger or OpenAPI spec
- Run HTTP requests with parameters sourced from local JSON files
- Test APIs requiring bearer token or OAuth2 authentication
- Validate API responses and report pass/fail status

## Input extraction

From the user's prompt, extract:

| Input | Description | Example |
|-------|-------------|---------|
| **Spec file** | Path to `.json`, `.yaml`, or `.yml` OpenAPI spec | `./petstore.json` |
| **HTTP method** | GET, POST, PUT, DELETE, PATCH | `POST` |
| **Endpoint path** | API path as defined in spec | `/users/{id}` |
| **Parameter files** | Any `.json` file paths mentioned — treated as request parameters | `./body.json` |
| **Auth info** | Auth URL, credentials file, or inline credentials | `./creds.json` |

### File path detection (filesystem-as-parameters)

If the user mentions **file paths** in their prompt (e.g., `./body.json`, `test-data/user.json`):
- For **POST/PUT/PATCH**: treat file content as the **request body**
- For **GET/DELETE**: treat file content as **query parameters**

Read the file using the Read tool first to inspect its content, then pass the path via `--params-file`.

## Execution steps

### Step 1: Check prerequisites

Verify Playwright is installed in the plugin directory:

```bash
cd <plugin-root> && node -e "require('playwright')" 2>/dev/null || npm install
```

If `playwright` is missing, run `npm install` in the plugin root before proceeding.

### Step 2: Read and inspect the spec

Use the Read tool to open the OpenAPI spec file. Look for:
- `servers[0].url` (OpenAPI 3.x) or `host` + `basePath` (Swagger 2.x) → base URL
- `components.securitySchemes` or `securityDefinitions` → auth type
- `paths.<endpoint>.<method>.parameters` → expected params and their `in` values (path/query/body)
- `paths.<endpoint>.<method>.security` → whether this endpoint requires auth

### Step 3: Determine authentication

If the spec defines a security scheme AND the endpoint requires auth:
1. Look for `tokenUrl` in oauth2 flows, or ask the user for the auth endpoint
2. Gather credentials (from a file the user mentioned, or ask)
3. The script will automatically make the auth call and inject the token

If the user provides a pre-existing token, pass it with `--token` to skip the auth call.

### Step 4: Build and run the command

Use the `CLAUDE_PLUGIN_ROOT` environment variable or the resolved absolute path to the plugin when running in a non-plugin context:

```bash
node <plugin-root>/scripts/api-runner.js \
  --spec "<spec-file>" \
  --method "<METHOD>" \
  --endpoint "<endpoint-path>" \
  [--params-file "<params.json>"] \
  [--params '{"key":"value"}'] \
  [--auth-url "<token-endpoint>"] \
  [--auth-body-file "<credentials.json>"] \
  [--auth-body '{"username":"...","password":"..."}'] \
  [--base-url "<override-url>"] \
  [--token "<pre-existing-token>"] \
  [--header "X-Api-Key: value"] \
  [--content-type "application/json"]
```

### Step 5: Interpret and report results

| Status | Outcome | Action |
|--------|---------|--------|
| 2xx | ✅ PASS | Show response body and duration |
| 4xx | ❌ FAIL | Show error details, check params and auth |
| 5xx | ❌ FAIL | Show server error, check API availability |
| Error | ❌ ERROR | Show message, check spec path and connectivity |

Always display: status code, response body (formatted JSON or text), execution duration.

## Example prompts and commands

### Basic GET request
> "Test GET /pets from petstore.json"
```bash
node api-runner.js --spec ./petstore.json --method GET --endpoint /pets
```

### POST with body from file (filesystem-as-parameters)
> "POST /users with data from ./test-data/new-user.json against api-spec.json"
```bash
node api-runner.js --spec ./api-spec.json --method POST --endpoint /users \
  --params-file ./test-data/new-user.json
```

### GET with query params from file
> "GET /orders using filters from ./filters.json, spec is ./shop-api.json"
```bash
node api-runner.js --spec ./shop-api.json --method GET --endpoint /orders \
  --params-file ./filters.json
```

### Authenticated request — token acquired automatically
> "Test GET /orders from ./shop-api.json, auth via /auth/token with creds from ./creds.json"
```bash
node api-runner.js --spec ./shop-api.json --method GET --endpoint /orders \
  --auth-url https://api.example.com/auth/token \
  --auth-body-file ./creds.json
```

### Request with path parameters
> "GET /users/{id} from api.json where id=123"
```bash
node api-runner.js --spec ./api.json --method GET --endpoint /users/{id} \
  --params '{"id": "123"}'
```

### Override base URL
> "Run POST /checkout against the staging server https://staging.api.example.com"
```bash
node api-runner.js --spec ./api.json --method POST --endpoint /checkout \
  --base-url https://staging.api.example.com \
  --params-file ./checkout-body.json
```

## Error handling guide

| Error | Likely cause | Action |
|-------|-------------|--------|
| Spec file not found | Wrong path | Ask user for the correct file path |
| Cannot determine base URL | Missing `servers` in spec | Ask user to provide `--base-url` |
| Auth token not acquired | Wrong credentials or auth endpoint | Show auth response body, ask for correct credentials |
| 401 Unauthorized | Token missing or expired | Check `--auth-url` matches spec's `tokenUrl` |
| 404 Not Found | Endpoint path mismatch | Verify path matches exactly what's in the spec |
| Connection refused | API server not running | Confirm base URL and server availability |
| Cannot parse spec | Invalid JSON/YAML | Validate spec file, install `js-yaml` for YAML support |

## Notes

- YAML specs require `js-yaml`: run `npm install` in the plugin root (it is in `package.json`)
- Path parameters `{id}` are resolved from `--params` or `--params-file` automatically
- Parameters not mapped to path/query go into the request body for POST/PUT/PATCH
- The `Authorization: Bearer <token>` header is set automatically when a token is present
- Use `--header "Key: Value"` for additional custom headers
