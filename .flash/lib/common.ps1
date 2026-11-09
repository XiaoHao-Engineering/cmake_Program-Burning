# =============================================================================
#  cmake-flash-kit :: common.ps1
#  输出、错误处理、外部命令调用等公共函数。
#  兼容 Windows PowerShell 5.1 与 PowerShell 7+。
# =============================================================================

$script:KitVersion = '1.0.0'

function Write-Banner {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkGray
    Write-Host ("  " + $Text) -ForegroundColor White
    Write-Host ('=' * 68) -ForegroundColor DarkGray
}

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host ("==> " + $Text) -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Text)
    Write-Host ("     " + $Text) -ForegroundColor Gray
}

function Write-Ok {
    param([string]$Text)
    Write-Host ("  OK  " + $Text) -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host ("  !   " + $Text) -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host ("  X   " + $Text) -ForegroundColor Red
}

function Write-Detail {
    param([string]$Text)
    Write-Host ("        " + $Text) -ForegroundColor DarkGray
}

# 把一条命令格式化成可直接复制到终端里执行的字符串
function Format-NativeCommand {
    param([string]$Exe, [string[]]$Arguments)

    $parts = @()
    $parts += ('"' + $Exe + '"')
    if ($Arguments) {
        foreach ($a in $Arguments) {
            if ($null -eq $a) { continue }
            if ($a -match '[\s&|<>]') {
                $parts += ('"' + $a.Replace('"', '\"') + '"')
            }
            else {
                $parts += $a
            }
        }
    }
    return ($parts -join ' ')
}

# 调用外部程序：输出直接进入终端（实时可见），返回退出码
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @(),
        [string]$WorkDir = ''
    )

    Write-Detail ('> ' + (Format-NativeCommand -Exe $Exe -Arguments $Arguments))

    $old = $null
    if ($WorkDir -and (Test-Path -LiteralPath $WorkDir)) {
        $old = (Get-Location).Path
        Set-Location -LiteralPath $WorkDir
    }
    try {
        # 用 Out-Host 保证子进程输出"只显示不进入函数返回值"，
        # 否则编译日志会被当成返回值，导致退出码判断失效。
        & $Exe @Arguments | Out-Host
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
    }
    finally {
        if ($old) { Set-Location -LiteralPath $old }
    }
    return $code
}

# 调用外部程序并捕获输出（用于探测版本号等）
function Invoke-Capture {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @()
    )

    try {
        $out = & $Exe @Arguments 2>&1
        return (($out | ForEach-Object { "$_" }) -join "`n")
    }
    catch {
        return ''
    }
}

# 在若干通配路径中找出第一个存在的文件（按修改时间倒序）
function Find-FirstFile {
    param([string[]]$Patterns, [string]$LeafFilter = '')

    foreach ($p in $Patterns) {
        if (-not $p) { continue }
        try {
            $items = @()
            if ($LeafFilter) {
                $items = @(Get-ChildItem -Path $p -Filter $LeafFilter -File -ErrorAction SilentlyContinue)
            }
            elseif (Test-Path -LiteralPath $p -PathType Leaf) {
                return (Get-Item -LiteralPath $p).FullName
            }
            else {
                $items = @(Get-Item -Path $p -ErrorAction SilentlyContinue)
            }
            if ($items.Count -gt 0) {
                $best = $items | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                return $best.FullName
            }
        }
        catch { }
    }
    return $null
}

# 取对象属性，属性不存在时返回默认值（避免 StrictMode 报错）
function Get-Field {
    param($Object, [string]$Name, $Default = $null)

    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    if ($null -eq $p.Value) { return $Default }
    return $p.Value
}

function Test-Truthy {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    $s = "$Value".Trim().ToLowerInvariant()
    return ($s -in @('1', 'true', 'yes', 'on'))
}
