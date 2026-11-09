# =============================================================================
#  cmake-flash-kit :: flash.ps1
#  一键：配置 CMake（按需） -> 编译 -> 自动识别下载器 -> OpenOCD 烧录。
#  用法示例：
#    .\.flash\flash.ps1                 # 编译 + 烧录（自动识别 ST-Link / DAPLink）
#    .\.flash\flash.ps1 -NoBuild        # 只烧录，不编译
#    .\.flash\flash.ps1 -Probe daplink  # 强制使用 DAPLink
#    .\.flash\flash.ps1 -ListProbes     # 列出当前连接的下载器
#    .\.flash\flash.ps1 -DryRun         # 只打印将要执行的命令
# =============================================================================

[CmdletBinding()]
param(
    [switch]$NoBuild,
    [switch]$UnderReset,
    [ValidateSet('auto', 'stlink', 'daplink')][string]$Probe = 'auto',
    [string]$Target = '',
    [int]$Speed = 0,
    [string]$Elf = '',
    [string]$BuildDir = '',
    [string]$ConfigPath = '',
    [switch]$ListProbes,
    [switch]$DryRun,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'lib\env.ps1')
. (Join-Path $PSScriptRoot 'lib\probe.ps1')
. (Join-Path $PSScriptRoot 'lib\project.ps1')

# ---------------------------------------------------------------------------
# 配置读取
# ---------------------------------------------------------------------------
function Get-DefaultConfig {
    return [pscustomobject]@{
        projectName         = ''
        target              = 'auto'
        probe               = 'auto'
        probeSerial         = ''
        speed               = 0
        buildDir            = 'build'
        buildType           = 'Debug'
        configureArgs       = @()
        elf                 = 'auto'
        openocd             = 'auto'
        openocdVersion      = '0.12.0-7'
        autoInstallOpenOCD  = $true
        connectUnderReset   = $false
        verify              = $true
        extraOpenocdConfig  = @()
        binAddress          = '0x08000000'
        autoSpeedFallback   = $true
    }
}

