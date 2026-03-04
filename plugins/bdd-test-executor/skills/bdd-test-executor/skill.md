# BDD Test Executor

Parse and execute BDD feature files against web applications using the Playwright MCP.

## Scope

This skill is **exclusively for web-based applications**. Do not attempt to execute tests for desktop, mobile native, CLI, or API-only targets without a browser UI.

---

## Instructions

You will be given one or more Gherkin `.feature` file(s) or raw BDD feature content. Follow these steps precisely:

---

### Step 1 — Parse & Validate the Feature

1. Extract the following from the feature input:
   - `Feature` title
   - `Background` steps (if any)
   - All `Scenario` / `Scenario Outline` blocks with their tags
   - `Examples` tables for `Scenario Outline`
   - All `Given`, `When`, `Then`, `And`, `But` steps in order

2. Validate the input:
   - Confirm it is valid Gherkin syntax
   - Confirm the feature targets a **web application** (must have a URL, browser navigation, or UI interaction implied)
   - If the feature is NOT web-based, stop and inform the user: _"This skill only supports web-based application testing via Playwright MCP."_
   - If the syntax is invalid, report the specific line/issue and ask the user to correct it before proceeding

3. Expand `Scenario Outline` blocks: generate one concrete scenario per row in the `Examples` table, substituting `<parameter>` placeholders with actual values.

---

### Step 2 — Map Gherkin Steps to Playwright MCP Actions

Translate each parsed step into the corresponding Playwright MCP tool call(s):

| Gherkin Pattern | Playwright MCP Tool |
|---|---|
| `Given I (am on / navigate to / open) "<url>"` | `playwright__browser_navigate` with `url` |
| `Given the browser is open at "<url>"` | `playwright__browser_navigate` with `url` |
| `When I click (on) "<element>"` | `playwright__browser_snapshot` → `playwright__browser_click` with matched `ref` |
| `When I double click "<element>"` | `playwright__browser_click` with `doubleClick: true` |
| `When I type "<text>" into "<field>"` | `playwright__browser_snapshot` → `playwright__browser_type` with matched `ref` |
| `When I fill the form with …` | `playwright__browser_snapshot` → `playwright__browser_fill_form` |
| `When I select "<option>" from "<dropdown>"` | `playwright__browser_snapshot` → `playwright__browser_select_option` |
| `When I hover over "<element>"` | `playwright__browser_snapshot` → `playwright__browser_hover` |
| `When I press the "<key>" key` | `playwright__browser_press_key` with `key` |
| `When I upload "<file>" to "<field>"` | `playwright__browser_file_upload` with `paths` |
| `When I accept the dialog` | `playwright__browser_handle_dialog` with `accept: true` |
| `When I dismiss the dialog` | `playwright__browser_handle_dialog` with `accept: false` |
| `When I go back` | `playwright__browser_navigate_back` |
| `When I resize the browser to <w>x<h>` | `playwright__browser_resize` |
| `Then I should see "<text>"` | `playwright__browser_snapshot` → assert `text` present in snapshot |
| `Then I should not see "<text>"` | `playwright__browser_snapshot` → assert `text` absent in snapshot |
| `Then the page title should be "<title>"` | `playwright__browser_evaluate` → `() => document.title` → assert |
| `Then the URL should (contain / be) "<url>"` | `playwright__browser_evaluate` → `() => window.location.href` → assert |
| `Then I take a screenshot` | `playwright__browser_take_screenshot` |
| `Then there should be no console errors` | `playwright__browser_console_messages` with `level: "error"` → assert empty |
| `Then I wait for "<text>" to appear` | `playwright__browser_wait_for` with `text` |
| `Then I wait for "<text>" to disappear` | `playwright__browser_wait_for` with `textGone` |
| `Then I wait <n> seconds` | `playwright__browser_wait_for` with `time: n` |

> For any step not matching the table above, interpret the intent and choose the most appropriate Playwright MCP tool. If genuinely ambiguous, ask the user for clarification before proceeding.

---

### Step 3 — Execute Scenarios

Execute scenarios in the order they appear in the feature file.

#### Execution Rules

