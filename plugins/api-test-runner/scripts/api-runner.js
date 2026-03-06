#!/usr/bin/env node
/**
 * api-runner.js — Playwright-based API test executor
 * Supports OpenAPI 2.x (Swagger) and 3.x specifications
 *
 * Usage:
 *   node api-runner.js --spec <path> --method <METHOD> --endpoint <path> [options]
 */

'use strict';

const { request } = require('playwright');
const fs = require('fs');
const path = require('path');

// ─── Argument Parsing ──────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {
    spec: null,
    method: 'GET',
    endpoint: null,
    paramsFile: null,
    inlineParams: null,
    authUrl: null,
    authBody: null,
    authBodyFile: null,
    baseUrl: null,
    token: null,
    contentType: 'application/json',
    headers: {},
    verbose: false,
    report: false,
    dashboardUrl: null,
  };

  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--spec':           args.spec = argv[++i]; break;
      case '--method':         args.method = argv[++i].toUpperCase(); break;
      case '--endpoint':       args.endpoint = argv[++i]; break;
      case '--params-file':    args.paramsFile = argv[++i]; break;
      case '--params':         args.inlineParams = argv[++i]; break;
      case '--auth-url':       args.authUrl = argv[++i]; break;
      case '--auth-body':      args.authBody = argv[++i]; break;
      case '--auth-body-file': args.authBodyFile = argv[++i]; break;
      case '--base-url':       args.baseUrl = argv[++i]; break;
      case '--token':          args.token = argv[++i]; break;
      case '--content-type':   args.contentType = argv[++i]; break;
      case '--verbose':        args.verbose = true; break;
      case '--report':         args.report = true; break;
      case '--dashboard-url':  args.dashboardUrl = argv[++i]; break;
      case '--header': {
        const raw = argv[++i];
        const colon = raw.indexOf(':');
        if (colon !== -1) {
          args.headers[raw.slice(0, colon).trim()] = raw.slice(colon + 1).trim();
        }
        break;
      }
      default:
        if (argv[i].startsWith('--')) {
          console.warn(`Warning: unknown option ${argv[i]}`);
        }
    }
  }

  return args;
}

// ─── Spec Parsing ──────────────────────────────────────────────────────────────

function readSpec(specPath) {
  if (!specPath) throw new Error('--spec <path> is required');
  const abs = path.resolve(specPath);
  if (!fs.existsSync(abs)) throw new Error(`Spec file not found: ${abs}`);

  const content = fs.readFileSync(abs, 'utf-8');

  // Try JSON first
  try {
    return JSON.parse(content);
  } catch (_) {}

  // Fall back to YAML
  try {
    // eslint-disable-next-line
    const yaml = require('js-yaml');
    return yaml.load(content);
  } catch (e) {
    if (e.code === 'MODULE_NOT_FOUND') {
      throw new Error(
        'Spec file appears to be YAML but js-yaml is not installed.\n' +
        'Run: npm install js-yaml   (in the plugin root)'
      );
    }
    throw new Error(`Failed to parse spec file: ${e.message}`);
  }
}

function extractBaseUrl(spec) {
  // OpenAPI 3.x
  if (spec.openapi && spec.servers && spec.servers.length > 0) {
    return spec.servers[0].url.replace(/\/$/, '');
  }
  // Swagger 2.x
  if (spec.swagger) {
    const scheme = (spec.schemes && spec.schemes[0]) || 'https';
    const host = spec.host || 'localhost';
    const basePath = (spec.basePath || '').replace(/\/$/, '');
    return `${scheme}://${host}${basePath}`;
  }
  throw new Error(
    'Cannot determine base URL from spec. Provide --base-url <url>'
  );
}

function hasSecurityRequirement(spec, method, endpointPath) {
  // Check endpoint-level security first
  const operation = getOperation(spec, method, endpointPath);
  if (operation && Array.isArray(operation.security)) {
    return operation.security.length > 0;
  }
  // Fall back to global security
  if (Array.isArray(spec.security)) {
    return spec.security.length > 0;
  }
  // Check if any security schemes are defined (conservative: assume required)
  return hasAnySecurityScheme(spec);
}

function hasAnySecurityScheme(spec) {
  if (spec.components && spec.components.securitySchemes) {
    return Object.keys(spec.components.securitySchemes).length > 0;
  }
  if (spec.securityDefinitions) {
    return Object.keys(spec.securityDefinitions).length > 0;
  }
  return false;
}

