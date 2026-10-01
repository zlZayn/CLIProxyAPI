# Pull the newest upstream release, re-apply this branch's local commits, and rebuild the exe.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\update-upstream.ps1
#
# github.com is not reachable directly on this machine, so the fetch goes through the
# local proxy (Clash/mihomo mixed port).
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$proxy = "http://127.0.0.1:7897"

Push-Location $root
try {
    $branch = (git rev-parse --abbrev-ref HEAD)
    if ($branch -eq "HEAD") {
        throw "detached HEAD. Run 'git switch local-autobrowser' first"
    }

    Write-Host "fetching upstream tags ..."
    git -c http.proxy=$proxy fetch upstream --tags
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }

    $tag = (git tag --list "v*" --sort=-v:refname | Select-Object -First 1)
    if (-not $tag) { throw "no upstream release tag found" }
    Write-Host "newest upstream release: $tag"

    Write-Host "rebasing $branch onto $tag ..."
    git rebase $tag
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Rebase stopped. To finish after fixing the files: git rebase --continue" -ForegroundColor Yellow
        Write-Host "To undo everything:                                git rebase --abort" -ForegroundColor Yellow
        exit 1
    }
} finally {
    Pop-Location
}

& (Join-Path $root "build-local.ps1")
