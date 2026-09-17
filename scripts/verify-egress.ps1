# C+D egress identity probe: read-only; no global mode, named pipe, or config writes.
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-egress.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-egress.ps1 -ExpectedMatchIp <VPS_IP>

[CmdletBinding()]
param(
    [string]$Proxy = "http://127.0.0.1:7897",
    [string]$ExpectedMatchIp
)

$ErrorActionPreference = "Stop"
$curl = Get-Command curl.exe -ErrorAction Stop
$failures = 0

function Invoke-Body {
    param([Parameter(Mandatory)][string]$Url)
    try {
        return ((& $curl.Source -4 --ssl-no-revoke --silent --show-error --max-time 20 -x $Proxy $Url 2>$null) -join "`n")
    } catch {
        return ""
    }
}

function Invoke-Status {
    param([Parameter(Mandatory)][string]$Url)
    try {
        $status = & $curl.Source -4 --ssl-no-revoke --silent --show-error --max-time 20 -o NUL -w "%{http_code}" -x $Proxy $Url 2>$null
        if ($LASTEXITCODE -ne 0) { return "000" }
        return ([string]$status).Trim()
    } catch {
        return "000"
    }
}

function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) {
        Write-Host "[OK]   $Name - $Detail" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Name - $Detail" -ForegroundColor Red
        $script:failures++
    }
}

Write-Host "C+D egress identity probe (read-only; proxy: $Proxy)" -ForegroundColor Cyan

# chatgpt.com must route to MIYA-STATIC; do not print the actual egress IP.
$trace = [string](Invoke-Body "https://chatgpt.com/cdn-cgi/trace")
$traceLoc = [regex]::Match($trace, "(?m)^loc=(.+)$").Groups[1].Value.Trim()
$traceIp = [regex]::Match($trace, "(?m)^ip=(.+)$").Groups[1].Value.Trim()
$residentialOk = ($traceLoc -eq "JP" -and -not ([string]::IsNullOrWhiteSpace($traceIp)))
if ($residentialOk) {
    Report "MIYA-STATIC / ChatGPT" $true "loc=JP; egress IP present"
} else {
    Report "MIYA-STATIC / ChatGPT" $false "loc=JP or egress IP missing"
}

$xStatus = Invoke-Status "https://x.com/"
Report "MIYA-STATIC / x.com" ($xStatus -match "^(200|3[0-9][0-9])$") "HTTP $xStatus"

$twitterStatus = Invoke-Status "https://twitter.com/"
Report "MIYA-STATIC / twitter.com" ($twitterStatus -match "^(200|3[0-9][0-9])$") "HTTP $twitterStatus"

# api.ipify.org must hit MATCH and normally return the self-hosted VPS; compare in memory only.
$matchIp = [string](Invoke-Body "https://api.ipify.org")
$matchIp = $matchIp.Trim()
if ([string]::IsNullOrWhiteSpace($ExpectedMatchIp)) {
    $matchAvailable = -not ([string]::IsNullOrWhiteSpace($matchIp))
    Report "Redundancy / MATCH" $matchAvailable "egress IP present; expected value not supplied"
} else {
    $expectedIp = $ExpectedMatchIp.Trim()
    $matchIdentityOk = ($matchIp -eq $expectedIp)
    Report "Redundancy / MATCH" $matchIdentityOk "egress identity matches expected value"
}

$baiduStatus = Invoke-Status "https://www.baidu.com/"
Report "Domestic / Baidu" ($baiduStatus -eq "200") "HTTP $baiduStatus"

if ($failures -gt 0) {
    Write-Host "Probe failures: $failures; do not auto-switch residential/VPS roles." -ForegroundColor Yellow
    exit 1
}

Write-Host "All read-only probes passed; Clash configuration was not modified." -ForegroundColor Green
exit 0
