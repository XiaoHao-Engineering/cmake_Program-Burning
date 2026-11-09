# =============================================================================
#  cmake-flash-kit :: env.ps1
#  工具链自动发现：arm-none-eabi-gcc / cmake / ninja / openocd
#  以及 OpenOCD 的按需自动安装。
#  兼容 Windows PowerShell 5.1 与 PowerShell 7+。
# =============================================================================

# ---------------------------------------------------------------------------
#  arm-none-eabi-gcc
# ---------------------------------------------------------------------------
function Find-ArmGcc {
    $onPath = Get-Command 'arm-none-eabi-gcc.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $bundles = Join-Path $env:LOCALAPPDATA 'STM32Cube\bundles'
    $patterns = @(
        (Join-Path $bundles 'gnu-tools-for-stm32\*\bin\arm-none-eabi-gcc.exe'),
        (Join-Path $env:USERPROFILE 'STM32Cube\bundles\gnu-tools-for-stm32\*\bin\arm-none-eabi-gcc.exe'),
        'C:\ST\STM32CubeIDE*\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.*\tools\bin\arm-none-eabi-gcc.exe',
        'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeIDE\*\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.*\tools\bin\arm-none-eabi-gcc.exe',
        (Join-Path $env:USERPROFILE '.eide\tools\gcc-arm-none-eabi*\bin\arm-none-eabi-gcc.exe'),
        (Join-Path $env:USERPROFILE '.eide\tools\gcc_arm*\bin\arm-none-eabi-gcc.exe'),
        (Join-Path $env:USERPROFILE '.platformio\packages\toolchain-gccarmnoneeabi\bin\arm-none-eabi-gcc.exe'),
        (Join-Path $env:USERPROFILE '.xpack\arm-none-eabi-gcc\*\bin\arm-none-eabi-gcc.exe'),
        'C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\*\bin\arm-none-eabi-gcc.exe',
        'C:\Program Files\Arm GNU Toolchain arm-none-eabi\*\bin\arm-none-eabi-gcc.exe',
        'C:\SysGCC\arm-eabi\bin\arm-none-eabi-gcc.exe'
    )
    return Find-FirstFile -Patterns $patterns
}

# ---------------------------------------------------------------------------
#  cmake
# ---------------------------------------------------------------------------
function Find-CMake {
    $onPath = Get-Command 'cmake.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $bundles = Join-Path $env:LOCALAPPDATA 'STM32Cube\bundles'
    $patterns = @(
        (Join-Path $bundles 'cmake\*\bin\cmake.exe'),
        'C:\Program Files\CMake\bin\cmake.exe',
        'C:\Program Files (x86)\CMake\bin\cmake.exe',
        'C:\Program Files\JetBrains\CLion*\bin\cmake\win\x64\bin\cmake.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\CLion*\bin\cmake\win\x64\bin\cmake.exe'),
        'C:\Program Files\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    )
    return Find-FirstFile -Patterns $patterns
}

# ---------------------------------------------------------------------------
#  ninja
# ---------------------------------------------------------------------------
function Find-Ninja {
    $onPath = Get-Command 'ninja.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $bundles = Join-Path $env:LOCALAPPDATA 'STM32Cube\bundles'
    $patterns = @(
        (Join-Path $bundles 'ninja\*\bin\ninja.exe'),
        'C:\Program Files\JetBrains\CLion*\bin\ninja\win\x64\ninja.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\CLion*\bin\ninja\win\x64\ninja.exe'),
        (Join-Path $env:USERPROFILE '.eide\tools\ninja*\ninja.exe'),
        'C:\Program Files\CMake\bin\ninja.exe'
    )
    return Find-FirstFile -Patterns $patterns
}

# ---------------------------------------------------------------------------
#  openocd
# ---------------------------------------------------------------------------
function Get-OpenOcdManagedRoot {
    return (Join-Path $env:LOCALAPPDATA 'flashkit\openocd')
}

