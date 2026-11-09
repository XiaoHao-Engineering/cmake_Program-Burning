# =============================================================================
#  cmake-flash-kit :: project.ps1
#  CMake 工程相关：构建目录定位 / 自动配置 / 编译 / 固件定位 / OpenOCD 目标芯片推断。
#  不依赖任何特定目录结构，任何 CMake 工程都能用。
#  兼容 Windows PowerShell 5.1 与 PowerShell 7+。
# =============================================================================

# 家族 -> OpenOCD target 配置名
function Get-TargetCfgName {
    param([string]$Family)

    $map = @{
        'F0' = 'stm32f0x'; 'F1' = 'stm32f1x'; 'F2' = 'stm32f2x'; 'F3' = 'stm32f3x'
        'F4' = 'stm32f4x'; 'F7' = 'stm32f7x'
        'H5' = 'stm32h5x'; 'H7' = 'stm32h7x'
        'L0' = 'stm32l0'; 'L1' = 'stm32l1'; 'L4' = 'stm32l4x'; 'L5' = 'stm32l5x'
        'G0' = 'stm32g0x'; 'G4' = 'stm32g4x'
        'WB' = 'stm32wbx'; 'WBA' = 'stm32wbax'; 'WL' = 'stm32wlx'
        'U5' = 'stm32u5x'; 'C0' = 'stm32c0x'; 'U0' = 'stm32u0x'
    }
    if ($map.ContainsKey($Family)) { return $map[$Family] }
    return $null
}

# 从任意文本里识别 STM32 家族（如 -DSTM32H723xx -> H7）
function Get-FamilyFromText {
    param([string]$Text)

    if (-not $Text) { return $null }

    # -DSTM32H723xx / STM32H723VGTx / startup_stm32h723xx.s
    $m = [regex]::Match($Text, 'STM32([A-Z]\d)([A-Z0-9]*)')
    if ($m.Success) {
        $fam = $m.Groups[1].Value
        if (Get-TargetCfgName $fam) { return $fam }
    }
    $m = [regex]::Match($Text, 'stm32([a-z]\d)([a-z0-9]*)')
    if ($m.Success) {
        $fam = $m.Groups[1].Value.ToUpperInvariant()
        if (Get-TargetCfgName $fam) { return $fam }
    }
    return $null
}

# 推断 OpenOCD target：配置优先，其次 CMakeCache / .ioc / 链接脚本 / 启动文件
function Resolve-Target {
    param(
        [string]$Root,
        [string]$BuildDir,
        [string]$Configured = 'auto'
    )

    if ($Configured -and $Configured -ne 'auto') {
        $name = $Configured
        if ($name -match '\.cfg$') {
            if (Test-Path -LiteralPath $name -PathType Leaf) {
                return [pscustomobject]@{ Target = (Get-Item -LiteralPath $name).FullName; Family = ''; Source = '配置(文件)' }
            }
            $name = [IO.Path]::GetFileNameWithoutExtension($name)
        }
        return [pscustomobject]@{ Target = $name; Family = ''; Source = '配置文件' }
    }

    # 1) CMakeCache 里的 -DSTM32xxxxxx
    if ($BuildDir) {
        $cache = Join-Path $BuildDir 'CMakeCache.txt'
        if (Test-Path -LiteralPath $cache) {
            $hit = Select-String -LiteralPath $cache -Pattern 'STM32([A-Z]\d)[A-Z0-9]*xx' -List -ErrorAction SilentlyContinue
            if ($hit) {
                $fam = Get-FamilyFromText $hit.Line
                if ($fam) {
                    return [pscustomobject]@{ Target = (Get-TargetCfgName $fam); Family = $fam; Source = 'CMakeCache' }
                }
            }
        }
    }

    # 2) .ioc（CubeMX）
    $ioc = @(Get-ChildItem -LiteralPath $Root -Filter '*.ioc' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($ioc.Count -gt 0) {
        $line = Select-String -LiteralPath $ioc[0].FullName -Pattern '^Mcu\.(Family|UserName)=' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($line) {
            $fam = Get-FamilyFromText $line.Line
            if ($fam) {
                return [pscustomobject]@{ Target = (Get-TargetCfgName $fam); Family = $fam; Source = $ioc[0].Name }
            }
        }
    }

    # 3) 链接脚本 / 启动文件
    $ld = @(Get-ChildItem -LiteralPath $Root -Filter '*_FLASH.ld' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($ld.Count -gt 0) {
        $fam = Get-FamilyFromText $ld[0].Name
        if ($fam) {
            return [pscustomobject]@{ Target = (Get-TargetCfgName $fam); Family = $fam; Source = $ld[0].Name }
        }
    }

    $startup = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter 'startup_stm32*.s' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1)
    if ($startup.Count -gt 0) {
        $fam = Get-FamilyFromText $startup[0].Name
        if ($fam) {
            return [pscustomobject]@{ Target = (Get-TargetCfgName $fam); Family = $fam; Source = $startup[0].Name }
        }
    }

    return [pscustomobject]@{ Target = ''; Family = ''; Source = '' }
}

# 定位构建目录
function Resolve-BuildDirectory {
    param([string]$Root, [string]$Configured = 'build')

    if (-not $Configured) { $Configured = 'build' }

    $candidates = @()
    if ([IO.Path]::IsPathRooted($Configured)) { $candidates += $Configured }
    else { $candidates += (Join-Path $Root $Configured) }

    if (-not [IO.Path]::IsPathRooted($Configured)) {
        foreach ($c in @('build', 'build\Debug', 'build\Release', 'cmake-build-debug', 'cmake-build-release',
                'cmake-build-relwithdebinfo', 'Debug', 'Release', 'out\build\Debug', 'out\build\Release')) {
            $candidates += (Join-Path $Root $c)
        }
    }

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'CMakeCache.txt')) {
            return [pscustomobject]@{ Path = $c; Ready = $true }
        }
    }
    return [pscustomobject]@{ Path = (Join-Path $Root $Configured); Ready = $false }
}

