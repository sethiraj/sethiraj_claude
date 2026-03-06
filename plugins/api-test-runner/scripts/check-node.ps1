# ─────────────────────────────────────────────────────────────────────────────
# check-node.ps1
# Windows PowerShell fallback: verifies Node.js is installed; installs via
# winget → Chocolatey → direct MSI download (in that priority order).
# Also runs `npm install` in the plugin directory if node_modules is absent.
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # faster Invoke-WebRequest

$BANNER       = "[api-test-runner]"
$MIN_MAJOR    = 18
$LTS_VERSION  = "20.18.0"
$LTS_MSI_URL  = "https://nodejs.org/dist/v${LTS_VERSION}/node-v${LTS_VERSION}-x64.msi"

# ── Resolve plugin root ────────────────────────────────────────────────────────
$PLUGIN_ROOT = if ($env:CLAUDE_PLUGIN_ROOT) {
    $env:CLAUDE_PLUGIN_ROOT
} else {
    (Split-Path -Parent $PSScriptRoot)
}

# ── Colour helpers ─────────────────────────────────────────────────────────────
function Write-OK    { param($Msg) Write-Host "$BANNER $Msg" -ForegroundColor Green  }
function Write-Warn  { param($Msg) Write-Host "$BANNER $Msg" -ForegroundColor Yellow }
function Write-Err   { param($Msg) Write-Host "$BANNER $Msg" -ForegroundColor Red    }
function Write-Info  { param($Msg) Write-Host "$BANNER $Msg"                         }

# ── Reload PATH from registry (picks up newly installed tools) ─────────────────
function Refresh-EnvPath {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine") -split ";"
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")    -split ";"
    $env:Path = ($machine + $user | Where-Object { $_ } | Select-Object -Unique) -join ";"
}

# ── Check Node version ─────────────────────────────────────────────────────────
function Test-NodeVersion {
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    try {
        $raw = & node -e "process.stdout.write(String(process.version))" 2>$null
        $major = [int]($raw -replace '[^0-9.].*' -replace '^v' -split '\.')[0]
        return ($major -ge $MIN_MAJOR)
    } catch { return $false }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — Node.js check / install
# ─────────────────────────────────────────────────────────────────────────────

Refresh-EnvPath

if (Test-NodeVersion) {
    $ver = & node --version
    Write-OK "✓ Node.js $ver detected"
} else {
    Write-Warn "Node.js >= v${MIN_MAJOR} not found — attempting installation…"
    $installed = $false

    # ── Try winget (Windows 10 1709+, Windows 11) ──────────────────────────────
    if (-not $installed -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Info "Trying winget…"
        try {
            $result = Start-Process -FilePath "winget" `
                -ArgumentList @(
                    "install", "OpenJS.NodeJS.LTS",
                    "--accept-source-agreements",
                    "--accept-package-agreements",
                    "--silent"
                ) -Wait -PassThru -NoNewWindow
            if ($result.ExitCode -eq 0) { $installed = $true }
        } catch { Write-Warn "winget failed: $_" }
        Refresh-EnvPath
    }

    # ── Try Chocolatey ────────────────────────────────────────────────────────
    if (-not $installed -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Info "Trying Chocolatey…"
        try {
            choco install nodejs-lts --yes --no-progress 2>&1 | Out-Null
            $installed = $true
        } catch { Write-Warn "choco failed: $_" }
        Refresh-EnvPath
    }

    # ── Try Scoop ────────────────────────────────────────────────────────────
    if (-not $installed -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Info "Trying Scoop…"
        try {
            scoop install nodejs-lts 2>&1 | Out-Null
            $installed = $true
        } catch { Write-Warn "scoop failed: $_" }
        Refresh-EnvPath
    }

    # ── Direct MSI download (last resort) ────────────────────────────────────
    if (-not $installed) {
        Write-Info "Downloading Node.js v${LTS_VERSION} MSI installer…"
        $msiPath = Join-Path $env:TEMP "nodejs-lts-installer.msi"
        try {
            Invoke-WebRequest -Uri $LTS_MSI_URL -OutFile $msiPath -UseBasicParsing
            Write-Info "Running installer (this may take a minute)…"
            $r = Start-Process -FilePath "msiexec.exe" `
                -ArgumentList "/i `"$msiPath`" /quiet /qn ADDLOCAL=ALL" `
                -Wait -PassThru
            Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
            if ($r.ExitCode -eq 0) { $installed = $true }
            else { Write-Warn "MSI installer exited with code $($r.ExitCode)" }
        } catch {
            Write-Warn "MSI download/install failed: $_"
        }
        Refresh-EnvPath
    }

    if (Test-NodeVersion) {
        $ver = & node --version
        Write-OK "✓ Node.js $ver installed successfully"
    } else {
        Write-Err "✗ Could not install Node.js automatically."
        Write-Err "  Please install Node.js v${MIN_MAJOR}+ from: https://nodejs.org"
        Write-Err "  Restart your terminal after installation and try again."
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — Install npm dependencies if node_modules is missing
# ─────────────────────────────────────────────────────────────────────────────

$pkgJson    = Join-Path $PLUGIN_ROOT "package.json"
$nodeModules= Join-Path $PLUGIN_ROOT "node_modules"
$pwDir      = Join-Path $nodeModules "playwright"

if ((Test-Path $pkgJson) -and (-not (Test-Path $nodeModules))) {
    Write-Warn "node_modules not found — running npm install…"
    Push-Location $PLUGIN_ROOT
    try {
        npm install --prefer-offline --no-audit --no-fund 2>&1
        Write-OK "✓ Dependencies installed"
    } finally { Pop-Location }
} elseif ((Test-Path $pkgJson) -and (-not (Test-Path $pwDir))) {
    Write-Warn "playwright package missing — running npm install…"
    Push-Location $PLUGIN_ROOT
    try {
        npm install --prefer-offline --no-audit --no-fund 2>&1
        Write-OK "✓ Dependencies installed"
    } finally { Pop-Location }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — Install Playwright browser binaries if needed
# ─────────────────────────────────────────────────────────────────────────────

$pwInstalled = Join-Path $nodeModules ".playwright-installed"

if ((Test-Path $pwDir) -and (-not (Test-Path $pwInstalled))) {
    Write-Warn "Installing Playwright browser binaries (first-time setup)…"
    Push-Location $PLUGIN_ROOT
    try {
        node node_modules/.bin/playwright install chromium 2>&1
        New-Item -ItemType File -Path $pwInstalled -Force | Out-Null
        Write-OK "✓ Playwright browsers ready"
    } catch {
        Write-Warn "Playwright browser install skipped: $_"
    } finally { Pop-Location }
}

Write-OK "✓ Environment ready — api-test-runner is good to go"
