# =====================================================================
# filter-best-node.ps1
# 基于 ip-api.com 的 IP 质量信息，筛选 Clash 高质量节点并连接
#
# 功能：
#   1. 遍历 AI智能优选 组内的候选节点（新/日/韩/美）
#   2. 逐节点测试：出口 IP 质量(ip-api.com) + ChatGPT/CodeX 可达性 + 延迟
#   3. 打分排序，选出可达 OpenAI 且质量好、延迟低的节点
#   4. 用达标节点重建 AI智能优选 组（url-test 自动选延迟最低的）
#   5. 恢复规则模式并连接
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File filter-best-node.ps1
# =====================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$PIPE = "verge-mihomo"
$SECRET = "set-your-secret"
$PROXY = "http://127.0.0.1:7897"
$GROUP = "AI智能优选"

$appDir = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev"
$runtimeConfig = "$appDir\clash-verge.yaml"
$groupsOverride = "$appDir\profiles\gRAJqrfpX3EL.yaml"

# ---------- 命名管道 HTTP ----------
function Invoke-Pipe {
    param([string]$Method, [string]$Path, [string]$Body = "")
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PIPE, [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(5000)
    $len = if ($Body) { [System.Text.Encoding]::UTF8.GetByteCount($Body) } else { 0 }
    $req = "$Method $Path HTTP/1.1`r`nHost: 127.0.0.1`r`nAuthorization: Bearer $SECRET`r`nContent-Length: $len`r`nConnection: close`r`n`r`n"
    $reqBytes = [System.Text.Encoding]::ASCII.GetBytes($req)
    $pipe.Write($reqBytes, 0, $reqBytes.Length)
    if ($Body) {
        $b = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $pipe.Write($b, 0, $b.Length)
    }
    $pipe.Flush()
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 65536
    while (($n = $pipe.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    $pipe.Dispose()
    $rawBytes = $ms.ToArray()
    if ($rawBytes.Length -eq 0) { return [PSCustomObject]@{ Status = ""; Body = "" } }
    $raw = [System.Text.Encoding]::UTF8.GetString($rawBytes)
    $statusLine = ($raw -split "`r?`n")[0]
    $hdrEnd = -1
    for ($i = 0; $i -lt $rawBytes.Length - 3; $i++) {
        if ($rawBytes[$i] -eq 0x0D -and $rawBytes[$i+1] -eq 0x0A -and $rawBytes[$i+2] -eq 0x0D -and $rawBytes[$i+3] -eq 0x0A) { $hdrEnd = $i + 4; break }
    }
    if ($hdrEnd -lt 0) { return [PSCustomObject]@{ Status = $statusLine; Body = $raw } }
    $headers = $raw.Substring(0, $hdrEnd - 4)
    if ($headers -match '(?i)Transfer-Encoding:\s*chunked') {
        # 分块传输：字节级去 chunk
        $pos = $hdrEnd
        $out = New-Object System.Collections.Generic.List[byte]
        while ($pos -lt $rawBytes.Length) {
            $nl = $pos
            while ($nl -lt $rawBytes.Length - 1 -and -not ($rawBytes[$nl] -eq 0x0D -and $rawBytes[$nl+1] -eq 0x0A)) { $nl++ }
            $sizeLine = [System.Text.Encoding]::ASCII.GetString($rawBytes, $pos, $nl - $pos)
            if ($sizeLine -match '^[0-9a-fA-F]+$') {
                $size = [Convert]::ToInt32($sizeLine, 16)
                if ($size -eq 0) { break }
                $pos = $nl + 2
                if ($pos + $size -gt $rawBytes.Length) { break }
                $slice = [byte[]]::new($size)
                [System.Array]::Copy($rawBytes, $pos, $slice, 0, $size)
                $out.AddRange($slice)
                $pos = $pos + $size + 2
            } else { break }
        }
        return [PSCustomObject]@{ Status = $statusLine; Body = [System.Text.Encoding]::UTF8.GetString($out.ToArray()) }
    } else {
        # Content-Length：直接取分隔符后内容
        return [PSCustomObject]@{ Status = $statusLine; Body = $raw.Substring($hdrEnd) }
    }
}

function Get-GroupNow {
    param([string]$Name)
    $enc = [Uri]::EscapeDataString($Name)
    $resp = Invoke-Pipe -Method GET -Path "/proxies/$enc"
    try {
        $j = $resp.Body | ConvertFrom-Json
        return ,$j   # return full object
    } catch { return $null }
}

function Set-Selection {
    param([string]$GroupName, [string]$NodeName)
    $enc = [Uri]::EscapeDataString($GroupName)
    $body = (@{ name = $NodeName } | ConvertTo-Json -Compress)
    $resp = Invoke-Pipe -Method PUT -Path "/proxies/$enc" -Body $body
    return ($resp.Status -match "204")
}

function Set-Mode {
    param([string]$Mode)
    $body = (@{ mode = $Mode } | ConvertTo-Json -Compress)
    $resp = Invoke-Pipe -Method PATCH -Path "/configs" -Body $body
    return ($resp.Status -match "204")
}

function Reload-Config {
    $body = (@{ path = $runtimeConfig } | ConvertTo-Json -Compress)
    $resp = Invoke-Pipe -Method PUT -Path "/configs" -Body $body
    return ($resp.Status -match "204")
}

# ---------- 节点测试 ----------
function Test-Node {
    param([string]$NodeName)
    $result = [PSCustomObject]@{
        Node      = $NodeName
        Ip        = ""
        Country   = ""
        As        = ""
        Proxy     = $null
        Hosting   = $null
        Mobile    = $null
        RiskScore = 0
        OpenAi    = 0        # http code of codex/responses
        Latency   = 9999     # ms
        Status    = "ok"
    }
    $null = Set-Selection -GroupName "GLOBAL" -NodeName $NodeName
    Start-Sleep -Milliseconds 600

    # ip-api.com 质量检测（同时计时作为延迟）
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $json = curl.exe -s --max-time 15 -x $PROXY "http://ip-api.com/json/?fields=status,country,city,as,proxy,hosting,mobile,usageType,query" 2>$null
    $sw.Stop()
    $result.Latency = [Math]::Round($sw.Elapsed.TotalMilliseconds)
    try {
        $o = $json | ConvertFrom-Json
        if ($o.status -eq "success") {
            $result.Ip      = $o.query
            $result.Country = $o.country
            $result.As      = $o.as
            $result.Proxy   = [bool]$o.proxy
            $result.Hosting = [bool]$o.hosting
            $result.Mobile  = [bool]$o.mobile
        } else {
            $result.Status = "ip-api:" + $o.message
        }
    } catch { $result.Status = "ip-api-parse-fail" }

    # OpenAI/CodeX 可达性：codex/responses websocket 端点
    $code = curl.exe -s --max-time 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0.0.0" -o NUL -w "%{http_code}" -x $PROXY -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" "https://chatgpt.com/backend-api/codex/responses" 2>$null
    $result.OpenAi = $code
    return $result
}

# ---------- 主流程 ----------
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Clash 节点质量筛选（基于 ip-api.com）" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

$grp = Get-GroupNow -Name $GROUP
$globalGrp = Get-GroupNow -Name "GLOBAL"
if (-not $globalGrp -or -not $globalGrp.all) { Write-Host "无法连接 Clash，请确认 Clash Verge 已启动" -ForegroundColor Red; exit 1 }
# 候选节点：GLOBAL 全量节点中筛出新/日/韩/美（含组内全部，避免组被缩小后漏测）
$nodes = @($globalGrp.all | Where-Object { $_ -match "^(🇸🇬|🇯🇵|🇰🇷|🇺🇸)" })
if ($nodes.Count -eq 0) { $nodes = @($grp.all) }
Write-Host "候选节点 $($nodes.Count) 个"

# 切全局模式（让测试流量走 GLOBAL 节点）
if (-not (Set-Mode "global")) { Write-Host "切换全局模式失败" -ForegroundColor Yellow }

$results = @()
$n = 0
foreach ($node in $nodes) {
    $n++
    Write-Host ("[{0}/{1}] {2}" -f $n, $nodes.Count, $node) -NoNewline
    $r = Test-Node -NodeName $node
    Write-Host ("  -> {0} | {1} | proxy={2} hosting={3} | OpenAI={4} | {5}ms | {6}" -f $r.Ip, $r.Country, $r.Proxy, $r.Hosting, $r.OpenAi, $r.Latency, $r.Status) -ForegroundColor Gray
    $results += $r
}

# 恢复规则模式 + 主组回自动优选
Set-Mode "rule" | Out-Null
Set-Selection -GroupName "GLOBAL" -NodeName $GROUP | Out-Null

# ---------- 打分 ----------
$passing = @()
foreach ($r in $results) {
    $okOpenAi = ($r.OpenAi -eq "401" -or $r.OpenAi -eq "405" -or $r.OpenAi -eq "200")
    $okApi    = ($r.Status -eq "ok")
    if ($okOpenAi -and $okApi) { $passing += $r }
}
$residential = @($passing | Where-Object { $_.Proxy -eq $false -and $_.Hosting -eq $false })
$datacenter  = @($passing | Where-Object { -not ($_.Proxy -eq $false -and $_.Hosting -eq $false) })

Write-Host ""
Write-Host "========== 汇总 ==========" -ForegroundColor Cyan
Write-Host "通过 OpenAI 且检测正常：$($passing.Count) 个"
Write-Host "  其中住宅/非机房标记：$($residential.Count) 个"
Write-Host "  机房/代理标记：$($datacenter.Count) 个"

if ($passing.Count -eq 0) {
    Write-Host "没有节点通过 OpenAI 可达性检测，请换供应商或稍后再试。" -ForegroundColor Red
    exit 2
}

# 排序：住宅优先，再按延迟升序
$sorted = @($passing | Sort-Object @{e={if ($_.Proxy -eq $false -and $_.Hosting -eq $false) {0} else {1}}}, Latency)
$best = $sorted[0]

Write-Host ""
Write-Host ("最优节点：{0}" -f $best.Node) -ForegroundColor Green
Write-Host ("  出口IP：{0}（{1}）" -f $best.Ip, $best.Country) -ForegroundColor Green
Write-Host ("  ASN：{0}" -f $best.As) -ForegroundColor Green
Write-Host ("  机房/代理：proxy={0} hosting={1}" -f $best.Proxy, $best.Hosting) -ForegroundColor Green
Write-Host ("  OpenAI可达：HTTP {0}   延迟：{1}ms" -f $best.OpenAi, $best.Latency) -ForegroundColor Green

# ---------- 用达标节点重建 AI智能优选 组 ----------
$pool = @($sorted | Select-Object -First ([Math]::Min(12, $sorted.Count))).Node
Write-Host ""
Write-Host ("重建 AI智能优选 组（{0} 个达标节点，按延迟排序）..." -f $pool.Count)

function Build-GroupYaml {
    param([string[]]$NodeList)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("- name: $GROUP")
    [void]$sb.AppendLine("  type: url-test")
    [void]$sb.AppendLine("  interval: 300")
    [void]$sb.AppendLine("  tolerance: 50")
    [void]$sb.AppendLine("  url: http://www.gstatic.com/generate_204")
    [void]$sb.AppendLine("  proxies:")
    foreach ($n in $NodeList) { [void]$sb.AppendLine("  - $n") }
    return $sb.ToString()
}

$newBlock = Build-GroupYaml -NodeList $pool

# 1) 更新运行时配置 clash-verge.yaml（替换 AI智能优选 组块）
$lines = Get-Content $runtimeConfig -Encoding UTF8
$idx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^\- name: " + [regex]::Escape($GROUP) + "$") { $idx = $i; break }
}
if ($idx -ge 0) {
    $out2 = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $idx; $i++) { $out2.Add($lines[$i]) }
    foreach ($gl in ($newBlock -split "`r?`n")) { if ($gl -ne "") { $out2.Add($gl) } }
    for ($i = $idx; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($i -gt $idx -and $ln -match "^(rules:|-)") { $out2.Add($ln) }
        elseif ($i -eq $idx) { continue }
        elseif ($ln -match "^  (name|type|interval|tolerance|url|proxies):") { continue }
        elseif ($ln -match "^  - ") { continue }
        elseif ($ln -eq "") { continue }
        else { $out2.Add($ln) }
    }
    [System.IO.File]::WriteAllLines($runtimeConfig, $out2.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已更新运行时配置"
} else {
    Write-Host "运行时配置中未找到 $GROUP 组块，跳过更新" -ForegroundColor Yellow
}

# 2) 更新 groups 覆盖文件（订阅刷新后仍保留）
$gb = New-Object System.Text.StringBuilder
[void]$gb.AppendLine("# Profile Enhancement Groups Template for Clash Verge")
[void]$gb.AppendLine("")
[void]$gb.AppendLine("prepend: []")
[void]$gb.AppendLine("")
[void]$gb.AppendLine("append:")
foreach ($gl in ($newBlock -split "`r?`n")) { if ($gl -ne "") { [void]$gb.AppendLine($gl) } }
[void]$gb.AppendLine("delete: []")
[System.IO.File]::WriteAllText($groupsOverride, $gb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已更新 groups 覆盖文件"

# 3) 重载配置
Start-Sleep -Milliseconds 300
if (Reload-Config) { Write-Host "配置已重载" } else { Write-Host "配置重载失败，请手动在 Clash Verge 里重载" -ForegroundColor Yellow }
Start-Sleep -Seconds 2

# 4) 重新选中
Set-Selection -GroupName "GLOBAL" -NodeName $GROUP | Out-Null

# ---------- 报告 ----------
Write-Host ""
Write-Host "========== 达标节点排名（前10） ==========" -ForegroundColor Cyan
$sorted | Select-Object -First 10 | ForEach-Object {
    $tag = if ($_.Proxy -eq $false -and $_.Hosting -eq $false) { "[住宅]" } else { "[机房]" }
    "{0,-3} {1,-6} {2,-34} {3,-18} proxy={4,-5} hosting={5,-6} OpenAI={6} {7}ms  {8}" -f "TOP", $tag, $_.Node, $_.Country, $_.Proxy, $_.Hosting, $_.OpenAi, $_.Latency, $_.Ip
}
Write-Host ""
Write-Host ("已连接：AI智能优选 已按延迟在 {0} 个达标节点间自动切换" -f $pool.Count) -ForegroundColor Green
Write-Host "提示：以后想重新筛选，直接再运行本脚本即可。" -ForegroundColor Cyan
