# Rebuild cli-proxy-api.exe for Windows/amd64 with the bundled MinGW toolchain.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\build-local.ps1
#
# The version string is taken from the nearest git tag, so after rebasing onto a
# newer upstream release the rebuild reports that release automatically.
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot

$running = Get-Process -Name "cli-proxy-api" -ErrorAction SilentlyContinue
if ($running) {
    throw "cli-proxy-api.exe is running; stop it before rebuilding"
}

$mingw = Join-Path $root ".toolchain\mingw64\bin"
if (-not (Test-Path (Join-Path $mingw "gcc.exe"))) {
    throw "missing C compiler: $(Join-Path $mingw 'gcc.exe')"
}

$env:PATH = "$mingw;$env:PATH"
$env:CGO_ENABLED = "1"
$env:GOOS = "windows"
$env:GOARCH = "amd64"
if (-not $env:GOPROXY) {
    $env:GOPROXY = "https://goproxy.cn,direct"
}

Push-Location $root
try {
    $version = (git describe --tags --abbrev=0 2>$null)
    if ($version) { $version = $version.Trim().TrimStart("v") } else { $version = "dev" }
    $commit = (git rev-parse --short HEAD 2>$null)
    if (-not $commit) { $commit = "none" }
    $buildDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $out = Join-Path $root "cli-proxy-api.exe"
    go build -ldflags="-s -w -X main.Version=$version -X main.Commit=$commit -X main.BuildDate=$buildDate" -o $out ./cmd/server
    if ($LASTEXITCODE -ne 0) {
        throw "go build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host "built $out (Version=$version Commit=$commit BuildDate=$buildDate)"