function getTokenUrlFromSpec(spec) {
  // OpenAPI 3.x — oauth2 flows
  if (spec.components && spec.components.securitySchemes) {
    for (const scheme of Object.values(spec.components.securitySchemes)) {
      if (scheme.type === 'oauth2' && scheme.flows) {
        const flows = scheme.flows;
        return (
          (flows.clientCredentials && flows.clientCredentials.tokenUrl) ||
          (flows.password && flows.password.tokenUrl) ||
          (flows.authorizationCode && flows.authorizationCode.tokenUrl) ||
          null
        );
      }
    }
  }
  // Swagger 2.x
  if (spec.securityDefinitions) {
    for (const scheme of Object.values(spec.securityDefinitions)) {
      if (scheme.type === 'oauth2' && scheme.tokenUrl) return scheme.tokenUrl;
    }
  }
  return null;
}

function getOperation(spec, method, endpointPath) {
  const paths = spec.paths || {};
  const pathItem = paths[endpointPath];
  if (!pathItem) return null;
  return pathItem[method.toLowerCase()] || null;
}

// ─── Parameter Resolution ──────────────────────────────────────────────────────

function readJsonFile(filePath, label) {
  const abs = path.resolve(filePath);
  if (!fs.existsSync(abs)) throw new Error(`${label} file not found: ${abs}`);
  const content = fs.readFileSync(abs, 'utf-8');
  try {
    return JSON.parse(content);
  } catch (e) {
    throw new Error(`${label} file is not valid JSON (${filePath}): ${e.message}`);
  }
}

function buildRequestParts(spec, method, endpointPath, params) {
  const operation = getOperation(spec, method, endpointPath);
  const queryParams = {};
  const pathParams = {};
  const categorized = new Set();

  if (operation && Array.isArray(operation.parameters)) {
    for (const param of operation.parameters) {
      const value = params[param.name];
      if (value !== undefined) {
        if (param.in === 'query') {
          queryParams[param.name] = String(value);
          categorized.add(param.name);
        } else if (param.in === 'path') {
          pathParams[param.name] = String(value);
          categorized.add(param.name);
        }
      }
    }
  }

  // Also pull path params from URL template for any not yet categorized
  const templateParams = (endpointPath.match(/\{(\w+)\}/g) || []).map(p => p.slice(1, -1));
  for (const name of templateParams) {
    if (params[name] !== undefined && !pathParams[name]) {
      pathParams[name] = String(params[name]);
      categorized.add(name);
    }
  }

  // Remaining params → body for mutating methods, query for read methods
  const remaining = Object.fromEntries(
    Object.entries(params).filter(([k]) => !categorized.has(k))
  );

  let body = null;
  if (['POST', 'PUT', 'PATCH'].includes(method)) {
    if (Object.keys(remaining).length > 0) body = remaining;
  } else {
    Object.assign(queryParams, remaining);
  }

  return { queryParams, pathParams, body };
}

function resolvePathParams(endpointPath, pathParams) {
  return endpointPath.replace(/\{(\w+)\}/g, (match, name) => {
    if (pathParams[name] === undefined) {
      console.warn(`  Warning: path parameter {${name}} has no value — leaving as-is`);
      return match;
    }
    return encodeURIComponent(pathParams[name]);
  });
}

// ─── Authentication ────────────────────────────────────────────────────────────

