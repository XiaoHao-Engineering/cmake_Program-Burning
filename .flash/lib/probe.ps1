# =============================================================================
#  cmake-flash-kit :: probe.ps1
#  下载器（ST-Link / DAPLink）自动识别。
#  兼容 Windows PowerShell 5.1 与 PowerShell 7+。
# =============================================================================

# 已知的 ST-Link VID/PID
$script:StLinkVidPids = @(
    '0483:3748', # ST-Link/V2
    '0483:374B', # ST-Link/V2-1
    '0483:374D', # ST-Link/V2-1 (DFU)
    '0483:374E', # ST-Link/V3
    '0483:374F', # ST-Link/V3-1
    '0483:3752', # ST-Link/V3-2
    '0483:3753', # ST-Link/V3 (DFU/other)
    '0483:3754', # ST-Link/V3 (bridge)
    '0483:3757'  # ST-Link/V3 (newer)
)

# 已知的 CMSIS-DAP / DAPLink VID/PID（含常见国产克隆）
$script:DapLinkVidPids = @(
    '0D28:0204', # ARM mbed DAPLink
    'C251:F001', # Keil ULINK 兼容 / 部分 DAPLink
    'C251:F002',
    '1209:0000', # 常见开源 DAPLink
    '2886:0001', # 部分 DAPLink 克隆
    '2E8A:0001'
)

# 枚举当前连接的下载器
function Get-ProbeList {
    $result = New-Object System.Collections.ArrayList
    $devices = @()

    try {
        $devices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
    }
    catch {
        try {
            $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
                Where-Object { $_.PNPDeviceID -like 'USB\*' })
        }
        catch { }
    }

    foreach ($d in $devices) {
        $name = "$(Get-Field $d 'FriendlyName' '')"
        $id = "$(Get-Field $d 'InstanceId' '')"
        if (-not $id) { $id = "$(Get-Field $d 'PNPDeviceID' '')" }
        if (-not $id) { continue }

        $vidpid = ''
        if ($id -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
            $vidpid = ($Matches[1] + ':' + $Matches[2]).ToUpperInvariant()
        }

        $kind = $null
        if ($vidpid -and ($script:StLinkVidPids -contains $vidpid)) { $kind = 'stlink' }
        elseif ($name -match 'ST-?\s?Link') { $kind = 'stlink' }
        elseif ($vidpid -and ($script:DapLinkVidPids -contains $vidpid)) { $kind = 'daplink' }
        elseif ($name -match 'CMSIS-?DAP|DAPLink|mbed|DAP\d') { $kind = 'daplink' }

        if (-not $kind) { continue }

        $serial = ''
        $idx = $id.LastIndexOf('\')
        if ($idx -ge 0 -and $idx -lt ($id.Length - 1)) { $serial = $id.Substring($idx + 1) }
        # USB 复合设备的实例路径形如 "9&15FC547A&0&0000"，不是真正的序列号
        if ($serial -match '^\d+&' -or $serial -match '&0&') { $serial = '' }

        [void]$result.Add([pscustomobject]@{
                Kind       = $kind
                Name       = $name
                VidPid     = $vidpid
                Serial     = $serial
                InstanceId = $id
            })
    }

    return $result
}

function Format-ProbeList {
    param($Probes)

    if (-not $Probes -or $Probes.Count -eq 0) {
        Write-Host '  (没有检测到 ST-Link / DAPLink)' -ForegroundColor Yellow
        return
    }
    $i = 0
    foreach ($p in $Probes) {
        $i++
        $label = if ($p.Kind -eq 'stlink') { 'ST-Link' } else { 'DAPLink' }
        Write-Host ("  [$i] " + $label.PadRight(8) + " " + $p.VidPid.PadRight(11) + " " + $p.Name) -ForegroundColor White
        if ($p.Serial) { Write-Host ("      SN: " + $p.Serial) -ForegroundColor DarkGray }
    }
}

# 根据配置 / 实际连接情况决定用哪个下载器
# 返回: @{ Kind='stlink'|'daplink'; Serial=''; Probe=<对象或$null> }
function Resolve-Probe {
    param(
        [string]$Preference = 'auto',
        $Probes,
        [string]$Serial = ''
    )

    if (-not $Probes) { $Probes = @() }

    $stlinks = @($Probes | Where-Object { $_.Kind -eq 'stlink' })
    $daplinks = @($Probes | Where-Object { $_.Kind -eq 'daplink' })

    if ($Serial) {
        $hit = @($Probes | Where-Object { $_.Serial -eq $Serial })
        if ($hit.Count -gt 0) {
            return [pscustomobject]@{ Kind = $hit[0].Kind; Serial = $hit[0].Serial; Probe = $hit[0] }
        }
        Write-Warn ("未找到序列号为 $Serial 的下载器，改为自动选择。")
    }

    switch ($Preference) {
        'stlink' {
            if ($stlinks.Count -eq 0) {
                throw "指定的 ST-Link 未连接。请检查 USB 线，或改用 -Probe daplink / auto。"
            }
            return [pscustomobject]@{ Kind = 'stlink'; Serial = $stlinks[0].Serial; Probe = $stlinks[0] }
        }
        'daplink' {
            if ($daplinks.Count -eq 0) {
                throw "指定的 DAPLink 未连接。请检查 USB 线，或改用 -Probe stlink / auto。"
            }
            return [pscustomobject]@{ Kind = 'daplink'; Serial = $daplinks[0].Serial; Probe = $daplinks[0] }
        }
    }

    # auto
    if ($stlinks.Count -gt 0 -and $daplinks.Count -eq 0) {
        return [pscustomobject]@{ Kind = 'stlink'; Serial = $stlinks[0].Serial; Probe = $stlinks[0] }
    }
    if ($daplinks.Count -gt 0 -and $stlinks.Count -eq 0) {
        return [pscustomobject]@{ Kind = 'daplink'; Serial = $daplinks[0].Serial; Probe = $daplinks[0] }
    }
    if ($stlinks.Count -gt 0 -and $daplinks.Count -gt 0) {
        Write-Warn '同时检测到 ST-Link 和 DAPLink，默认使用 ST-Link（可用 -Probe daplink 切换）。'
        return [pscustomobject]@{ Kind = 'stlink'; Serial = $stlinks[0].Serial; Probe = $stlinks[0] }
    }

    throw @'
没有检测到任何下载器（ST-Link / DAPLink）。

请依次检查：
  1. 下载器是否已插到电脑 USB 口（换一个 USB 口试试，尽量直连不用 Hub）；
  2. 设备管理器里是否出现 "ST-Link" 或 "CMSIS-DAP" 设备，有没有黄色感叹号；
  3. 杜邦线：SWDIO / SWCLK / GND 是否接对，目标板是否已上电；
  4. 若使用 DAPLink，确认固件是 CMSIS-DAP 而不是 DAPLink 的 "拖拽下载" U 盘模式。
'@
}
