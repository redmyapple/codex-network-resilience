# sync.ps1
# 一键同步本仓库：git add -A + commit + push
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $repo
try {
    git add -A
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "No changes to commit."
        exit 0
    }
    git commit -m "sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    git push
    Write-Host "Synced."
}
finally {
    Pop-Location
}