async function acquireToken(authUrl, authBody, authBodyFile, spec, baseUrl) {
  let tokenUrl = authUrl;

  if (!tokenUrl) {
    tokenUrl = getTokenUrlFromSpec(spec);
    if (!tokenUrl) {
      console.warn('[Auth] Could not determine token URL from spec. Skipping token acquisition.');
      return null;
    }
    // Resolve relative token URLs against base URL
    if (!tokenUrl.startsWith('http')) {
      tokenUrl = baseUrl.replace(/\/$/, '') + '/' + tokenUrl.replace(/^\//, '');
    }
  }

  let credentials = {};
  if (authBodyFile) {
    credentials = readJsonFile(authBodyFile, 'Auth credentials');
  } else if (authBody) {
    try {
      credentials = JSON.parse(authBody);
    } catch (e) {
      throw new Error(`--auth-body is not valid JSON: ${e.message}`);
    }
  }

  console.log(`\n[Auth] Acquiring bearer token`);
  console.log(`       POST ${tokenUrl}`);

  const ctx = await request.newContext();
  try {
    const response = await ctx.post(tokenUrl, {
      data: credentials,
      headers: { 'Content-Type': 'application/json' },
    });

    let body;
    try {
      body = await response.json();
    } catch (_) {
      body = await response.text();
    }

    if (!response.ok()) {
      console.error(`[Auth] Token request failed: ${response.status()} ${response.statusText()}`);
      console.error('[Auth] Response:', JSON.stringify(body, null, 2));
      return null;
    }

    // Common token field names across providers
    const token =
      body.access_token ||
      body.token ||
      body.id_token ||
      body.authToken ||
      body.jwt ||
      body.bearerToken;

    if (!token) {
      console.warn('[Auth] Token field not found in response. Available keys:', Object.keys(body).join(', '));
      console.warn('[Auth] Full response:', JSON.stringify(body, null, 2));
      return null;
    }

    console.log('[Auth] Token acquired successfully');
    return token;
  } finally {
    await ctx.dispose();
  }
}

// ─── API Execution ─────────────────────────────────────────────────────────────

async function executeApiCall({ baseUrl, method, endpointPath, queryParams, body, token, extraHeaders, contentType }) {
  const headers = { ...extraHeaders };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (body !== null && ['POST', 'PUT', 'PATCH'].includes(method)) {
    headers['Content-Type'] = contentType || 'application/json';
  }

  const fullUrl = baseUrl.replace(/\/$/, '') + endpointPath;

  console.log(`\n[Request] ${method} ${fullUrl}`);
  if (Object.keys(queryParams).length > 0) {
    console.log('[Query]  ', JSON.stringify(queryParams));
  }
  if (body !== null) {
    console.log('[Body]   ', JSON.stringify(body, null, 2));
  }

  // Log headers with token redacted
  const logHeaders = { ...headers };
  if (logHeaders['Authorization']) logHeaders['Authorization'] = 'Bearer ***';
  if (Object.keys(logHeaders).length > 0) {
    console.log('[Headers]', JSON.stringify(logHeaders));
  }

  const ctx = await request.newContext({ baseURL: baseUrl });
  try {
    const options = { headers, params: queryParams };
    if (body !== null && ['POST', 'PUT', 'PATCH'].includes(method)) {
      options.data = body;
    }

    const t0 = Date.now();
    const response = await ctx[method.toLowerCase()](endpointPath, options);
    const duration = Date.now() - t0;

    let responseBody;
    const ct = response.headers()['content-type'] || '';
    if (ct.includes('application/json')) {
      try { responseBody = await response.json(); } catch (_) { responseBody = await response.text(); }
    } else {
      responseBody = await response.text();
    }

    return {
      status: response.status(),
      statusText: response.statusText(),
      headers: response.headers(),
      body: responseBody,
      duration,
      url: fullUrl,
      method,
    };
  } finally {
    await ctx.dispose();
  }
}

// ─── Output Formatting ─────────────────────────────────────────────────────────

function printResult(result) {
  const divider = '─'.repeat(60);
  const passed = result.status >= 200 && result.status < 300;
  const icon = passed ? '✅ PASS' : '❌ FAIL';

  console.log(`\n${divider}`);
  console.log(`[Response] ${result.status} ${result.statusText}  (${result.duration}ms)`);
  console.log(`[Body]`);
  if (typeof result.body === 'object') {
    console.log(JSON.stringify(result.body, null, 2));
  } else {
    console.log(result.body);
  }
  console.log(`\n${divider}`);
  console.log(`[Result]   ${icon}`);
  console.log(`[URL]      ${result.url}`);
  console.log(`[Duration] ${result.duration}ms`);
  console.log(divider);

  return passed;
}

function printUsage() {
  console.log('Usage: node api-runner.js --spec <path> --method <METHOD> --endpoint <path> [options]');
  console.log('');
  console.log('Required:');
  console.log('  --spec <path>            Path to OpenAPI/Swagger spec (JSON or YAML)');
  console.log('  --method <METHOD>        HTTP method: GET, POST, PUT, DELETE, PATCH');
  console.log('  --endpoint <path>        API path from spec (e.g. /users/{id})');
  console.log('');
  console.log('Parameters:');
  console.log('  --params-file <path>     JSON file with request parameters (body or query)');
  console.log('  --params <json>          Inline JSON parameters string');
  console.log('');
  console.log('Authentication:');
  console.log('  --auth-url <url>         Token endpoint URL (overrides spec)');
  console.log('  --auth-body-file <path>  JSON file with auth credentials');
  console.log('  --auth-body <json>       Inline JSON auth credentials');
  console.log('  --token <token>          Pre-existing bearer token (skips auth call)');
  console.log('');
  console.log('Request options:');
  console.log('  --base-url <url>         Override base URL from spec');
  console.log('  --header <Key: Value>    Additional request header (repeatable)');
  console.log('  --content-type <type>    Content-Type for body (default: application/json)');
  console.log('  --verbose                Show extra debug information');
}

// ─── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.spec || !args.endpoint) {
    printUsage();
    process.exit(1);
  }

  // 1. Read and validate spec
  const spec = readSpec(args.spec);
  const apiTitle = (spec.info && spec.info.title) || 'Unknown API';
  const apiVersion = (spec.info && spec.info.version) || '?';
  console.log(`[Spec]    ${apiTitle} v${apiVersion}`);
  console.log(`[Spec]    File: ${path.resolve(args.spec)}`);

  // 2. Determine base URL
  const baseUrl = args.baseUrl || extractBaseUrl(spec);
  console.log(`[Base URL] ${baseUrl}`);

  // 3. Load parameters (from file or inline)
  let params = {};
  if (args.paramsFile) {
    params = readJsonFile(args.paramsFile, 'Params');
    console.log(`[Params]  Loaded from ${args.paramsFile}`);
    if (args.verbose) console.log('[Params]  ', JSON.stringify(params, null, 2));
  } else if (args.inlineParams) {
    try {
      params = JSON.parse(args.inlineParams);
    } catch (e) {
      throw new Error(`--params is not valid JSON: ${e.message}`);
    }
  }

  // 4. Resolve request parts from spec and params
  const { queryParams, pathParams, body } = buildRequestParts(spec, args.method, args.endpoint, params);
  const resolvedEndpoint = resolvePathParams(args.endpoint, pathParams);

  // 5. Acquire bearer token if needed
  let token = args.token;
  if (!token) {
    const needsAuth = hasSecurityRequirement(spec, args.method, args.endpoint);
    if (needsAuth || args.authUrl || args.authBodyFile || args.authBody) {
      token = await acquireToken(args.authUrl, args.authBody, args.authBodyFile, spec, baseUrl);
    }
  } else {
    console.log('[Auth]    Using pre-provided token');
  }

  // 6. Execute the API call
  const result = await executeApiCall({
    baseUrl,
    method: args.method,
    endpointPath: resolvedEndpoint,
    queryParams,
    body,
    token,
    extraHeaders: args.headers,
    contentType: args.contentType,
  });

  // 7. Print and exit
  const passed = printResult(result);

  // 8. Persist result if --report flag set
  if (args.report) {
    await persistResult({
      timestamp:  new Date().toISOString(),
      spec:       path.resolve(args.spec),
      specName:   path.basename(args.spec),
      method:     args.method,
      endpoint:   resolvedEndpoint,
      baseUrl,
      status:     result.status,
      statusText: result.statusText,
      duration:   result.duration,
      passed,
      body:       result.body,
      error:      passed ? null : `HTTP ${result.status} ${result.statusText}`,
      stackTrace: null,
    }, args.dashboardUrl);
  }

  process.exit(passed ? 0 : 1);
}