function Invoke-ProjectConfigure {
    param(
        [string]$Root,
        [string]$BuildDir,
        [string]$BuildType = 'Debug',
        [string]$CMake,
        [string]$Ninja,
        [string[]]$ExtraArgs = @(),
        [switch]$DryRun
    )

    $cmdArgs = @('-S', $Root, '-B', $BuildDir)
    if ($Ninja) {
        # 先拼成一个完整字符串：PowerShell 5.1 的数组字面量里直接写
        # '-DXXX=' + $var 会被拆成两个参数
        $ninjaArg = '-DCMAKE_MAKE_PROGRAM=' + $Ninja
        $cmdArgs += @('-G', 'Ninja', $ninjaArg)
    }
    $cmdArgs += ('-DCMAKE_BUILD_TYPE=' + $BuildType)
    if ($ExtraArgs) { $cmdArgs += $ExtraArgs }

    if ($DryRun) {
        Write-Detail ('> ' + (Format-NativeCommand -Exe $CMake -Arguments $cmdArgs))
        return 0
    }
    return (Invoke-Native -Exe $CMake -Arguments $cmdArgs -WorkDir $Root)
}

function Invoke-ProjectBuild {
    param(
        [string]$Root,
        [string]$BuildDir,
        [string]$BuildType = 'Debug',
        [string]$CMake,
        [switch]$DryRun
    )

    $cmdArgs = @('--build', $BuildDir, '--config', $BuildType, '--parallel')
    if ($DryRun) {
        Write-Detail ('> ' + (Format-NativeCommand -Exe $CMake -Arguments $cmdArgs))
        return 0
    }
    return (Invoke-Native -Exe $CMake -Arguments $cmdArgs -WorkDir $Root)
}

# 读取 CMakeCache 中的工程名
function Get-ProjectNameFromCache {
    param([string]$BuildDir)

    $cache = Join-Path $BuildDir 'CMakeCache.txt'
    if (-not (Test-Path -LiteralPath $cache)) { return $null }
    $line = Select-String -LiteralPath $cache -Pattern '^CMAKE_PROJECT_NAME:STATIC=' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($line) {
        $v = $line.Line.Substring($line.Line.IndexOf('=') + 1).Trim()
        if ($v) { return $v }
    }
    return $null
}

# 固件定位：配置优先 -> 工程名匹配 -> 最新生成的 .elf
function Find-ElfFile {
    param(
        [string]$BuildDir,
        [string]$Configured = 'auto',
        [string]$ProjectName = ''
    )

    if ($Configured -and $Configured -ne 'auto') {
        if (Test-Path -LiteralPath $Configured -PathType Leaf) { return (Get-Item -LiteralPath $Configured).FullName }
        $alt = Join-Path $BuildDir $Configured
        if (Test-Path -LiteralPath $alt -PathType Leaf) { return (Get-Item -LiteralPath $alt).FullName }
        return $null
    }

    if (-not (Test-Path -LiteralPath $BuildDir)) { return $null }

    $elves = @(Get-ChildItem -LiteralPath $BuildDir -Recurse -Filter '*.elf' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\CMakeFiles\\' })

    if ($elves.Count -eq 0) { return $null }
    if ($elves.Count -eq 1) { return $elves[0].FullName }

    if ($ProjectName) {
        $hit = @($elves | Where-Object { $_.BaseName -eq $ProjectName })
        if ($hit.Count -gt 0) {
            return ($hit | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
        }
    }

    return ($elves | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