function Find-OpenOcd {
    param([string]$Configured = 'auto')

    $root = Get-OpenOcdManagedRoot

    if ($Configured -and $Configured -ne 'auto') {
        if (Test-Path -LiteralPath $Configured -PathType Leaf) {
            return (Get-Item -LiteralPath $Configured).FullName
        }
        if (Test-Path -LiteralPath $Configured -PathType Container) {
            $hit = Get-ChildItem -LiteralPath $Configured -Recurse -Filter 'openocd.exe' -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
        return $null
    }

    $onPath = Get-Command 'openocd.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $patterns = @(
        (Join-Path $root '*\bin\openocd.exe'),
        (Join-Path $root '*\*\bin\openocd.exe'),
        'C:\Program Files\OpenOCD*\bin\openocd.exe',
        'C:\Program Files (x86)\OpenOCD*\bin\openocd.exe',
        'C:\OpenOCD*\bin\openocd.exe',
        (Join-Path $env:USERPROFILE '.eide\tools\openocd*\bin\openocd.exe'),
        (Join-Path $env:USERPROFILE '.eide\tools\openocd*\*\bin\openocd.exe'),
        (Join-Path $env:USERPROFILE '.platformio\packages\tool-openocd\bin\openocd.exe'),
        (Join-Path $env:USERPROFILE 'scoop\apps\openocd\current\bin\openocd.exe'),
        'C:\ProgramData\chocolatey\bin\openocd.exe',
        'C:\ST\STM32CubeIDE*\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.openocd.win32_*\tools\bin\openocd.exe',
        'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeIDE\*\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.openocd.win32_*\tools\bin\openocd.exe'
    )
    return Find-FirstFile -Patterns $patterns
}

# 找到 openocd 的 scripts 目录（-s 参数），找不到返回 $null
function Get-OpenOcdScripts {
    param([string]$OpenOcdExe)

    if (-not $OpenOcdExe) { return $null }
    $bin = Split-Path -Parent $OpenOcdExe
    $candidates = @(
        (Join-Path $bin '..\openocd\scripts'),
        (Join-Path $bin '..\share\openocd\scripts'),
        (Join-Path $bin '..\..\openocd\scripts'),
        (Join-Path $bin '..\..\share\openocd\scripts'),
        (Join-Path $bin 'scripts'),
        'C:\Program Files\OpenOCD\share\openocd\scripts'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'target\stm32h7x.cfg')) { return (Resolve-Path -LiteralPath $c).Path }
        if (Test-Path -LiteralPath (Join-Path $c 'target')) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

# 从 GitHub 下载 xPack OpenOCD 并解压到 %LOCALAPPDATA%\flashkit\openocd\<版本>
function Install-OpenOcd {
    param([string]$Version = '0.12.0-7')

    $root = Get-OpenOcdManagedRoot
    $dest = Join-Path $root $Version
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    $fileName = "xpack-openocd-$Version-win32-x64.zip"
    $url = "https://github.com/xpack-dev-tools/openocd-xpack/releases/download/v$Version/$fileName"
    $zip = Join-Path $env:TEMP $fileName

    Write-Info "下载 OpenOCD $Version ..."
    Write-Info $url

    # Windows PowerShell 5.1 默认不启用 TLS 1.2
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch { }

    $ok = $false
    for ($i = 1; $i -le 3; $i++) {
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 300
            $ok = $true
            break
        }
        catch {
            Write-Warn ("第 $i 次下载失败：" + $_.Exception.Message)
            Start-Sleep -Seconds (2 * $i)
        }
    }
    if (-not $ok) { return $null }

    Write-Info '解压中 ...'
    try {
        Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
    }
    catch {
        Write-Warn ('解压失败：' + $_.Exception.Message)
        return $null
    }
    finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    }

    $exe = Get-ChildItem -LiteralPath $dest -Recurse -Filter 'openocd.exe' -File -ErrorAction SilentlyContinue |
        Sort-Object FullName | Select-Object -First 1
    if ($exe) { return $exe.FullName }
    return $null
}

# 确保能拿到 openocd：找不到就按配置自动安装
function Ensure-OpenOcd {
    param(
        [string]$Configured = 'auto',
        [string]$Version = '0.12.0-7',
        [bool]$AutoInstall = $true
    )

    $exe = Find-OpenOcd -Configured $Configured
    if ($exe) { return $exe }

    if (-not $AutoInstall) { return $null }

    Write-Warn '未找到 OpenOCD，尝试自动下载安装到用户目录 ...'
    $exe = Install-OpenOcd -Version $Version
    if ($exe) {
        Write-Ok ("OpenOCD 已安装：" + $exe)
        return $exe
    }
    return $null
}

# 生成"PATH 增强版"环境：把 gcc / cmake / ninja 所在目录前置
function Get-ToolchainEnv {
    param(
        [string]$ArmGcc,
        [string]$CMake,
        [string]$Ninja
    )

    $add = @()
    foreach ($p in @($ArmGcc, $CMake, $Ninja)) {
        if ($p) {
            $d = Split-Path -Parent $p
            if ($d -and ($add -notcontains $d)) { $add += $d }
        }
    }
    if ($add.Count -eq 0) { return $env:PATH }
    return (($add -join ';') + ';' + $env:PATH)
}