// ─── Reporting ─────────────────────────────────────────────────────────────────

async function persistResult(entry, dashboardUrl) {
  // Always write to local history file
  const resultsDir  = path.join(__dirname, '..', 'results');
  const historyFile = path.join(resultsDir, 'history.json');

  if (!fs.existsSync(resultsDir)) fs.mkdirSync(resultsDir, { recursive: true });

  let history = [];
  if (fs.existsSync(historyFile)) {
    try { history = JSON.parse(fs.readFileSync(historyFile, 'utf-8')); } catch (_) {}
  }

  entry.id = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
  history.unshift(entry);
  if (history.length > 500) history.splice(500);
  fs.writeFileSync(historyFile, JSON.stringify(history, null, 2));

  // Write a marker file that the post-run-notify hook uses for reliable detection
  fs.writeFileSync(path.join(resultsDir, '.last-run'), entry.id);

  console.log(`[Report]  Saved to ${historyFile}`);

  // Optionally POST to a running dashboard server
  const url = dashboardUrl || 'http://localhost:3737';
  try {
    const http = require('http');
    const payload = JSON.stringify(entry);
    await new Promise((resolve) => {
      const req = http.request(`${url}/api/results`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
        timeout: 2000,
      }, (res) => { res.resume(); resolve(); });
      req.on('error', () => resolve()); // dashboard not running — that's OK
      req.write(payload);
      req.end();
    });
  } catch (_) { /* dashboard server optional */ }
}

main().catch(async err => {
  console.error('\n[Error]', err.message);
  if (process.env.DEBUG || process.argv.includes('--verbose')) {
    console.error(err.stack);
  }

  // Persist failure with stack trace if --report was requested
  const args = parseArgs(process.argv.slice(2));
  if (args.report && args.spec && args.endpoint) {
    const resolvedEndpoint = args.endpoint;
    let baseUrl = args.baseUrl || '(unknown)';
    try {
      const spec = readSpec(args.spec);
      baseUrl = args.baseUrl || extractBaseUrl(spec);
    } catch (_) {}

    await persistResult({
      timestamp:  new Date().toISOString(),
      spec:       path.resolve(args.spec),
      specName:   path.basename(args.spec),
      method:     args.method,
      endpoint:   resolvedEndpoint,
      baseUrl,
      status:     0,
      statusText: 'Error',
      duration:   0,
      passed:     false,
      body:       null,
      error:      err.message,
      stackTrace: err.stack,
    }, args.dashboardUrl).catch(() => {});
  }

  process.exit(1);
});
