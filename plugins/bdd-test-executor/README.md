# bdd-test-executor

> **Claude Code Plugin** — Parse and execute BDD feature files against web applications using Playwright MCP, then generate an interactive test dashboard with full failure stack traces and screenshots.

**Author:** Surendran E
**Version:** 1.0.0
**License:** MIT

---

## Overview

`bdd-test-executor` is a Claude Code plugin that brings end-to-end BDD test execution directly into your Claude Code session. You provide Gherkin `.feature` files; the plugin handles the rest:

1. **Scans** your features folder automatically on every prompt (hook)
2. **Parses** Gherkin syntax — `Feature`, `Background`, `Scenario`, `Scenario Outline`, `Examples`
3. **Executes** each scenario step-by-step using the [Playwright MCP](https://github.com/microsoft/playwright-mcp) server
4. **Captures** the full error message, stack trace, console errors, and a screenshot on every failure
5. **Generates** a self-contained interactive HTML dashboard with feature-wise results, a global summary, and a consolidated failures view

> **Web applications only.** This plugin exclusively targets browser-based UIs. API-only, CLI, or native desktop targets are not supported.
>
> **No API key required.** The dashboard is generated entirely from execution results — no external AI service is needed.

---

## Prerequisites

| Requirement | Minimum version | Notes |
|---|---|---|
| [Node.js](https://nodejs.org/) | 18.x | Required for Playwright MCP via npx |
| npm | 8.x | Bundled with Node.js |
| [Claude Code](https://claude.ai/code) | latest | Plugin host |

---

## Installation

### From a local directory

```bash
claude plugin add ./path/to/execute-bdd-test
```

### From a registry / marketplace _(future)_

```bash
claude plugin add bdd-test-executor
```

Claude Code loads the plugin automatically on next start.

---

## Directory Structure

```
execute-bdd-test/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── .mcp.json                    # Playwright MCP server definition
├── agents/
│   └── bdd-dashboard/
│       └── agent.md             # Dashboard generator agent
├── hooks/
│   └── hooks.json               # Hook event configuration
├── scripts/
│   ├── scan-features.sh         # UserPromptSubmit: discovers .feature files
│   ├── validate-playwright.sh   # PreToolUse: validates Playwright MCP
│   └── collect-results.sh       # PostToolUse: writes results stub after browser close
├── skills/
│   └── bdd-test-executor/
│       └── skill.md             # BDD parse & execute skill
└── README.md                    # This file
```

---

## Quick Start

### 1 — Point to your features folder

The plugin auto-discovers `.feature` files on every prompt. Set the folder in any of these ways:

```bash
# Option A — environment variable (recommended for CI)
export BDD_FEATURES_DIR=/path/to/features

# Option B — mention it in your Claude prompt
"features folder: ./tests/features"

# Option C — use the default location
mkdir -p ./features   # plugin looks here if nothing else is set
```

### 2 — Run the executor skill

Paste feature content directly or let the plugin pick up files from the scanned folder:

```
/bdd-test-executor

Feature: User Login
  Scenario: Successful login
    Given I navigate to "https://example.com/login"
    When I type "user@example.com" into "Email"
    And I type "secret123" into "Password"
    And I click "Login"
    Then I should see "Welcome"
```

Or reference a discovered file:

```
Execute the login.feature file found in ./tests/features
```

### 3 — Generate the dashboard

After execution completes, invoke the dashboard agent:

```
/bdd-dashboard
```

Or ask naturally:

```
Generate the test dashboard for the results above.
```

The dashboard is saved as `bdd-dashboard-<YYYYMMDD-HHmmss>.html` in your current working directory.

---

## Skills

### `bdd-test-executor`

Invoked with `/bdd-test-executor` or naturally by describing what to test.

| Phase | What it does |
|---|---|
| **Parse** | Validates Gherkin syntax; expands `Scenario Outline` into concrete scenarios; rejects non-web features |
| **Map** | Translates every `Given/When/Then` step to the correct Playwright MCP tool call |
| **Execute** | Runs scenarios sequentially; always snapshots before interacting; on failure captures error, stack trace, console errors, page URL, and a screenshot |
| **Persist** | Saves a `bdd-results-<timestamp>.json` with full structured results including all failure details |
| **Report** | Prints a formatted console summary with PASS/FAIL per scenario and screenshot filenames |

#### Failure data captured per step

| Field | Description |
|---|---|
| `error` | Full error message returned by the Playwright MCP tool |
| `stack_trace` | Complete stack trace string |
| `console_errors` | Browser console errors captured at the moment of failure |
| `page_url_at_failure` | URL the browser was on when the step failed |
| `screenshot` | Filename of the automatically captured failure screenshot |

Screenshots are saved as `fail-<feature-slug>-<scenario-slug>-<step-index>.png` in the working directory.

#### Supported Gherkin → Playwright mappings

| Gherkin step | Playwright MCP tool |
|---|---|
| `Given I navigate to "<url>"` | `browser_navigate` |
| `When I click "<element>"` | `browser_snapshot` → `browser_click` |
| `When I type "<text>" into "<field>"` | `browser_snapshot` → `browser_type` |
| `When I fill the form with …` | `browser_snapshot` → `browser_fill_form` |
| `When I select "<option>" from "<dropdown>"` | `browser_snapshot` → `browser_select_option` |
| `When I hover over "<element>"` | `browser_snapshot` → `browser_hover` |
| `When I press the "<key>" key` | `browser_press_key` |
| `When I upload "<file>" to "<field>"` | `browser_file_upload` |
| `When I accept / dismiss the dialog` | `browser_handle_dialog` |
| `When I go back` | `browser_navigate_back` |
| `When I resize the browser to <w>x<h>` | `browser_resize` |
| `Then I should see "<text>"` | `browser_snapshot` → assert text present |
| `Then I should not see "<text>"` | `browser_snapshot` → assert text absent |
| `Then the page title should be "<title>"` | `browser_evaluate` → `document.title` |
| `Then the URL should contain "<url>"` | `browser_evaluate` → `window.location.href` |
| `Then I take a screenshot` | `browser_take_screenshot` |
| `Then there should be no console errors` | `browser_console_messages` |
| `Then I wait for "<text>" to appear` | `browser_wait_for` |
| `Then I wait <n> seconds` | `browser_wait_for` with `time` |

---

## Agents

### `bdd-dashboard`

Invoked with `/bdd-dashboard` after a test run.

| Phase | What it does |
|---|---|
| **Ingest** | Reads execution results from inline JSON, a file path, or current session context |
| **Aggregate** | Computes global, per-feature, and per-tag metrics |
| **Generate** | Builds a single offline-capable HTML dashboard |
| **Save** | Writes `bdd-dashboard-<timestamp>.html` to disk |

#### Dashboard tabs

| Tab | Contents |
|---|---|
| **Summary** | KPI cards, donut chart (SVG), feature health table, execution timeline bars |
| **Features** | Accordion per feature; scenario results table; expandable failure detail with error message, stack trace, console errors, and screenshot per failed step; step waterfall |
| **Tags** | Pass-rate card per tag (`@smoke`, `@regression`, etc.) |
| **Failures** | Consolidated failure list; expandable rows with full stack trace and screenshot; filter by Feature/Tag; CSV export |

#### Failure detail in the dashboard

Each failed step expands to show:

```
Failed Step   : When I click "Login Button"
Page URL      : https://example.com/login

ERROR MESSAGE
  Element not found matching role=button name="Login Button"

STACK TRACE
  Error: Strict mode violation: locator resolved to 0 elements
      at Object.click (playwright/lib/client/locator.js:101)
      at BDDExecutor.runStep (executor.js:88)

CONSOLE ERRORS AT FAILURE
  [error] Uncaught TypeError: Cannot read property 'id' of undefined

SCREENSHOT
  [ inline thumbnail ]
  fail-login-wrong-password-2.png
```

Dashboard styling: dark theme with light-mode toggle, fully responsive, pure HTML + CSS + vanilla JS — no external dependencies, no API key needed.

---

## Hooks

Three hooks fire automatically during a session:

### 1. `UserPromptSubmit` — Feature Scanner

**Script:** `scripts/scan-features.sh`
**Fires:** On every user prompt submission
**Blocking:** Yes

Resolves and scans the features directory using this priority order:

```
BDD_FEATURES_DIR env var
        │
        ├── set → use it
        │
        └── not set → parse "features folder: <path>" from prompt
                              │
                              ├── found → use extracted path
                              │
                              └── not found → default to ./features
```

**Output** injected into Claude context:

```
╔══════════════════════════════════════════════════════════════╗
║            BDD FEATURES DISCOVERED                          ║
╠══════════════════════════════════════════════════════════════╣
║  Directory : ./tests/features                               ║
║  Found     : 3 feature file(s)                              ║
╠══════════════════════════════════════════════════════════════╣
║  📄 login.feature                         [ 4 scenario(s)] ║
║  📄 checkout.feature                      [ 6 scenario(s)] ║
║  📄 profile.feature                       [ 3 scenario(s)] ║
╚══════════════════════════════════════════════════════════════╝
```

If the directory does not exist or contains no `.feature` files, a warning is printed with instructions — the hook exits cleanly so the session continues.

---

### 2. `PreToolUse` — Playwright Validator

**Script:** `scripts/validate-playwright.sh`
**Fires:** Before `browser_navigate` (first Playwright call of a run)
**Blocking:** Yes

- Checks that `npx` and `node` (≥18) are on `PATH`
- Verifies `@playwright/mcp@latest` is reachable via npx

---

### 3. `PostToolUse` — Results Collector

**Script:** `scripts/collect-results.sh`
**Fires:** After `browser_close` (end of a test run)
**Blocking:** No (async)

If no `bdd-results-*.json` file exists in the working directory, writes a timestamped stub so the dashboard agent always has a file to read.

---

## MCP Server

The Playwright MCP server is defined in `.mcp.json`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    }
  }
}
```

No pre-installation required — `npx` fetches and runs `@playwright/mcp` on first use.

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `BDD_FEATURES_DIR` | `./features` | Path to folder containing `.feature` files |
| `CLAUDE_PLUGIN_ROOT` | set by Claude Code | Absolute path to this plugin directory (used by hook scripts) |

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `No .feature files found` | Wrong directory | Set `BDD_FEATURES_DIR` or mention `"features folder: <path>"` in your prompt |
| `npx not found` | Node.js not installed | Install Node.js ≥18 from https://nodejs.org |
| Playwright browser does not launch | `@playwright/mcp` not cached | Run `npx @playwright/mcp@latest --version` manually first |
| Hook script permission denied | Script not executable | Run `chmod +x scripts/*.sh` inside the plugin directory |
| Windows: script not found | Path separator issue | Use Git Bash or WSL; ensure `CLAUDE_PLUGIN_ROOT` uses forward slashes |
| Stack trace shows "No trace captured" | Playwright MCP returned error only | The `error` field will be shown in its place — this is normal for assertion failures |
| Screenshot not embedded in dashboard | File not found next to HTML | Ensure screenshots are in the same directory as the dashboard HTML, or re-run the executor |
| Feature executed but `Scenario Outline` not expanded | Malformed `Examples` table | Ensure the `Examples:` block is indented under `Scenario Outline:` and all `<placeholders>` match column headers |

---

## License

MIT © Surendran E
