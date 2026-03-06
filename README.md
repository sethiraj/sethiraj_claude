# Sethiraj Claude Plugin Marketplace

> Curated Claude Code plugins by **Surendran E** — focused on test automation, web performance, and AI-assisted engineering.

**GitHub:** [github.com/sethiraj](https://github.com/sethiraj) &nbsp;·&nbsp; **Marketplace version:** 1.2.0 &nbsp;·&nbsp; **Updated:** 2026-03-06

---

## Plugins (3)

| Plugin | Category | Version | Description |
|--------|----------|---------|-------------|
| [api-test-runner](#api-test-runner) | Testing | 1.2.0 | Execute API tests from OpenAPI/Swagger specs with live dashboard |
| [bdd-test-executor](#bdd-test-executor) | Testing | 1.0.0 | Run Gherkin BDD feature files via Playwright MCP with HTML dashboard |
| [end-user-perf](#end-user-perf) | Performance | 1.0.0 | Google Lighthouse audit with Web Core Vitals and PDF report |

---

## Installation

```bash
# Install from this marketplace
claude plugin install <plugin-name>@sethiraj_claude

# Install from a direct GitHub repository
claude plugin add <repository-url>
```

**Scope options** — add `--scope` to control where the plugin is available:

| Flag | Scope | When to use |
|------|-------|-------------|
| *(default)* | `user` | Available across all your projects |
| `--scope project` | `project` | Shared with your team via version control |
| `--scope local` | `local` | Project-specific, gitignored |

---

## api-test-runner

> Execute API test cases directly from Swagger / OpenAPI specifications using Playwright as the HTTP engine, with a real-time dashboard and automatic environment setup.

| Field | Value |
|-------|-------|
| Version | 1.2.0 |
| Author | Surendran E |
| License | MIT |
| Repository | [sethiraj/sethiraj_claude](https://github.com/sethiraj/sethiraj_claude/tree/main/plugins/api-test-runner) |
| Requirements | Node.js ≥ 18, npm ≥ 8 *(auto-installed by SessionStart hook)* |

**Install:**
```bash
claude plugin install api-test-runner@sethiraj_claude
```

### What it does

Point it at a Swagger or OpenAPI spec, name an HTTP method and endpoint, and the plugin handles the rest:

- Parses JSON and YAML specs (OpenAPI 2.x Swagger + 3.x)
- Auto-detects security schemes and acquires a **bearer token** by calling the spec's `tokenUrl` before the main request
- Accepts `.json` file paths in your prompt as **request body or query parameters** (filesystem-as-parameters)
- Routes parameters to path, query, or body automatically from spec definitions; resolves `{id}` URL templates
- Executes the HTTP request via **Playwright**
- Saves results to `results/history.json` and streams them live to the dashboard via SSE

### Real-time dashboard

```bash
node scripts/dashboard-server.js   # opens http://localhost:3737
```

| Feature | Detail |
|---------|--------|
| Stats bar | Total runs · pass rate · failure count · avg duration |
| Trend chart | Response time over last 50 executions, coloured by pass/fail |
| Distribution donut | Overall pass vs fail ratio with live updates |
| History table | Sortable, filterable, searchable — All / Passed / Failed |
| Failure details | Expandable rows with Response · Stack Trace · Request Info tabs |
| PDF export | Cover page → charts → full results table → per-failure stack traces |

### Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| `SessionStart` | Every session start | Verifies Node.js ≥ 18, installs via nvm/winget/brew/apt if missing, runs `npm install`, installs Playwright browser binaries |
| `PostToolUse` | After any Bash tool call | Detects api-runner execution via `.last-run` marker and prints the dashboard URL in the terminal |

### Plugin components

| Component | Name | Description |
|-----------|------|-------------|
| Skill | `api-test-runner` | Guides Claude through spec parsing, auth, and HTTP execution |
| Agent | `api-test-reporter` | Orchestrates batch runs, persists results, manages the dashboard |

### Usage inside Claude Code

```
Test GET /users from ./api.json
```

```
POST /orders using ./order-body.json against api-spec.json,
auth via /auth/token with creds from ./creds.json
```

```
Run GET /products/{id} from ./catalog.json where id=42 and report to dashboard
```

### CLI usage

```bash
# Basic run
node scripts/api-runner.js \
  --spec ./api.json \
  --method GET \
  --endpoint /users

# With bearer token auth + reporting
node scripts/api-runner.js \
  --spec ./api.json \
  --method POST \
  --endpoint /orders \
  --params-file ./order.json \
  --auth-body-file ./creds.json \
  --report
```

**All flags:**

```
--spec <path>            OpenAPI/Swagger spec (JSON or YAML)
--method <METHOD>        GET · POST · PUT · DELETE · PATCH
--endpoint <path>        API path from spec, e.g. /users/{id}
--params-file <path>     JSON file → body (POST) or query (GET)
--params <json>          Inline JSON parameters
--auth-url <url>         Token endpoint (overrides spec)
--auth-body-file <path>  Credentials JSON file
--auth-body <json>       Inline credentials
--token <value>          Pre-existing bearer token (skips auth call)
--base-url <url>         Override base URL from spec
--header <Key: Value>    Extra request header (repeatable)
--content-type <type>    Content-Type (default: application/json)
--report                 Save result to results/history.json
--dashboard-url <url>    Dashboard server URL (default: http://localhost:3737)
--verbose                Show full stack traces on error
```

Exit codes: `0` = HTTP 2xx (pass) · `1` = HTTP 4xx/5xx or error (fail)

---

## bdd-test-executor

> Parse and execute BDD Gherkin feature files against web applications using the Playwright MCP. Captures full stack traces, console errors, and screenshots on failure. Generates a self-contained interactive HTML dashboard.

| Field | Value |
|-------|-------|
| Version | 1.0.0 |
| Author | Surendran E |
| License | MIT |
| Repository | [sethiraj/sethiraj_claude](https://github.com/sethiraj/sethiraj_claude/tree/main/plugins/bdd-test-executor) |
| Requirements | Node.js ≥ 18, npm ≥ 8, Playwright MCP |

**Install:**
```bash
claude plugin install bdd-test-executor@sethiraj_claude
```

### What it does

- Scans and parses Gherkin `.feature` files (Given/When/Then/And/But)
- Executes scenarios step-by-step using the **Playwright MCP** browser
- On failure: captures the full error message, stack trace, browser console errors, and a screenshot
- Generates a **self-contained interactive HTML dashboard** with:
  - Global summary (total / passed / failed / skipped)
  - Feature-wise results with scenario drill-down
  - Consolidated failures view with stack traces and screenshots
  - Tag-based filtering

### Usage inside Claude Code

```
Execute the feature files in ./features against https://myapp.com
```

```
Run the login.feature BDD test and generate a report
```

---

## end-user-perf

> Evaluate and report end-user performance of web applications using Google Lighthouse.

| Field | Value |
|-------|-------|
| Version | 1.0.0 |
| Author | Surendran E |
| License | MIT |
| Repository | [sethiraj/sethiraj_claude](https://github.com/sethiraj/sethiraj_claude/tree/main/plugins/end-user-perf) |
| Requirements | Node.js ≥ 18, npm ≥ 8 *(Lighthouse auto-installed if missing)* |

**Install:**
```bash
claude plugin install end-user-perf@sethiraj_claude
```

### What it does

Runs a Google Lighthouse audit on any URL and generates a structured report covering:

- **Web Core Vitals** — LCP, INP, CLS, FCP, TTFB, TBT, Speed Index
- **Network Analysis** — latency, RTT, throughput, MIME-type breakdown
- **Estimated Savings & Opportunities** — prioritised by time/byte savings
- **PDF export** of the full report

### Usage inside Claude Code

```
Analyze https://example.com and generate a performance report
```

---

## Marketplace registry

The full plugin registry is in [`index.json`](./index.json).
Each plugin has a dedicated directory under [`plugins/<name>/`](./plugins/) containing:

```
plugins/<name>/
├── .claude-plugin/
│   ├── plugin.json          Plugin manifest
│   └── marketplace.json     Marketplace metadata + changelog
├── entry.json               Lightweight index record
├── README.md                Plugin documentation
├── agents/                  Claude Code agents
├── skills/                  Claude Code skills (optional)
├── hooks/                   Hook configuration
└── scripts/                 Executable scripts (optional)
```

---

## Contributing

To submit a plugin to this marketplace:

1. Build your plugin following the [Claude Code Plugin documentation](https://code.claude.com/docs/en/plugins)
2. Host it on a public GitHub repository
3. Open an issue or pull request with your plugin's `entry.json`

---

## License

MIT © Surendran E
