# end-user-perf

> **Claude Code Plugin** — Evaluate and report end-user performance of web applications using Google Lighthouse.

**Author:** Surendran E
**Version:** 1.0.0
**License:** MIT

---

## Overview

`end-user-perf` is a Claude Code plugin that automates web performance auditing. Point it at any public URL and it produces a structured PDF report covering:

- **Web Core Vitals** — LCP, INP, CLS, FCP, TTFB, TBT, Speed Index
- **Network Analysis** — latency, RTT, throughput, and MIME-type breakdown
- **Estimated Savings** — prioritised list of Lighthouse opportunities with time/byte savings

The plugin uses [Google Lighthouse](https://github.com/GoogleChrome/lighthouse) via MCP and runs entirely within your Claude Code session — no external service or API key required.

---

## Prerequisites

| Requirement | Minimum version | Notes |
|---|---|---|
| [Node.js](https://nodejs.org/) | 18.x | Required to run Lighthouse |
| npm | 8.x | Bundled with Node.js |
| [Claude Code](https://claude.ai/code) | latest | Plugin host |

> **Lighthouse is installed automatically.** The plugin's pre-hook checks for Lighthouse before every audit and installs it globally (`npm install -g lighthouse`) if it is missing. See [Hooks](#hooks) for details.

---

## Installation

### From a local directory

```bash
# Inside your project (or globally)
claude plugin add ./path/to/end-user-perf-plugin
```

### From a registry / marketplace _(future)_

```bash
claude plugin add end-user-perf
```

After installation Claude Code loads the plugin automatically on next start.

---

## Directory Structure

```
end-user-perf-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── agents/
│   └── perf-report.md       # Performance report agent definition
├── hooks/
│   └── hooks.json           # PreToolUse hook configuration
├── scripts/
│   └── validate-lighthouse.sh  # Lighthouse install/validation script
├── .mcp.json                # MCP server definition (lighthouse)
└── README.md                # This file
```

---

## Usage

Once the plugin is loaded in Claude Code, use the `perf-report` agent by describing what you want to audit:

```
Analyze https://example.com and generate a performance report
```

```
Run a desktop performance audit on https://shop.example.com
```

```
Generate an end-user performance report for https://app.example.com using mobile profile
```

### Device profile

| User instruction | Profile used |
|---|---|
| Not specified | **Mobile** (default, aligns with Google mobile-first indexing) |
| "desktop" | Desktop |
| "mobile" | Mobile |

### Output

The agent saves a PDF to your current working directory:

```
perf-report-example.com-20260303-143022.pdf
```

It then prints the full file path in the Claude Code session.

---

## Report Sections

### Cover Page
- Audited URL
- Audit date and time
- Overall Lighthouse Performance Score (0–100, color-coded)
- Device profile used

### Executive Summary
A 2–3 sentence assessment of the page's overall performance health.

### Section 1 — Web Core Vitals

| Metric | Full Name | What it measures |
|---|---|---|
| LCP | Largest Contentful Paint | Time to render the largest visible element |
| INP | Interaction to Next Paint | Responsiveness to user interactions |
| CLS | Cumulative Layout Shift | Visual stability — unexpected layout shifts |
| FCP | First Contentful Paint | Time to first visible content |
| TTFB | Time to First Byte | Server responsiveness |
| TBT | Total Blocking Time | Main-thread blocking duration |
| SI | Speed Index | Speed at which content is visually populated |

Each metric is reported with its measured value, Lighthouse score, and **Pass / Needs Improvement / Fail** classification.

Score colour coding used throughout the report:

| Score | Status | Colour |
|---|---|---|
| 90 – 100 | Pass | Green |
| 50 – 89 | Needs Improvement | Orange |
| 0 – 49 | Fail | Red |

### Section 2 — Network Analysis

**Latency & Timing**
- Total page load time
- TTFB per origin
- Estimated Round Trip Time (RTT) per origin
- DNS lookup time
- TCP + TLS handshake time

**Throughput**
- Total page weight (transferred bytes)
- Total number of network requests
- Average response size
- Estimated bandwidth utilization

**MIME Type Breakdown**
All requests grouped by resource type (HTML, CSS, JavaScript, Images, Fonts, XHR/Fetch, Media, Other) with count, total size, and percentage of total page weight. Includes the top 3 largest URLs per type.

### Section 3 — Estimated Savings & Opportunities

All Lighthouse-surfaced opportunities and diagnostics, sorted by estimated time saving (highest first). Each entry includes:

- Opportunity name
- Estimated time saving (ms)
- Estimated byte saving (KB)
- Affected resources
- Recommended fix

Covers areas such as render-blocking resources, unused JS/CSS, image optimisation, text compression, CDN usage, HTTP/2, preloading, and more.

### Appendix
Raw Lighthouse category scores table (Performance, Accessibility, Best Practices, SEO).

---

## MCP Server

The plugin registers the `lighthouse` MCP server defined in `.mcp.json`:

```json
{
  "mcpServers": {
    "lighthouse": {
      "command": "npx",
      "args": ["lighthouse-mcp"]
    }
  }
}
```

This server exposes Lighthouse audit capabilities as MCP tools that the `perf-report` agent calls directly within Claude Code.

---

## Hooks

### Lighthouse Validation Hook

**Trigger:** `PreToolUse` — fires before any `mcp__lighthouse__*` tool call
**Script:** `scripts/validate-lighthouse.sh`
**Blocking:** Yes — the tool call is blocked until the script exits successfully

#### What the script does

```
lighthouse --version
       │
       ├── returns valid semver (e.g. 12.3.0)
       │         └── Proceeds ✓
       │
       └── not found / unexpected output
                 └── npm install -g lighthouse
                           │
                           ├── success → re-validates → Proceeds ✓
                           └── failure → exits 1, prints manual install instructions ✗
```

#### OS-specific behaviour

| OS | Lighthouse binary | npm binary | Elevation |
|---|---|---|---|
| Linux | `lighthouse` | `npm` | `sudo` when global prefix is restricted |
| macOS | `lighthouse` | `npm` | `sudo` when global prefix is restricted |
| Windows | `lighthouse.cmd` | `npm.cmd` | PowerShell `RunAs` fallback |

OS is detected via `uname -s` with a fallback to the `$OS` environment variable for Windows native shells.

---

## Configuration Reference

### `.claude-plugin/plugin.json`

```json
{
  "name": "end-user-perf",
  "version": "1.0.0",
  "description": "Plugin to evaluate and report end user performance report of the web applications",
  "author": { "name": "Surendran E" },
  "license": "MIT",
  "keywords": ["performance", "web", "end-user", "reporting", "metrics"],
  "agents":   "./agents/",
  "hooks":    "./hooks/hooks.json",
  "mcpServers": "./.mcp.json"
}
```

### `.mcp.json`

Defines the Lighthouse MCP server. No additional configuration needed.

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `Lighthouse installation failed` | npm not on PATH | Install Node.js from https://nodejs.org |
| `ERROR: binary not found on PATH` | Global npm bin dir not on PATH | Add npm global bin to PATH: `npm config get prefix` |
| Hook times out | Slow network during install | Increase hook timeout in `hooks/hooks.json` (`timeout` field, value in ms) |
| PDF not generated | Missing PDF writer dependency | Ensure the `pdfkit` or equivalent library is available in the environment |
| Audit returns empty results | URL requires authentication | Use a publicly accessible URL or configure Lighthouse auth headers |
| Windows elevation prompt blocked | Group policy | Run Claude Code as Administrator |

---

## License

MIT © Surendran E
