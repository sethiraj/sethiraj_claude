# api-test-runner

A Claude Code plugin that executes API test cases directly from Swagger / OpenAPI specifications using Playwright as the HTTP engine. Results stream live into a real-time dashboard with pass/fail trend charts, expandable stack traces, and one-click PDF export.

---

## Table of contents

1. [Features](#features)
2. [Architecture](#architecture)
3. [Requirements](#requirements)
4. [Installation](#installation)
5. [Project structure](#project-structure)
6. [Quick start](#quick-start)
7. [Hooks](#hooks)
8. [CLI reference — api-runner.js](#cli-reference--api-runnerjs)
9. [Authentication flow](#authentication-flow)
10. [Filesystem-as-parameters](#filesystem-as-parameters)
11. [Dashboard](#dashboard)
12. [PDF export](#pdf-export)
13. [Agent — api-test-reporter](#agent--api-test-reporter)
14. [Skill — api-test-runner](#skill--api-test-runner)
15. [History file format](#history-file-format)
16. [Configuration](#configuration)
17. [Examples](#examples)
18. [Troubleshooting](#troubleshooting)

---

## Features

| Capability | Detail |
|------------|--------|
| **OpenAPI / Swagger support** | Parses JSON and YAML specs (2.x Swagger + 3.x OpenAPI) |
| **Auto bearer token** | Detects `securitySchemes`, calls the token endpoint, injects `Authorization: Bearer` |
| **File-based parameters** | Mention a `.json` file in your prompt — it becomes the request body or query params |
| **Path / query / body routing** | Parameters auto-routed from spec definitions; `{id}` templates resolved automatically |
| **Real-time dashboard** | SSE-powered live updates — response time charts, pass/fail trends, history table |
| **Stack trace inspection** | Expandable failure rows with Response / Stack Trace / Request Info tabs |
| **PDF export** | Cover page → charts → full results table → per-failure stack traces |
| **Auto Node.js setup** | `SessionStart` hook installs Node.js and Playwright if not present |
| **Post-run notification** | `PostToolUse` hook prints the dashboard URL after every API test run |
| **Persistent history** | Results stored in `results/history.json`, capped at 500 entries |
| **CI-friendly exit codes** | Exits `0` for 2xx responses, `1` for 4xx/5xx or errors |

---

## Architecture

```
api-test-runner/
│
│  ┌──────────────────── Claude Code session ─────────────────────┐
│  │                                                               │
│  │  SessionStart hook ──▶ check-node.sh / check-node.ps1        │
│  │      • Verifies Node.js ≥ 18                                  │
│  │      • Installs via nvm / winget / brew / apt / …            │
│  │      • Runs npm install + playwright install chromium         │
│  │                                                               │
│  │  /api-test-runner skill ──▶ api-runner.js                     │
│  │      • Parses OpenAPI spec                                    │
│  │      • Acquires bearer token (if required)                    │
│  │      • Executes HTTP request via Playwright                   │
│  │      • Saves result to results/history.json  ──────────────┐  │
│  │      • Writes results/.last-run marker                      │  │
│  │                                                             │  │
│  │  PostToolUse hook ──▶ post-run-notify.sh                    │  │
│  │      • Detects .last-run marker                             │  │
│  │      • Prints  http://localhost:3737  banner                │  │
│  │                                                             │  │
│  └──────────────────────────────────────────────────────────  │  │
│                                                               ▼  │
│  dashboard-server.js                                             │
│      • Serves dashboard/index.html                               │
│      • REST: GET/POST/DELETE /api/results                        │
│      • REST: GET /api/stats                                      │
│      • SSE:  GET /api/events  ◀── fs.watch(history.json)         │
│                                                                  │
│  dashboard/index.html                                            │
│      • Chart.js  — response-time trend + pass/fail donut         │
│      • jsPDF + html2canvas — client-side PDF export              │
│      • SSE client — zero-reload live updates                     │
└──────────────────────────────────────────────────────────────────
```

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Claude Code** | Latest version |
| **Node.js ≥ 18** | The `SessionStart` hook auto-installs this if missing |
| **npm** | Bundled with Node.js |
| **bash** | Git Bash, WSL, macOS Terminal, or any Linux shell |
| **Internet access** | Required for bearer token calls and Playwright browser download on first run |

---

## Installation

### 1 — Clone or copy the plugin

```bash
# Copy to your workspace
cp -r api-test-runner /path/to/your/project/

# Or place it anywhere and reference by path
```

### 2 — Install npm dependencies

```bash
cd api-test-runner
npm install
```

> **First run**: The `SessionStart` hook installs Node.js and runs `npm install` automatically, so this step is optional if you trust the hook to handle it.

### 3 — Register the plugin with Claude Code

```bash
# Install for current project only (shared via version control)
claude plugin install . --scope project

# Install for your user account (all projects)
claude plugin install . --scope user

# Install locally only (gitignored)
claude plugin install . --scope local
```

### 4 — Start the dashboard (optional — for live reporting)

```bash
node scripts/dashboard-server.js
# Opens http://localhost:3737 automatically
```

---

## Project structure

```
api-test-runner/
├── .claude-plugin/
│   └── plugin.json              Plugin manifest (name, version, component paths)
│
├── agents/
│   └── api-test-reporter.md     Agent: orchestrates test runs + dashboard reporting
│
├── skills/
│   └── api-test-runner/
│       └── SKILL.md             Skill: guides Claude through OpenAPI test execution
│
├── hooks/
│   └── hooks.json               Hook config: SessionStart + PostToolUse (Bash)
│
├── scripts/
│   ├── api-runner.js            Core CLI: parses spec, authenticates, executes HTTP
│   ├── dashboard-server.js      HTTP server: REST + SSE + file watching
│   ├── check-node.sh            SessionStart hook script (bash — macOS/Linux/Git Bash)
│   ├── check-node.ps1           SessionStart hook script (PowerShell — Windows fallback)
│   └── post-run-notify.sh       PostToolUse hook: prints dashboard URL after test runs
│
├── dashboard/
│   └── index.html               Single-file dashboard UI (Chart.js, jsPDF, html2canvas)
│
├── results/                     Created at runtime
│   ├── history.json             Persistent execution history (max 500 entries)
│   └── .last-run                Marker file — written by api-runner, read by notify hook
│
└── package.json
```

---

## Quick start

### Run a single test

```bash
node scripts/api-runner.js \
  --spec ./petstore.json \
  --method GET \
  --endpoint /pets
```

### Run and record to dashboard

```bash
# Terminal 1 — start dashboard
node scripts/dashboard-server.js

# Terminal 2 — run tests with reporting
node scripts/api-runner.js \
  --spec ./petstore.json \
  --method POST \
  --endpoint /pets \
  --params-file ./new-pet.json \
  --report
```

Open **http://localhost:3737** — the result appears instantly via SSE.

### Using the Claude Code skill

In Claude Code, describe what you want in plain English:

```
Test GET /users from ./api.json
```

```
POST /orders using ./order-body.json against api-spec.json,
auth via /auth/token with creds from ./creds.json
```

```
Run GET /products/{id} from ./catalog.json where id=42
```

---

## Hooks

Hooks are defined in `hooks/hooks.json` and registered automatically when the plugin is installed.

### SessionStart — Node.js environment check

**Fires:** Once at the beginning of every Claude Code session.

**What it does:**

```
Step 1 — Node.js check / install
  ├── Already installed?  → prints "✓ Node.js vXX detected"  and continues
  └── Not found?
        ├── Try nvm / nvm.sh
        ├── Try Windows PowerShell (winget → Chocolatey → Scoop → direct MSI)
        ├── Try Homebrew (macOS)
        ├── Try apt / dnf / yum / pacman / apk (Linux)
        └── Fail with install URL if all methods fail

Step 2 — npm dependencies
  ├── node_modules/ exists and has playwright?  → skip
  └── Missing?  → runs npm install --prefer-offline

Step 3 — Playwright browsers (first run only)
  ├── .playwright-installed marker present?  → skip
  └── Missing?  → runs playwright install chromium, writes marker
```

**Hook command:**

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-node.sh"
  || powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/check-node.ps1"
```

The bash script runs first; PowerShell is only invoked if bash exits non-zero (e.g., on a bare Windows system without Git Bash in PATH).

---

### PostToolUse (Bash) — dashboard link notification

**Fires:** After every Bash tool use by Claude.

**What it does:** Checks whether the Bash call just ran an API test, then prints a prominent banner containing the dashboard URL and the result of the last execution.

**Detection strategy (layered for reliability):**

| Layer | Signal | Notes |
|-------|--------|-------|
| 1 (primary) | `results/.last-run` marker mod-time < 15 s | Written exclusively by `api-runner.js --report` |
| 2 (fallback) | Bash tool input JSON contains `"api-runner"` | Read from stdin piped by Claude Code |
| 3 (fallback) | `results/history.json` mod-time < 5 s | Catches wrapper scripts and npm aliases |

**Example banner output:**

```
╔════════════════════════════════════════════════════════════╗
║  📊  API Test Runner — Results Dashboard                   ║
├────────────────────────────────────────────────────────────╢
║    http://localhost:3737                                   ║
║                                                            ║
║    Last run:  ❌ 422  POST /users  (312ms)                 ║
║                                                            ║
║    Start server →  node .../scripts/dashboard-server.js   ║
╚════════════════════════════════════════════════════════════╝
```

If the dashboard server is already running the bottom line changes to:

```
║    Server running  ·  open the link above in your browser  ║
```

---

## CLI reference — api-runner.js

```
node scripts/api-runner.js [required] [options]
```

### Required flags

| Flag | Description | Example |
|------|-------------|---------|
| `--spec <path>` | Path to OpenAPI / Swagger spec (JSON or YAML) | `--spec ./petstore.json` |
| `--method <METHOD>` | HTTP method | `--method POST` |
| `--endpoint <path>` | API path as defined in the spec | `--endpoint /users/{id}` |

### Parameter flags

| Flag | Description | Example |
|------|-------------|---------|
| `--params-file <path>` | JSON file — contents become body (POST/PUT/PATCH) or query params (GET/DELETE) | `--params-file ./body.json` |
| `--params <json>` | Inline JSON parameters string | `--params '{"id":"42"}'` |

**Parameter routing logic:**

```
For each key in params:
  ├── Declared in spec as in: path   → placed in URL template
  ├── Declared in spec as in: query  → appended as query string
  └── Not declared (or spec absent):
        ├── Method is POST/PUT/PATCH  → added to request body
        └── Method is GET/DELETE      → appended as query string
```

### Authentication flags

| Flag | Description |
|------|-------------|
| `--auth-url <url>` | Override token endpoint URL (skips spec auto-detection) |
| `--auth-body-file <path>` | JSON file containing login credentials |
| `--auth-body <json>` | Inline JSON credentials string |
| `--token <value>` | Supply a pre-existing bearer token (skips the auth call entirely) |

### Request customisation flags

| Flag | Description | Default |
|------|-------------|---------|
| `--base-url <url>` | Override the base URL extracted from the spec | From spec `servers[0].url` |
| `--header <Key: Value>` | Add a custom request header (repeatable) | — |
| `--content-type <type>` | `Content-Type` for request body | `application/json` |

### Reporting flags

| Flag | Description |
|------|-------------|
| `--report` | Persist result to `results/history.json` and notify the dashboard server |
| `--dashboard-url <url>` | Override dashboard server URL for live push | `http://localhost:3737` |

### Utility flags

| Flag | Description |
|------|-------------|
| `--verbose` | Print full stack traces on error |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | HTTP 2xx — test passed |
| `1` | HTTP 4xx / 5xx, network error, or bad arguments |

---

## Authentication flow

The runner detects and handles authentication automatically from the OpenAPI spec.

### Auto-detection

```
1. Check endpoint-level security field
   └── If empty array [] → skip auth even if global security is set

2. Fall back to global security field
   └── If present → auth required

3. Fall back to securitySchemes / securityDefinitions presence
   └── If any schemes defined → assume auth required (conservative)
```

### Token endpoint resolution

```
OpenAPI 3.x:  components.securitySchemes.<name>.flows.<flow>.tokenUrl
Swagger 2.x:  securityDefinitions.<name>.tokenUrl
--auth-url flag overrides everything above
```

### Token field search order

After a successful POST to the token endpoint, the runner searches the response body for:

```
access_token  →  token  →  id_token  →  authToken  →  jwt  →  bearerToken
```

The first non-empty value is injected as `Authorization: Bearer <token>`.

### Providing credentials

```bash
# From a file
--auth-body-file ./creds.json

# Inline
--auth-body '{"username":"admin","password":"secret"}'

# Skip the call — use a pre-existing token
--token "eyJhbGciOiJSUzI1NiJ9..."
```

---

## Filesystem-as-parameters

Any `.json` file path mentioned in your prompt or passed via `--params-file` is treated as the source of API parameters.

| HTTP method | File content becomes |
|-------------|---------------------|
| `POST` / `PUT` / `PATCH` | **Request body** |
| `GET` / `DELETE` | **Query parameters** |

Parameters found in the file are matched against the spec's parameter list first. Path parameters (`{id}`) are extracted and placed in the URL. Everything else goes to body or query string depending on the method.

**Example `new-user.json`:**

```json
{
  "name": "Alice",
  "email": "alice@example.com",
  "role": "admin"
}
```

```bash
node scripts/api-runner.js \
  --spec ./api.json \
  --method POST \
  --endpoint /users \
  --params-file ./new-user.json
```

All three fields go into the request body. No spec involvement needed.

---

## Dashboard

Start the dashboard server:

```bash
node scripts/dashboard-server.js                   # default port 3737
DASHBOARD_PORT=4000 node scripts/dashboard-server.js  # custom port
node scripts/dashboard-server.js --port 4000           # alternative
node scripts/dashboard-server.js --no-open             # don't open browser
```

### Server endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Dashboard HTML |
| `GET` | `/api/results` | Full history array (JSON) |
| `POST` | `/api/results` | Record a result (used by api-runner `--report`) |
| `DELETE` | `/api/results` | Clear all history |
| `GET` | `/api/stats` | Aggregated statistics |
| `GET` | `/api/events` | SSE stream — push live updates |

### Dashboard UI features

#### Stats bar

| Card | Data |
|------|------|
| Total Runs | Count of all recorded executions |
| Pass Rate | Percentage of 2xx responses |
| Failures | Count of non-2xx + error runs |
| Avg Duration | Mean response time of last 20 runs |

#### Charts

**Trend chart** — response time over the last 50 executions:
- Line shows response time in milliseconds
- Each data point is coloured **green** (pass) or **red** (fail)
- Tooltip shows method, endpoint, status code, and duration
- Updates in real time via SSE

**Distribution donut** — overall pass/fail ratio:
- 72% cutout with pass rate displayed in the centre
- Tooltip shows absolute count and percentage per segment
- Updates in real time via SSE

#### Execution history table

| Column | Notes |
|--------|-------|
| Time | Relative (`2m ago`) — absolute on hover |
| Method | Colour-coded badge (blue GET, green POST, orange PUT, red DELETE, purple PATCH) |
| Endpoint | Monospace path |
| Status | Green `✓ 200` or red `✕ 422` badge |
| Duration | Response time in ms |
| Spec | Filename of the OpenAPI spec used |
| Details | Expand button for failure rows |

**Filtering:** All / Passed / Failed toggle buttons
**Search:** Live filter by endpoint, method, status, or spec name
**Sorting:** Click any column header to sort ascending / descending

#### Failure detail rows

Click **Details** on any row to expand three tabs:

| Tab | Content |
|-----|---------|
| **Response** | Full response body (formatted JSON or plain text) |
| **Stack Trace** | Error message + `at` frames (colour-highlighted) |
| **Request Info** | Method, endpoint, base URL, spec, timestamp, duration |

#### Live updates

The dashboard maintains a persistent SSE connection to `/api/events`. When `api-runner.js --report` writes a result:

1. `fs.watch` detects the `history.json` change
2. Server broadcasts `{ type: "result", data: <entry> }` to all SSE clients
3. Dashboard prepends the row, flashes it, and updates all charts and stats — no page reload

A heartbeat comment is sent every 25 seconds to keep proxies from closing the connection.

---

## PDF export

Click **⬇ Export PDF** in the dashboard header. The export is generated entirely in the browser using jsPDF and html2canvas — no server involvement.

### PDF structure

| Page | Content |
|------|---------|
| 1 — Cover | Title, generated timestamp, 4-column stats band |
| 2 — Charts | Screenshot of trend chart and distribution donut |
| 3 — Results table | Latest 200 executions with status colour-coding |
| 4+ — Failures | Per-failure section: header, error message, stack trace (up to 10 lines each), response body snippet |

The file is saved as `api-test-report-YYYY-MM-DDTHH-MM-SS.pdf`.

> Only failures that have `error`, `stackTrace`, or `body` data appear in the Failures section. Up to 50 failures are included; a note is appended if there are more.

---

## Agent — api-test-reporter

The `api-test-reporter` agent is automatically available in Claude Code after plugin installation. Claude invokes it when you ask to:

- Run API tests with reporting
- View test history or analytics
- Start or interact with the dashboard
- Export a test report PDF
- Diagnose test failures

### Manual invocation

In Claude Code, describe your goal:

```
Run a full test suite against api.json, report all results to the dashboard
```

```
Show me the failures from today's runs with their stack traces
```

```
What is the current pass rate for the /orders endpoint?
```

### Batch test workflow

```bash
# The agent follows this pattern for multiple endpoints:
for endpoint in /users /orders /products /inventory; do
  node scripts/api-runner.js \
    --spec ./api.json \
    --method GET \
    --endpoint "$endpoint" \
    --report
done
```

### Reading failure details programmatically

```bash
node -e "
  const h = require('./results/history.json');
  const failures = h.filter(r => !r.passed);
  failures.slice(0, 5).forEach(f => {
    console.log(f.method, f.endpoint, '->', f.status, f.statusText);
    if (f.error) console.log('  Error:', f.error);
    if (f.stackTrace) console.log(f.stackTrace.split('\n').slice(0,3).join('\n'));
    console.log('');
  });
"
```

---

## Skill — api-test-runner

The skill `/api-test-runner` guides Claude through executing a single API test step by step. It triggers automatically when you describe an API test in natural language.

### What Claude extracts from your prompt

| Element | How Claude finds it |
|---------|-------------------|
| **Spec file** | File path ending in `.json`, `.yaml`, or `.yml` |
| **HTTP method** | GET / POST / PUT / DELETE / PATCH keyword |
| **Endpoint path** | A string starting with `/` matching a path in the spec |
| **Parameter files** | Any `.json` file paths mentioned → used as body or query params |
| **Auth info** | Auth endpoint, credentials file, or inline `username`/`password` |

### Supported prompt patterns

```
# Simple method + spec
Test GET /pets from petstore.json

# With body file
POST /users with data from ./test-data/new-user.json against api-spec.json

# With authentication
Test GET /orders from ./shop-api.json,
auth via /auth/token with credentials from ./creds.json

# With path parameters
GET /users/{id} from api.json where id=123

# Override base URL (e.g. target staging)
Run POST /checkout against https://staging.api.example.com using api.json
```

---

## History file format

Every execution recorded with `--report` is appended to `results/history.json`.

```json
[
  {
    "id":         "1712345678901-abc12",
    "timestamp":  "2026-03-06T12:34:56.789Z",
    "spec":       "/absolute/path/to/api.json",
    "specName":   "api.json",
    "method":     "POST",
    "endpoint":   "/users",
    "baseUrl":    "https://api.example.com",
    "status":     422,
    "statusText": "Unprocessable Entity",
    "duration":   312,
    "passed":     false,
    "body":       { "error": "email already exists" },
    "error":      "HTTP 422 Unprocessable Entity",
    "stackTrace": null
  }
]
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique entry ID (`timestamp-random`) |
| `timestamp` | ISO 8601 | When the test ran |
| `spec` | string | Absolute path to the OpenAPI spec file |
| `specName` | string | Basename of the spec file |
| `method` | string | HTTP method (`GET`, `POST`, …) |
| `endpoint` | string | Resolved path (path params substituted) |
| `baseUrl` | string | Base URL used for the request |
| `status` | number | HTTP response status code (`0` on network error) |
| `statusText` | string | HTTP status text or `"Error"` |
| `duration` | number | Round-trip time in milliseconds |
| `passed` | boolean | `true` if status is 2xx |
| `body` | any | Response body (parsed JSON or string) |
| `error` | string \| null | Error message for failures |
| `stackTrace` | string \| null | Full stack trace for thrown errors |

History is capped at **500 entries**; oldest entries are removed automatically.

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DASHBOARD_PORT` | `3737` | Port for the dashboard server |
| `CLAUDE_PLUGIN_ROOT` | Auto-detected | Absolute path to plugin directory (set by Claude Code) |
| `DEBUG` | — | Set to any value to enable verbose error stack traces |

### Custom dashboard port

```bash
# Environment variable
DASHBOARD_PORT=4000 node scripts/dashboard-server.js

# CLI flag
node scripts/dashboard-server.js --port 4000

# Pass to api-runner for live push
node scripts/api-runner.js ... --report --dashboard-url http://localhost:4000
```

---

## Examples

### Example 1 — Public Petstore API (no auth)

```bash
node scripts/api-runner.js \
  --spec ./petstore.json \
  --method GET \
  --endpoint /pets \
  --params '{"limit": 10}'
```

**Expected output:**
```
[Spec]    Swagger Petstore v1.0.0
[Base URL] https://petstore.swagger.io/v2

[Request] GET https://petstore.swagger.io/v2/pets
[Query]   {"limit":"10"}

────────────────────────────────────────────────────────────
[Response] 200 OK  (124ms)
[Body]
[ { "id": 1, "name": "Buddy", ... }, ... ]

────────────────────────────────────────────────────────────
[Result]   ✅ PASS
[URL]      https://petstore.swagger.io/v2/pets
[Duration] 124ms
────────────────────────────────────────────────────────────
```

---

### Example 2 — POST with file body + reporting

**`new-user.json`:**
```json
{
  "name": "Alice Chen",
  "email": "alice@example.com",
  "role": "editor"
}
```

```bash
node scripts/api-runner.js \
  --spec ./api.json \
  --method POST \
  --endpoint /users \
  --params-file ./new-user.json \
  --report
```

The result is saved to `results/history.json` and pushed to the dashboard.

---

### Example 3 — OAuth2 authenticated request

**`creds.json`:**
```json
{
  "grant_type": "client_credentials",
  "client_id": "my-client",
  "client_secret": "s3cr3t"
}
```

```bash
node scripts/api-runner.js \
  --spec ./enterprise-api.json \
  --method GET \
  --endpoint /reports/summary \
  --auth-body-file ./creds.json \
  --report
```

The runner will:
1. Read `tokenUrl` from the spec's `securitySchemes`
2. POST credentials to the token endpoint
3. Extract `access_token` from the response
4. Set `Authorization: Bearer <token>` on the main request

---

### Example 4 — Path parameter resolution

```bash
node scripts/api-runner.js \
  --spec ./api.json \
  --method GET \
  --endpoint /users/{userId}/orders/{orderId} \
  --params '{"userId": "u-42", "orderId": "ord-99"}'
```

The URL becomes: `GET /users/u-42/orders/ord-99`

---

### Example 5 — Override to staging environment

```bash
node scripts/api-runner.js \
  --spec ./api.json \
  --method DELETE \
  --endpoint /products/{id} \
  --params '{"id": "prod-123"}' \
  --base-url https://staging.example.com/api/v2 \
  --token "staging-dev-token" \
  --report
```

---

### Example 6 — Batch test suite

```bash
#!/usr/bin/env bash
SPEC="./api.json"
BASE="https://api.example.com"
AUTH_FILE="./creds.json"

endpoints=(
  "GET /users"
  "GET /orders"
  "GET /products"
  "POST /health-check"
)

PASS=0; FAIL=0

for entry in "${endpoints[@]}"; do
  METHOD=$(echo "$entry" | cut -d' ' -f1)
  ENDPOINT=$(echo "$entry" | cut -d' ' -f2)

  node scripts/api-runner.js \
    --spec "$SPEC" \
    --method "$METHOD" \
    --endpoint "$ENDPOINT" \
    --base-url "$BASE" \
    --auth-body-file "$AUTH_FILE" \
    --report

  [ $? -eq 0 ] && ((PASS++)) || ((FAIL++))
done

echo ""
echo "Suite complete — Passed: $PASS  Failed: $FAIL"
```

---

## Troubleshooting

### Node.js not found after hook runs

The `SessionStart` hook installs Node.js, but some installers require a **shell restart** to update PATH. If you see `node: command not found` after the hook:

```bash
# Restart your terminal, then verify
node --version

# Or source your shell profile manually
source ~/.bashrc   # or ~/.zshrc / ~/.profile
```

On Windows, open a new terminal window after the MSI installer finishes.

---

### Dashboard not updating in real time

| Symptom | Fix |
|---------|-----|
| Status dot is red (Disconnected) | Dashboard server is not running — `node scripts/dashboard-server.js` |
| Status dot green but no new rows | Run tests with `--report` flag |
| Dashboard loads but charts are empty | All past runs did not use `--report`; run at least one test with `--report` |
| Port already in use | `DASHBOARD_PORT=3738 node scripts/dashboard-server.js` |

---

### YAML spec not parsing

```
Error: Spec file appears to be YAML but js-yaml is not installed.
```

```bash
cd api-test-runner && npm install
```

`js-yaml` is in `package.json` but might be missing if `node_modules` was deleted. The `SessionStart` hook also handles this.

---

### Cannot determine base URL

```
Error: Cannot determine base URL from spec. Provide --base-url <url>
```

Your spec is missing a `servers` array (OpenAPI 3.x) or `host` field (Swagger 2.x). Supply it explicitly:

```bash
--base-url https://api.example.com
```

---

### Auth token not found in response

```
Warning: Token field not found in response. Available keys: ...
```

The token endpoint returned a non-standard field name. Supply the token directly:

```bash
--token "your-token-here"
```

Or add a pre-processing step to extract and pass the token:

```bash
TOKEN=$(curl -s -X POST https://auth.example.com/token \
  -d '{"username":"admin","password":"pass"}' \
  -H 'Content-Type: application/json' | node -e "
    let d=''; process.stdin.on('data',c=>d+=c).on('end',()=>
      console.log(JSON.parse(d).my_custom_token_field)
    );
  ")

node scripts/api-runner.js ... --token "$TOKEN"
```

---

### PDF export fails

The PDF export uses `html2canvas` and `jsPDF` from CDN. If you are on an offline network:

1. Download the libraries and host them locally
2. Update the `<script>` tags in `dashboard/index.html` to point to your local copies

---

### Post-run hook not printing the banner

The notify hook only fires when `--report` is used (it watches for the `.last-run` marker). Without `--report`, no marker is written and the banner is suppressed.

```bash
# With --report  →  banner appears after execution
node scripts/api-runner.js --spec ./api.json --method GET --endpoint /users --report

# Without --report  →  no banner
node scripts/api-runner.js --spec ./api.json --method GET --endpoint /users
```

---

## License

MIT
