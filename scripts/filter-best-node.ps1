# Compatibility entry point: node selection is now read-only.
# The old version changed global mode, called PUT /proxies, and edited runtime config.
# Use verify-egress.ps1 to audit the current routing.

[CmdletBinding()]
param(
    [string]$Proxy = "http://127.0.0.1:7897",
    [string]$ExpectedMatchIp
)

$verify = Join-Path $PSScriptRoot "verify-egress.ps1"
if (-not (Test-Path -LiteralPath $verify)) {
    throw "Missing read-only egress probe: $verify"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verify -Proxy $Proxy -ExpectedMatchIp $ExpectedMatchIp
exit $LASTEXITCODE
