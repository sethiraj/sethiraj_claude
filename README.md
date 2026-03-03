# Sethiraj Claude Plugin Marketplace

> Curated Claude Code plugins by **Surendran E** — focused on test automation, web performance, and AI-assisted engineering.

**GitHub:** [github.com/sethiraj](https://github.com/sethiraj)

---

## Installing a Plugin

```bash
claude plugin add <repository-url>
```

Example:

```bash
claude plugin add https://github.com/sethiraj/claude_lighthouse_plugin
```

---

## Available Plugins

### end-user-perf

> Evaluate and report end-user performance of web applications

| Field | Value |
|---|---|
| Version | 1.0.0 |
| Author | Surendran E |
| License | MIT |
| Repository | [sethiraj/claude_lighthouse_plugin](https://github.com/sethiraj/claude_lighthouse_plugin) |

**Install:**
```bash
claude plugin add https://github.com/sethiraj/claude_lighthouse_plugin
```

**What it does:**
Runs a Google Lighthouse audit on any URL and generates a structured PDF report covering:
- Web Core Vitals (LCP, INP, CLS, FCP, TTFB, TBT, Speed Index)
- Network Analysis (latency, RTT, throughput, MIME-type breakdown)
- Estimated Savings & Opportunities (prioritised by time/byte savings)

**Requirements:** Node.js ≥ 18, npm ≥ 8 *(Lighthouse is auto-installed if missing)*

**Usage inside Claude Code:**
```
Analyze https://example.com and generate a performance report
```

---

## Marketplace Registry

The full plugin registry is in [`index.json`](./index.json).
Each plugin has a dedicated entry under [`plugins/<name>/entry.json`](./plugins/).

---

## Contributing

To submit a plugin to this marketplace:

1. Build your plugin following the [Claude Code Plugin documentation](https://docs.claude.ai/code/plugins)
2. Host it on a public GitHub repository
3. Open an issue or pull request with your plugin's `entry.json`

---

## License

MIT © Surendran E