function Read-FlashConfig {
    param([string]$Path)

    $cfg = Get-DefaultConfig
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $cfg }

    try {
        $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw ("配置文件解析失败：" + $Path + "`n" + $_.Exception.Message)
    }

    foreach ($p in $cfg.PSObject.Properties) {
        $v = Get-Field $json $p.Name $null
        if ($null -ne $v) { $cfg.($p.Name) = $v }
    }
    return $cfg
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
function Invoke-FlashKit {
    param([string]$Root)

    $configFile = $ConfigPath
    if (-not $configFile) { $configFile = Join-Path $PSScriptRoot 'flash.config.json' }
    if (-not (Test-Path -LiteralPath $configFile)) { $configFile = '' }

    $cfg = Read-FlashConfig -Path $configFile

    # 命令行覆盖配置
    if ($Probe -ne 'auto') { $cfg.probe = $Probe }
    if ($Target) { $cfg.target = $Target }
    if ($Speed -gt 0) { $cfg.speed = $Speed }
    if ($Elf) { $cfg.elf = $Elf }
    if ($BuildDir) { $cfg.buildDir = $BuildDir }
    if ($UnderReset) { $cfg.connectUnderReset = $true }

    if (-not $Quiet) {
        Write-Banner ("cmake-flash-kit v" + $script:KitVersion + "  |  " + $Root)
        if ($configFile) { Write-Detail ("配置文件: " + $configFile) }
    }

    # ---------------- 1. 列出下载器 ----------------
    if ($ListProbes) {
        Write-Step '当前连接的下载器'
        $probes = Get-ProbeList
        Format-ProbeList -Probes $probes
        Write-Host ''
        if (-not $Quiet) { Write-Detail '提示: 用 -Probe stlink / -Probe daplink 指定；或在 flash.config.json 里写 "probe".' }
        return 0
    }

    # ---------------- 2. 工具链 ----------------
    Write-Step '检查工具链'
    $gcc = Find-ArmGcc
    if (-not $gcc) {
        throw @'
没有找到 arm-none-eabi-gcc。

可选做法（任选其一）：
  * 安装 STM32 VS Code 扩展的 GNU 工具链（会自动下载到 %LOCALAPPDATA%\STM32Cube\bundles）；
  * 安装 STM32CubeIDE；
  * 安装 xPack GNU Arm Embedded GCC 并把它加入 PATH；
  * 在 flash.config.json 的 "configureArgs" 里指定 -DCMAKE_C_COMPILER=... 并用系统编译器。
'@
    }
    Write-Ok ("arm-none-eabi-gcc: " + $gcc)

    $cmake = Find-CMake
    if (-not $cmake) { throw '没有找到 cmake.exe，请安装 CMake 或 STM32 VS Code 扩展（自带 CMake）。' }
    Write-Ok ("cmake: " + $cmake)

    $ninja = Find-Ninja
    if ($ninja) { Write-Ok ("ninja: " + $ninja) }
    else { Write-Info '未找到 ninja，将使用 CMake 默认生成器。' }

    $env:PATH = Get-ToolchainEnv -ArmGcc $gcc -CMake $cmake -Ninja $ninja

    # ---------------- 3. 构建 ----------------
    $buildInfo = Resolve-BuildDirectory -Root $Root -Configured $cfg.buildDir
    $buildDirPath = $buildInfo.Path

    if (-not $NoBuild) {
        if (-not $buildInfo.Ready) {
            Write-Step '首次配置 CMake 工程'
            $code = Invoke-ProjectConfigure -Root $Root -BuildDir $buildDirPath -BuildType $cfg.buildType `
                -CMake $cmake -Ninja $ninja -ExtraArgs $cfg.configureArgs -DryRun:$DryRun
            if ($code -ne 0) { throw ("CMake 配置失败（退出码 $code）。请先手动执行 cmake 配置排查报错。") }
            Write-Ok '配置完成'
        }
        else {
            Write-Info ("复用构建目录: " + $buildDirPath)
        }

        Write-Step '编译固件'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $code = Invoke-ProjectBuild -Root $Root -BuildDir $buildDirPath -BuildType $cfg.buildType `
            -CMake $cmake -DryRun:$DryRun
        $sw.Stop()
        if ($code -ne 0) { throw ("编译失败（退出码 $code），已终止烧录。") }
        Write-Ok ("编译完成，用时 " + [math]::Round($sw.Elapsed.TotalSeconds, 1) + " s")
    }
    else {
        Write-Info '已指定 -NoBuild，跳过编译。'
    }

    # ---------------- 4. 固件 ----------------
    Write-Step '定位固件'
    $projectName = Get-ProjectNameFromCache -BuildDir $buildDirPath
    $elfPath = Find-ElfFile -BuildDir $buildDirPath -Configured $cfg.elf -ProjectName $projectName
    if (-not $elfPath) {
        throw ("在 " + $buildDirPath + " 下没有找到 .elf 固件。请先编译，或在 flash.config.json 里用 `"elf`" 指定路径。")
    }
    $size = (Get-Item -LiteralPath $elfPath).Length
    Write-Ok ($elfPath)
    Write-Info ("ELF 文件: " + [math]::Round($size / 1024, 1) + " KB（含调试信息，实际占用见编译输出的 FLASH 行）")

    # ---------------- 5. OpenOCD ----------------
    Write-Step '准备 OpenOCD'
    $ocd = Ensure-OpenOcd -Configured $cfg.openocd -Version $cfg.openocdVersion -AutoInstall (Test-Truthy $cfg.autoInstallOpenOCD)
    if (-not $ocd) {
        throw @'
没有找到可用的 OpenOCD，自动安装也失败了。

请手动安装（任选其一）：
  * 下载 xPack OpenOCD 解压后，把 bin 目录加入 PATH；
  * 在 flash.config.json 里把 "openocd" 写成 openocd.exe 的绝对路径；
  * 安装 STM32CubeIDE（其插件目录自带 OpenOCD，本工具会自动搜索）。
'@
    }
    Write-Ok $ocd

    $scriptsDir = Get-OpenOcdScripts -OpenOcdExe $ocd
    if ($scriptsDir) { Write-Info ('scripts: ' + $scriptsDir) }

    # ---------------- 6. 目标芯片 ----------------
    $targetInfo = Resolve-Target -Root $Root -BuildDir $buildDirPath -Configured $cfg.target
    if (-not $targetInfo.Target) {
        throw @'
无法自动判断目标芯片型号（OpenOCD target 配置）。

请在 .flash\flash.config.json 里显式指定，例如：
  "target": "stm32h7x"      // STM32H7
  "target": "stm32f4x"      // STM32F4
  "target": "stm32g4x"      // STM32G4
也可以填 .cfg 文件的绝对路径。
'@
    }
    Write-Ok ('target: ' + $targetInfo.Target + '  (来源: ' + $targetInfo.Source + ')')

    # ---------------- 7. 下载器 ----------------
    Write-Step '识别下载器'
    $probes = @(Get-ProbeList)
    $resolved = Resolve-Probe -Preference $cfg.probe -Probes $probes -Serial $cfg.probeSerial
    $kindLabel = if ($resolved.Kind -eq 'stlink') { 'ST-Link' } else { 'DAPLink' }
    Write-Ok ($kindLabel + '  ' + $resolved.Probe.VidPid + '  ' + $resolved.Probe.Name)
    if ($resolved.Serial) { Write-Info ('SN: ' + $resolved.Serial) }

    # ---------------- 8. 烧录 ----------------
    $interfaceCfg = if ($resolved.Kind -eq 'stlink') { 'interface/stlink.cfg' } else { 'interface/cmsis-dap.cfg' }

    # 速度：0 表示自动。DAPLink 克隆版普遍跑不到 10MHz，默认给保守值。
    $speeds = @()
    if ($cfg.speed -gt 0) {
        $speeds += [int]$cfg.speed
    }
    else {
        if ($resolved.Kind -eq 'daplink') { $speeds += 2000 }
        else { $speeds += 4000 }
    }
    if ((Test-Truthy $cfg.autoSpeedFallback) -and $cfg.speed -le 0) {
        foreach ($s in @(2000, 1000, 500)) {
            if ($speeds -notcontains $s -and $s -lt $speeds[0]) { $speeds += $s }
        }
    }

    $lastCode = 1
    for ($i = 0; $i -lt $speeds.Count; $i++) {
        $speedNow = $speeds[$i]
        $ocdArgs = @()
        if ($scriptsDir) { $ocdArgs += @('-s', $scriptsDir) }
        $ocdArgs += @('-f', $interfaceCfg)
        $targetCfg = $targetInfo.Target
        if ($targetCfg -notmatch '\.cfg$') { $targetCfg = $targetCfg + '.cfg' }
        $ocdArgs += @('-f', ('target/' + $targetCfg))
        $ocdArgs += @('-c', ('adapter speed ' + $speedNow))
        if (Test-Truthy $cfg.connectUnderReset) {
            $ocdArgs += @('-c', 'reset_config srst_only srst_nogate connect_assert_srst')
        }
        foreach ($extra in @($cfg.extraOpenocdConfig)) {
            if ($extra) { $ocdArgs += @('-c', $extra) }
        }

        # 用 Tcl 花括号包住路径：既能带空格，又避免在 PowerShell 5.1 里被二次转义
        $elfTcl = $elfPath.Replace('\', '/')
        $programArgs = 'program {' + $elfTcl + '}'
        if ($elfPath -match '\.bin$') { $programArgs += (' 0x' + ($cfg.binAddress -replace '^0x', '')) }
        if (Test-Truthy $cfg.verify) { $programArgs += ' verify' }
        $programArgs += ' reset exit'
        $ocdArgs += @('-c', $programArgs)

        Write-Step ('烧录中（' + $kindLabel + ' @ ' + $speedNow + ' kHz）')
        if ($DryRun) {
            Write-Detail ('> ' + (Format-NativeCommand -Exe $ocd -Arguments $ocdArgs))
            return 0
        }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $log = New-Object System.Collections.ArrayList
        # OpenOCD 的信息输出走 stderr；PS 5.1 在 ErrorActionPreference=Stop 时会把 stderr
        # 当成终止性错误，所以这里临时改成 Continue，把输出正常收进日志。
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $ocd @ocdArgs 2>&1 | ForEach-Object {
                $line = "$_"
                [void]$log.Add($line)
                Write-Host ("  " + $line) -ForegroundColor DarkGray
            }
            $lastCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldEap
        }
        $sw.Stop()

        if ($lastCode -eq 0) {
            Write-Host ''
            Write-Ok ('烧录成功，用时 ' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + ' s')
            Write-Info ($kindLabel + ' -> ' + $targetInfo.Target + ' -> ' + (Split-Path -Leaf $elfPath))
            return 0
        }

        $text = ($log -join "`n")
        $retryable = ($text -match 'adapter speed|timed out|Timeout|Error: init|JTAG scan chain|connect failed|Cant connect|unable to connect')
        if ($i -lt ($speeds.Count - 1) -and $retryable) {
            Write-Warn ('本次失败，可能是 SWD 速度过高，自动降到 ' + $speeds[$i + 1] + ' kHz 重试 ...')
            continue
        }
        break
    }

    throw @'
烧录失败。常见原因与处理：
  1. 目标板没上电 / 没共地 / SWDIO、SWCLK 接反  -> 检查接线与供电；
  2. 芯片里旧程序带看门狗，一上电就打断 SWD   -> 用 Ctrl+Shift+P 运行 "Flash (Connect under reset)"；
  3. 芯片被读保护（RDP Level 1/2）             -> 先用 STM32CubeProgrammer 解除保护；
  4. DAPLink 固件不是 CMSIS-DAP 模式            -> 重新刷 DAPLink 固件（CMSIS-DAP）；
  5. SWD 速度过高                              -> 在 flash.config.json 里把 "speed" 改成 1000。
'@
}

# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------
try {
    $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $code = Invoke-FlashKit -Root $root
    exit $code
}
catch {
    Write-Host ''
    Write-Err $_.Exception.Message
    exit 1
}
