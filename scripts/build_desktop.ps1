param(
    [switch]$SkipAssets,
    [switch]$SkipRelease
)

$ErrorActionPreference = "Stop"

Write-Host "==> Packaging RxGenerator Desktop Application" -ForegroundColor Cyan

$env:MIX_ENV = "prod"

if (-not $env:DATABASE_PATH) {
    $env:DATABASE_PATH = Join-Path (Get-Location) "priv\repo\seeds\rx_generator_seed.db"
}

if (-not $env:SECRET_KEY_BASE) {
    $env:SECRET_KEY_BASE = "rx_generator_build_time_placeholder_key_rx_generator_build_time_placeholder_key_"
}

Write-Host "==> Compiling production release artifacts..." -ForegroundColor Yellow
mix compile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $SkipAssets) {
    Write-Host "==> Deploying assets..." -ForegroundColor Yellow
    mix assets.deploy
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $SkipRelease) {
    Write-Host "==> Building Mix release..." -ForegroundColor Yellow
    mix release rx_generator --overwrite
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$runnerScript = Join-Path (Join-Path "native_runner" "windows") "build_runner.ps1"
if (Test-Path $runnerScript) {
    Write-Host "==> Compiling native Windows runner..." -ForegroundColor Yellow
    & powershell -ExecutionPolicy Bypass -File $runnerScript
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "==> Desktop packaging completed successfully!" -ForegroundColor Green
