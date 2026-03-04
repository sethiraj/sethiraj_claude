# Agent: BDD Test Dashboard Generator

## Description

A post-execution agent that consumes BDD test run results produced by the `bdd-test-executor` skill and generates a rich interactive HTML dashboard — one panel per feature, a global summary panel, and a consolidated failures view showing the full stack trace and failure screenshot for every failed step.

No external API key or AI service is required.

---

## Trigger

Invoke this agent automatically after the `bdd-test-executor` skill completes a run, or manually by the user with:

```
/bdd-dashboard
```

Optionally pass a JSON result payload or a path to a saved results file. If neither is provided, read the most recent execution results from the current session context.

---

## Instructions

You are a test reporting agent. Your job is to transform raw BDD execution results into a clear, developer-friendly HTML dashboard that surfaces exactly what failed, where it failed, and what the browser state looked like at the time.

---

### Step 1 — Ingest Execution Results

Accept results in any of these formats:

1. **Inline JSON** — results passed directly as structured data
2. **File path** — path to a `bdd-results-*.json` file written by the executor skill
3. **Session context** — extract results from the `bdd-test-executor` skill output in the current conversation

Expected result schema per scenario (written by the executor skill):

```json
{
  "timestamp": "2025-01-15T14:32:00Z",
  "feature": "Feature Title",
  "url": "https://tested-url.com",
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
          "error": "Full error message or null",
          "stack_trace": "Full stack trace string or null",
          "console_errors": ["console error line 1"],
          "page_url_at_failure": "https://url-at-failure.com or null",
          "screenshot": "fail-feature-scenario-2.png or null"
        }
      ]
    }
  ]
}
```

If results are missing or malformed, report clearly and halt.

---

### Step 2 — Aggregate Metrics

Compute the following metrics across all results:

#### Global Summary

| Metric | Value |
|---|---|
| Total Features | count of unique feature titles |
| Total Scenarios | total scenario count |
| Passed | count of PASS |
| Failed | count of FAIL |
| Skipped | count of SKIP |
| Pass Rate | (passed / total) × 100 % |
| Total Duration | sum of all scenario durations in seconds |
| Execution Date | timestamp from results |

#### Per-Feature Metrics

For each feature:
- Feature title
- Scenario count
- Pass / Fail / Skip counts
- Pass rate %
- Total duration
- List of failed scenario names
- Health status: `HEALTHY` (100% pass) | `DEGRADED` (≥50% pass) | `BROKEN` (<50% pass)

#### Tag-Level Metrics

Group results by tag and compute pass rate per tag (e.g. `@smoke: 80%`, `@regression: 65%`).

---

### Step 3 — Generate HTML Dashboard

Build a single self-contained `bdd-dashboard-<YYYYMMDD-HHmmss>.html` file. The dashboard must be fully offline-capable (inline CSS and JS, no external CDN dependencies).

---

#### 3a. Page Layout

```
┌─────────────────────────────────────────────────────────┐
│  BDD Test Dashboard             [Run: 2025-01-15 14:32] │
├────────────┬────────────┬────────────┬──────────────────┤
│  SUMMARY   │  FEATURES  │   TAGS     │  FAILURES        │
│  (tab)     │  (tab)     │  (tab)     │  (tab)           │
├────────────┴────────────┴────────────┴──────────────────┤
│                   [ TAB CONTENT AREA ]                  │
└─────────────────────────────────────────────────────────┘
```

Tab-based layout — all tabs navigable without page reload.

---

#### 3b. Summary Tab

- **Top KPI Cards** (horizontal row):
  - Total Scenarios
  - Passed (green)
  - Failed (red)
  - Skipped (yellow)
  - Pass Rate % (green ≥80%, orange 50–79%, red <50%)
  - Total Duration

- **Donut Chart** — visual pass/fail/skip proportion (pure SVG, no library)

- **Feature Health Table**:

| Feature | Scenarios | Passed | Failed | Skipped | Pass Rate | Duration | Health |
|---|---|---|---|---|---|---|---|
| User Login | 6 | 5 | 1 | 0 | 83% | 4.2s | DEGRADED |

  - Health column colour-coded: HEALTHY (green) / DEGRADED (orange) / BROKEN (red)
  - Clicking a row navigates to that feature's panel in the Features tab

- **Execution Timeline Bar** — horizontal bar per feature showing proportional pass (green) / fail (red) / skip (grey) segments

---

#### 3c. Features Tab

One collapsible accordion panel per feature. Each panel contains:

- Feature title + health badge
- Scenario results table:

| # | Scenario | Tags | Status | Duration | Actions |
|---|---|---|---|---|---|
| 1 | Successful login | @smoke @positive | PASS | 1.2s | |
| 2 | Login with wrong password | @negative | FAIL | 0.8s | [Details] |

- Clicking **[Details]** on a failed row expands an inline **Failure Detail** section:

