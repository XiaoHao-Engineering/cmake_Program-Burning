<#
.SYNOPSIS
    把 cmake-flash-kit 安装到任意 CMake 工程。

.EXAMPLE
    # 在本仓库目录下，把工具装到某个工程
    .\install.ps1 -Project D:\work\my_stm32_project

.EXAMPLE
    # 已经站在目标工程里，直接装到当前目录
    C:\tools\cmake_Program-Burning\install.ps1

.EXAMPLE
    # 装完后顺手烧一次
    .\install.ps1 -Project . -Run
#>

[CmdletBinding()]
param(
    [string]$Project = '',
    [ValidateSet('auto', 'stlink', 'daplink')][string]$Probe = 'auto',
    [string]$Target = 'auto',
    [int]$Speed = 0,
    [string]$BuildType = 'Debug',
    [switch]$NoTasks,
    [switch]$Force,
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

$kitRoot = $PSScriptRoot
$kitFlash = Join-Path $kitRoot '.flash'

# 复用运行库里的 Get-Field 等工具函数
. (Join-Path $kitFlash 'lib\common.ps1')

function Write-InstallLog {
    param([string]$Text, [string]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
}

if (-not (Test-Path -LiteralPath $kitFlash)) {
    throw "安装包不完整：找不到 $kitFlash"
}

if (-not $Project) { $Project = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Project)) { throw "工程目录不存在：$Project" }
$Project = (Resolve-Path -LiteralPath $Project).Path

# 目标目录不能是工具自身
$kitFull = (Resolve-Path -LiteralPath $kitRoot).Path
if ($Project -eq $kitFull) {
    throw "请不要把工具安装到它自己的目录里。请在目标工程目录下运行：$kitRoot\install.ps1 -Project <工程目录>"
}

$cmakeLists = Join-Path $Project 'CMakeLists.txt'
if (-not (Test-Path -LiteralPath $cmakeLists)) {
    Write-InstallLog "警告：$Project 下没有 CMakeLists.txt，仍然继续安装（之后把它放进 CMake 工程根目录即可）。" 'Yellow'
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host '  cmake-flash-kit 安装程序' -ForegroundColor White
Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host ("  工具目录 : " + $kitRoot)
Write-Host ("  目标工程 : " + $Project)
Write-Host ''

# ---------------------------------------------------------------------------
# 1. 复制 .flash
# ---------------------------------------------------------------------------
$destFlash = Join-Path $Project '.flash'
Write-Host '[1/3] 复制运行文件 ...' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $destFlash | Out-Null

$configDest = Join-Path $destFlash 'flash.config.json'
$keepConfig = (Test-Path -LiteralPath $configDest) -and (-not $Force)

Get-ChildItem -LiteralPath $kitFlash -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($kitFlash.Length).TrimStart('\')
    if ($keepConfig -and ($rel -eq 'flash.config.json')) { return }
    $dst = Join-Path $destFlash $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
}
Write-InstallLog ("      -> " + $destFlash) 'DarkGray'

# ---------------------------------------------------------------------------
# 2. 生成 / 合并 flash.config.json
# ---------------------------------------------------------------------------
Write-Host '[2/3] 写入配置 ...' -ForegroundColor Cyan
if ($keepConfig) {
    Write-InstallLog '      已存在 flash.config.json，保留你的设置（加 -Force 可覆盖）。' 'Yellow'
}
else {
    $cfg = Get-Content -LiteralPath (Join-Path $kitFlash 'flash.config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $cfg.projectName = (Split-Path -Leaf $Project)
    if ($Target -ne 'auto') { $cfg.target = $Target }
    if ($Probe -ne 'auto') { $cfg.probe = $Probe }
    if ($Speed -gt 0) { $cfg.speed = $Speed }
    if ($BuildType) { $cfg.buildType = $BuildType }
    $json = $cfg | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($configDest, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-InstallLog '      -> .flash\flash.config.json' 'DarkGray'
}

# ---------------------------------------------------------------------------
# 3. 生成 / 合并 .vscode/tasks.json
# ---------------------------------------------------------------------------
if (-not $NoTasks) {
    Write-Host '[3/3] 写入 VS Code 任务（Ctrl+Shift+B）...' -ForegroundColor Cyan

    $templatePath = Join-Path $kitRoot '.vscode\tasks.json'
    $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json

    $vscodeDir = Join-Path $Project '.vscode'
    if (-not (Test-Path -LiteralPath $vscodeDir)) { New-Item -ItemType Directory -Force -Path $vscodeDir | Out-Null }
    $tasksPath = Join-Path $vscodeDir 'tasks.json'

    $merged = $null
    if (Test-Path -LiteralPath $tasksPath) {
        try {
            $merged = Get-Content -LiteralPath $tasksPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            $backup = $tasksPath + '.bak'
            Copy-Item -LiteralPath $tasksPath -Destination $backup -Force
            Write-InstallLog ("      原 tasks.json 解析失败，已备份到 " + $backup) 'Yellow'
            $merged = $null
        }
    }

    if (-not $merged) {
        # 没有现成的 tasks.json：直接复制模板，保留可读的排版
        Copy-Item -LiteralPath $templatePath -Destination $tasksPath -Force
    }
    else {
        if (-not $merged.PSObject.Properties['version']) {
            $merged | Add-Member -NotePropertyName version -NotePropertyValue '2.0.0'
        }
        if (-not $merged.PSObject.Properties['tasks']) {
            $merged | Add-Member -NotePropertyName tasks -NotePropertyValue @()
        }
        $keep = @()
        foreach ($t in @($merged.tasks)) {
            $label = "$(Get-Field $t 'label' '')"
            if ($label -like 'Flash:*') { continue }
            $keep += $t
        }
        $merged.tasks = @($keep) + @($template.tasks)

        $json = $merged | ConvertTo-Json -Depth 12
        [IO.File]::WriteAllText($tasksPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-InstallLog '      -> .vscode\tasks.json（已设为默认生成任务）' 'DarkGray'
}

# ---------------------------------------------------------------------------
# 完成
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '安装完成。' -ForegroundColor Green
Write-Host ''
Write-Host '  用 VS Code 打开该工程，按 Ctrl+Shift+B 即可：编译 + 自动识别下载器 + 烧录。' -ForegroundColor White
Write-Host '  也可以手动运行：' -ForegroundColor Gray
Write-Host ('      powershell -ExecutionPolicy Bypass -File "' + (Join-Path $destFlash 'flash.ps1') + '"') -ForegroundColor DarkGray
Write-Host ''
Write-Host '  常用选项：-NoBuild 只烧录 / -Probe stlink|daplink 指定下载器 / -ListProbes 查看设备' -ForegroundColor Gray
Write-Host '  详细说明见 .flash\README.md 或仓库根目录 README.md。' -ForegroundColor Gray
Write-Host ''

if ($Run) {
    Write-Host '开始首次烧录 ...' -ForegroundColor Cyan
    & (Join-Path $destFlash 'flash.ps1')
    exit $LASTEXITCODE
}
