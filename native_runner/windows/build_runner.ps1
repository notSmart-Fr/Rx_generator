param(
    [string]$OutDir = "_build/prod/rel/rx_generator/bin"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

if (-not (Test-Path $csc)) {
    throw "Standard C# compiler (csc.exe) not found on host."
}

$source = Join-Path $PSScriptRoot "RxGeneratorApp.cs"
$output = Join-Path $OutDir "RxGeneratorApp.exe"

Write-Host "==> Compiling native Windows supervisor runner: $output" -ForegroundColor Cyan

& $csc /target:winexe /out:"$output" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "$source"

if ($LASTEXITCODE -ne 0) {
    throw "Failed to compile RxGeneratorApp.exe"
}

Write-Host "==> Native Windows runner compiled successfully: $output" -ForegroundColor Green