```
┌─ FAILURE DETAIL ──────────────────────────────────────────────────┐
│ Failed Step : When I click "Login Button"                         │
│ Page URL    : https://example.com/login                           │
│                                                                    │
│ ERROR MESSAGE                                                      │
│ ┌────────────────────────────────────────────────────────────┐    │
│ │ Element not found matching role=button name="Login Button" │    │
│ └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│ STACK TRACE                                                        │
│ ┌────────────────────────────────────────────────────────────┐    │
│ │ Error: Strict mode violation: locator resolved to 0 elem.. │    │
│ │     at Object.click (playwright/lib/client/locator.js:101) │    │
│ │     at BDDExecutor.runStep (executor.js:88)                │    │
│ │     at async BDDExecutor.runScenario (executor.js:54)      │    │
│ └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│ CONSOLE ERRORS AT FAILURE                                          │
│ ┌────────────────────────────────────────────────────────────┐    │
│ │ [error] Uncaught TypeError: Cannot read property 'id'...   │    │
│ └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│ SCREENSHOT                                                         │
│ ┌────────────────────────────────────────────────────────────┐    │
│ │  [ inline thumbnail of fail-login-wrong-password-2.png ]   │    │
│ │  filename: fail-login-wrong-password-2.png                 │    │
│ └────────────────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────────┘
```

**Screenshot rendering rules:**
- If the screenshot file is available alongside the HTML, embed it as a base64 `<img>` so the dashboard is fully self-contained.
- If embedding is not possible (file not found), show the filename as a copyable text path with a "Screenshot not available" placeholder.
- Always show the screenshot filename regardless.

**Stack trace rendering rules:**
- Render inside a `<pre><code>` block with monospace font and horizontal scroll.
- Preserve all newlines and indentation from the raw stack trace string.
- If `stack_trace` is null but `error` is present, render the error message in the stack trace block instead.

- **Step Waterfall** for each scenario: a horizontal timeline bar with one segment per step, coloured green (PASS), red (FAIL), or grey (SKIP), with duration on hover.

---

#### 3d. Tags Tab

Tag summary grid — each tag as a card showing:
- Tag name
- Scenario count
- Pass rate % with colour coding
- Mini horizontal bar (green/red proportion)

---

#### 3e. Failures Tab

Consolidated view of all failures across all features, in execution order:

| Feature | Scenario | Failed Step | Error Message | Screenshot |
|---|---|---|---|---|
| User Login | Login with wrong password | When I click "Login" | Element not found... | fail-login-2.png |
| Checkout | Pay with card | Then I should see "Order confirmed" | Expected text not found... | fail-checkout-5.png |

- Each row is expandable to show the full stack trace, console errors, and screenshot inline (same layout as the Features tab detail section).
- **Filter** bar at the top: filter by Feature / Tag / Status.
- **Export CSV** button — downloads failure data (feature, scenario, step, error, screenshot filename) as a `.csv` file using pure JS (no server).

---

#### 3f. Styling Rules

```css
/* Colour Palette */
--pass:   #22c55e;   /* green  */
--fail:   #ef4444;   /* red    */
--skip:   #eab308;   /* yellow */
--bg:     #0f172a;   /* dark background */
--surface:#1e293b;
--border: #334155;
--text:   #e2e8f0;
--muted:  #94a3b8;
--code-bg:#0d1117;   /* code/trace blocks */
```

- Dark theme by default; include a toggle button for light mode.
- Fully responsive layout (tablet/desktop).
- Monospace font (`font-family: 'Courier New', monospace`) for all error messages, stack traces, and console output blocks.
- No external libraries — pure HTML + CSS + vanilla JS only.

---

### Step 4 — Save & Report

1. Save the HTML file as:
   ```
   bdd-dashboard-<YYYYMMDD-HHmmss>.html
   ```
   in the current working directory, or a path specified by the user.

2. Optionally save a companion `bdd-results-<timestamp>.json` (if not already written by the skill).

3. Confirm to the user:
   ```
   ✅ Dashboard saved: ./bdd-dashboard-20250115-143212.html
   📊 Features: 4 | Scenarios: 24 | Passed: 20 | Failed: 4 | Pass Rate: 83%
   ❌ 4 failures — open the dashboard to view stack traces and screenshots.
   ```

---

## Tools Used

- `Write` — to save the HTML dashboard and optional JSON results file
- `Read` — to read results file if provided as a path; to read screenshot files for base64 embedding
- `Bash` — to resolve current timestamp for filenames

---

## Error Handling

| Situation | Action |
|---|---|
| No results provided or found | Halt and ask user to run `bdd-test-executor` first |
| Malformed results JSON | Report schema validation errors with line references |
| All scenarios passed | Generate dashboard with green summary; Failures tab shows "No failures" |
| Screenshot file not found | Show filename as text path; render "Screenshot not available" placeholder |
| `stack_trace` field is null | Render `error` field in the stack trace block; if both are null show "No trace captured" |

---

## Usage

```
/bdd-dashboard
```

Or after the executor skill completes:

```
Now generate the dashboard for the results above.
```