- **Always** call `playwright__browser_snapshot` before any click, type, select, hover, or fill action to obtain current element `ref` values. Never guess or hardcode `ref` values.
- Match elements from the snapshot using the human-readable description from the step (role, label, placeholder, visible text). Pick the closest match.
- After each `Then` (assertion) step, capture the result as **PASS** or **FAIL**.
- If a `Background` section exists, execute its steps before **every** scenario.
- For `Scenario Outline`, execute each expanded concrete scenario independently.
- If a step fails:
  1. Record the full failure detail:
     - Scenario name
     - Step keyword + text
     - Expected value / condition
     - Actual value / what was found
     - Full error message and stack trace returned by the Playwright MCP tool
     - Console errors at time of failure (capture via `playwright__browser_console_messages` with `level: "error"`)
     - Current page URL at time of failure (capture via `playwright__browser_evaluate` → `() => window.location.href`)
  2. Immediately take a screenshot using `playwright__browser_take_screenshot` — save as `fail-<feature-slug>-<scenario-slug>-<step-index>.png`
  3. Continue executing the remaining scenarios (do not abort the full run unless the browser crashes).
- Close the browser only after all scenarios are complete using `playwright__browser_close`.

---

### Step 4 — Collect & Persist Results

After all scenarios finish, build a structured JSON result object and save it as `bdd-results-<YYYYMMDD-HHmmss>.json` in the current working directory.

#### Result schema

```json
{
  "timestamp": "2025-01-15T14:32:00Z",
  "feature": "Feature Title",
  "url": "https://tested-url.com",
  "total": 6,
  "passed": 5,
  "failed": 1,
  "skipped": 0,
  "duration_ms": 8420,
  "scenarios": [
    {
      "scenario": "Scenario name",
      "tags": ["@smoke", "@regression"],
      "status": "PASS | FAIL | SKIP",
      "duration_ms": 1540,
      "steps": [
        {
          "keyword": "Given | When | Then | And | But",
          "text": "step text",
          "status": "PASS | FAIL | SKIP",
          "duration_ms": 320,
          "error": "Full error message returned by Playwright MCP",
          "stack_trace": "Full stack trace string, null if passed",
          "console_errors": ["console error line 1", "console error line 2"],
          "page_url_at_failure": "https://url-when-failed.com or null",
          "screenshot": "fail-feature-scenario-2.png or null"
        }
      ]
    }
  ]
}
```

---

### Step 5 — Report Results

After saving the JSON, print a structured execution summary:

```
╔══════════════════════════════════════════════════════════════╗
║              BDD TEST EXECUTION REPORT                       ║
╠══════════════════════════════════════════════════════════════╣
║ Feature : <Feature Title>                                    ║
║ URL     : <Target URL>                                       ║
║ Total   : <n>  |  Passed: <n>  |  Failed: <n>  |  Skipped: <n> ║
╠══════════════════════════════════════════════════════════════╣
║ RESULTS                                                      ║
╠══════════════════════════════════════════════════════════════╣
║ ✅ PASS  <Scenario Name>                                     ║
║ ❌ FAIL  <Scenario Name>                                     ║
║          Step       : <keyword> <step text>                  ║
║          Error      : <error message>                        ║
║          Screenshot : <filename.png>                         ║
╚══════════════════════════════════════════════════════════════╝
```

- List every scenario with its PASS/FAIL/SKIP status.
- For each failed scenario include: the failing step, the full error message, and the screenshot filename.
- Sensitive data (passwords, tokens) must be masked as `****` in all output.
- End with the path to the saved JSON results file.

---

## Constraints & Guidelines

- **Web only**: Never execute tests that do not involve browser/UI interaction.
- **No hardcoded refs**: Always snapshot first, then resolve `ref` dynamically.
- **One scenario at a time**: Do not parallelize scenario execution; run sequentially.
- **Idempotent navigation**: Each scenario should start from a known state (navigate to the base URL if no `Background` provides context).
- **Sensitive data**: Mask passwords and tokens as `****` in all reports and JSON output.
- **Scope**: Only interact with the web application specified in the feature. Do not browse external URLs unless explicitly stated in a step.

---

## Usage

Provide your BDD feature content in one of these ways:

1. **Paste raw Gherkin** — paste the full `.feature` file content directly
2. **Describe the feature** — describe what to test and the target URL; the skill will infer and execute
3. **File reference** — provide the path to a `.feature` file

Example prompt:
```
/bdd-test-executor

Feature: User Login
  Scenario: Successful login with valid credentials
    Given I navigate to "https://example.com/login"
    When I type "user@example.com" into "Email"
    And I type "password123" into "Password"
    And I click "Login"
    Then I should see "Welcome, User"
```
