param(
    [switch]$SkipAssets,
    [switch]$SkipRelease
)

$ErrorActionPreference = "Stop"

Write-Host "==> Packaging RxGenerator Desktop Application" -ForegroundColor Cyan

$env:MIX_ENV = "prod"

if (-not $SkipAssets) {
    Write-Host "==> Deploying assets..." -ForegroundColor Yellow
    mix assets.deploy
}

if (-not $SkipRelease) {
    Write-Host "==> Building Mix release..." -ForegroundColor Yellow
    mix release rx_generator --overwrite
}

$runnerScript = Join-Path "native_runner" "windows" "build_runner.ps1"
if (Test-Path $runnerScript) {
    Write-Host "==> Compiling native Windows runner..." -ForegroundColor Yellow
    & powershell -ExecutionPolicy Bypass -File $runnerScript
}

Write-Host "==> Desktop packaging completed successfully!" -ForegroundColor Green

