# cmake-flash-kit

> 给**任意 CMake 工程**装上一键烧录：VS Code 里按 `Ctrl+Shift+B`，自动配置 → 编译 → 识别下载器 → 烧录 → 校验 → 复位。
> 同时支持 **ST-Link** 和 **DAPLink（CMSIS-DAP）**，不需要每个新工程重新配一遍。

---

## 为什么需要它

用 CMake 做 STM32 开发时，每开一个新工程都要重复一遍这些事：

- 写 `.vscode/tasks.json`，还要让它成为 `Ctrl+Shift+B` 的默认构建任务；
- 配 OpenOCD 的 `interface/*.cfg` 和 `target/*.cfg`；
- 这个工程用 ST-Link、那个工程用 DAPLink，cfg 又不一样；
- SWD 速度、复位连接、看门狗、`.elf` 路径、构建目录名（`build` / `cmake-build-debug`）各不相同；
- 换台电脑，OpenOCD / arm-none-eabi-gcc 的路径又全变了。

这套工具把这些全部自动化，只保留**一个约定**：工程根目录下有一个 `.flash/` 目录和一个 `flash.config.json`。

---

## 功能一览

| 能力 | 说明 |
| --- | --- |
| 一键烧录 | `Ctrl+Shift+B`：配置（按需）→ 编译 → 烧录 → 校验 → 复位运行 |
| 双下载器 | 自动识别 ST-Link / DAPLink（CMSIS-DAP），也支持手动指定 |
| 自动找工具链 | arm-none-eabi-gcc、cmake、ninja：PATH、STM32 VS Code 扩展、STM32CubeIDE、EIDE、PlatformIO、CLion 都会找 |
| 自动装 OpenOCD | 找不到时自动下载 xPack OpenOCD 到 `%LOCALAPPDATA%\flashkit`（不污染系统） |
| 自动认芯片 | 从 CMakeCache 的 `-DSTM32xxxxxx`、`.ioc`、链接脚本、startup 文件推断 OpenOCD target |
| 首次自动配置 | 没有 `build/CMakeCache.txt` 时自动执行 `cmake -S . -B build -G Ninja` |
| 自动降速重试 | 烧录失败且疑似速度问题时，自动 2000 → 1000 → 500 kHz 重试 |
| 复位时连接 | `-UnderReset`，专治「旧程序带看门狗，一连就断」 |
| 固件格式 | `.elf` / `.hex` / `.bin`（bin 可配起始地址） |
| 兼容性 | Windows PowerShell 5.1 与 PowerShell 7 都能跑；路径含空格 / 中文已实测 |
| CMake 集成 | 可选 `FlashKit.cmake`，给 CLion / 命令行提供 `flash`、`flash-stlink`、`flash-daplink` target |

---

## 快速开始

### 步骤 1：把工具放到一个固定位置

```powershell
git clone https://github.com/XiaoHao-Engineering/cmake_Program-Burning.git C:\tools\cmake_Program-Burning
```

### 步骤 2：装进你的 CMake 工程

```powershell
cd D:\your_cmake_project
C:\tools\cmake_Program-Burning\install.ps1 -Project .
```

安装器会做三件事：

1. 把 `.flash/` 复制到工程根目录；
2. 生成 `.flash/flash.config.json`（工程名、构建目录、下载器等）；
3. 生成或**合并** `.vscode/tasks.json`，把 `Flash: 编译并烧录` 设为默认构建任务。

### 步骤 3：VS Code 打开工程，按 `Ctrl+Shift+B`

```
==> 检查工具链
  OK  arm-none-eabi-gcc: ...\gnu-tools-for-stm32\14.3.1+st.2\bin\arm-none-eabi-gcc.exe
  OK  cmake: ...\cmake\4.3.1+st.1\bin\cmake.exe
==> 编译固件
  ...
==> 定位固件
  OK  ...\build\your_project.elf
==> 准备 OpenOCD
  OK  C:\Users\you\AppData\Local\flashkit\openocd\0.12.0-7\...\bin\openocd.exe
  OK  target: stm32h7x  (来源: your_project.ioc)
==> 识别下载器
  OK  DAPLink  FAED:4873  Horco CMSIS-DAP v2
==> 烧录中（DAPLink @ 2000 kHz）
  ** Verified OK **
  OK  烧录成功，用时 2.4 s
```

之后每次改代码，只需要再按一次 `Ctrl+Shift+B`。

---

## 三种使用方式，按需选择

### A. 工具集中放一处，各工程共享（推荐）

```powershell
C:\tools\cmake_Program-Burning\install.ps1 -Project D:\proj_a
C:\tools\cmake_Program-Burning\install.ps1 -Project D:\proj_b
```

升级工具时重新 clone，再对每个工程跑一次 `install.ps1 -Force` 即可。

### B. 随工程进版本库（团队协作友好）

把 `.flash/` 和 `.vscode/tasks.json` 一起提交进 Git，同事 clone 下来直接 `Ctrl+Shift+B`，不需要装任何额外东西（OpenOCD 首次会自动下载）。

```powershell
cd D:\your_cmake_project
C:\tools\cmake_Program-Burning\install.ps1 -Project .
git add .flash .vscode
git commit -m "chore: 加入 cmake-flash-kit 一键烧录"
```

### C. 作为 submodule

```powershell
git submodule add https://github.com/XiaoHao-Engineering/cmake_Program-Burning.git tools/cmake-flash-kit
tools/cmake-flash-kit/install.ps1 -Project .
```

---

## 命令速查

```powershell
# 编译 + 自动识别下载器 + 烧录
.\.flash\flash.ps1

# 只烧录，不编译
.\.flash\flash.ps1 -NoBuild

# 强制指定下载器
.\.flash\flash.ps1 -Probe stlink
.\.flash\flash.ps1 -Probe daplink

# 旧程序带看门狗时
.\.flash\flash.ps1 -UnderReset

# 看看现在插了哪些下载器
.\.flash\flash.ps1 -ListProbes

# 只打印将要执行的命令，不真正执行
.\.flash\flash.ps1 -DryRun

# 指定速度 / 芯片 / 固件 / 构建目录
.\.flash\flash.ps1 -Speed 1000 -Target stm32h7x -Elf .\build\app.elf -BuildDir build
```

VS Code 里对应的任务（`Ctrl+Shift+P` → `Tasks: Run Task`）：

- `Flash: 编译并烧录（自动识别 ST-Link / DAPLink）` ← `Ctrl+Shift+B` 默认任务
- `Flash: 仅烧录（不编译）`
- `Flash: 使用 ST-Link`
- `Flash: 使用 DAPLink`
- `Flash: 复位时连接（旧程序带看门狗时用）`
- `Flash: 列出已连接的下载器`

---

## 配置文件 `flash.config.json`

```jsonc
{
  "projectName": "my_project",     // 仅用于显示 / .elf 匹配
  "target": "auto",                // OpenOCD target，如 stm32h7x；auto = 自动推断
  "probe": "auto",                 // auto | stlink | daplink
  "probeSerial": "",               // 同时插了多个下载器时，用序列号指定
  "speed": 0,                      // SWD kHz；0 = 自动（ST-Link 4M / DAPLink 2M）
  "buildDir": "build",             // 构建目录
  "buildType": "Debug",            // CMAKE_BUILD_TYPE
  "configureArgs": [],             // 额外给 cmake 的参数，如 ["-DCMAKE_TOOLCHAIN_FILE=..."]
  "elf": "auto",                   // 固件路径；auto = 自动查找
  "openocd": "auto",               // openocd.exe 路径；auto = 自动搜索
  "openocdVersion": "0.12.0-7",    // 自动安装的 xPack OpenOCD 版本
  "autoInstallOpenOCD": true,      // 找不到时是否自动下载
  "connectUnderReset": false,      // 复位时连接
  "verify": true,                  // 烧录后校验
  "extraOpenocdConfig": [],        // 追加的 OpenOCD -c 命令
  "binAddress": "0x08000000",      // 烧 .bin 时的起始地址
  "autoSpeedFallback": true        // 失败自动降速重试
}
```

> 配置项在每次运行时读取，改完不需要重新安装。

---

## 它是怎么工作的

```
Ctrl+Shift+B
   │
   ├─ 读取 .flash/flash.config.json
   ├─ 找 arm-none-eabi-gcc / cmake / ninja（PATH → ST 扩展 → CubeIDE → EIDE → CLion → …）
   ├─ 构建目录没有 CMakeCache.txt？ → cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=…
   ├─ cmake --build build
   ├─ 找 .elf（优先与工程同名，其次最新的）
   ├─ 找 OpenOCD（PATH → 常见安装目录 → 自动下载 xPack 到 %LOCALAPPDATA%\flashkit）
   ├─ 推断 target：CMakeCache 的 -DSTM32H723xx → stm32h7x
   ├─ 枚举 USB：ST-Link（VID 0483）/ DAPLink（VID 0D28、C251、FAED… + 设备名匹配）
   └─ openocd -f interface/stlink.cfg|cmsis-dap.cfg
              -f target/stm32h7x.cfg
              -c "adapter speed 2000"
              -c "program {…/app.elf} verify reset exit"
```

推断芯片家族的优先级：`flash.config.json` → `CMakeCache.txt` 里的 `-DSTM32xxxxxx` → `*.ioc` → `*_FLASH.ld` → `startup_stm32*.s`。

---

## 已实测环境

| 项目 | 版本 / 结果 |
| --- | --- |
| 芯片 | STM32H723VGT6（DBGMCU ID `0x483`，1 MB Flash） |
| 下载器 | Horco CMSIS-DAP v2（`FAED:4873`），DAPLink 模式 |
| OpenOCD | xPack 0.12.0-7 |
| 工具链 | GNU Tools for STM32 14.3.1（ST VS Code 扩展自带） |
| CMake / Ninja | 4.3.1 / 1.13.2 |
| 结果 | 编译 94 个目标 → 烧录 + 校验 2.4 s，`Verified OK` |
| 路径 | 含中文（`开源工程`）与长路径，正常 |

> 说明：本工具在 Windows 10/11 上测试。Linux / macOS 用户可参考脚本自行改写，核心逻辑（找工具 → 构建 → openocd 命令）是通用的。

---

## 常见问题

**1. 提示「没有检测到任何下载器」**

- 换 USB 口、直连不用 Hub；
- 设备管理器看有没有 `ST-Link` 或 `CMSIS-DAP`，有黄色感叹号就先装驱动；
- 检查 SWDIO / SWCLK / GND 与目标板供电；
- DAPLink 必须是 **CMSIS-DAP 固件**，不能是"拖拽 U 盘"模式的和气 DAPLink。

**2. DAPLink 烧录超时 / `Error: init mode failed`**

克隆 DAPLink 普遍跑不到 10 MHz（很多教程里的 `adapter speed 10000` 是失败主因）。把 `speed` 改成 `1000`，或直接依赖自动降速重试。

**3. 一连接就断开 / `target not halted`**

旧程序里开了看门狗（如本仓库隔壁的 `dm02_test`，`MX_IWDG1_Init` 在 `main` 里就启动），一上电就复位，SWD 抓不住。用 `-UnderReset`（任务：`Flash: 复位时连接`）。

**4. 烧录成功但程序不跑**

- 检查 `BOOT0` 是否被拉高（应从 Flash 启动）；
- 确认 `.ld` 里 `FLASH ORIGIN = 0x08000000`；
- 外部晶振（HSE）频率和代码里 `HSE_VALUE` 是否一致，不一致会卡在 `SystemClock_Config`。

**5. 芯片被读保护（RDP）**

先用 STM32CubeProgrammer 解除保护（会全片擦除），再回来烧录。

**6. `cmake` 配置阶段失败**

- 老工程 `cmake_minimum_required(VERSION 3.x < 3.5)` 在 CMake 4 上会直接报错，需要改成 `3.5` 以上；
- 需要工具链文件的工程，用 `configureArgs` 传 `-DCMAKE_TOOLCHAIN_FILE=...`。

**7. 公司网络 / 离线，下载不了 OpenOCD**

手动下载 xPack OpenOCD 解压后，把 `flash.config.json` 的 `openocd` 改成 `openocd.exe` 的绝对路径，或把 `bin` 目录加进 PATH。

**8. 同时插了 ST-Link 和 DAPLink**

默认用 ST-Link（会有提示）。用 `-Probe daplink` 临时切换，或在配置里固定 `"probe": "daplink"`；同类多个时用 `probeSerial`。

**9. 想用 CLion**

`include(${CMAKE_CURRENT_LIST_DIR}/.flash/cmake/FlashKit.cmake)` 之后：

```powershell
cmake --build build --target flash
```

CLion 里把 `flash` target 加进 Run Configuration，或给 `Build` 绑一个快捷键即可。

---

## 目录结构

```
cmake_Program-Burning/
├─ install.ps1                     # 安装到任意 CMake 工程
├─ .flash/
│  ├─ flash.ps1                    # 主入口
│  ├─ flash.config.json            # 工程配置
│  ├─ flash.config.schema.json     # 配置的 JSON Schema（编辑器自动补全）
│  ├─ lib/
│  │  ├─ common.ps1                # 输出 / 外部命令
│  │  ├─ env.ps1                   # 工具链与 OpenOCD 发现、自动安装
│  │  ├─ probe.ps1                 # ST-Link / DAPLink 识别
│  │  └─ project.ps1               # CMake 构建 / 固件定位 / 芯片推断
│  └─ cmake/FlashKit.cmake         # 可选的 CMake target 集成
├─ .vscode/tasks.json              # 任务模板（Ctrl+Shift+B）
└─ README.md
```

---

## 卸载

```powershell
Remove-Item -Recurse -Force .flash
# 再删掉 .vscode/tasks.json 里 label 以 "Flash:" 开头的任务即可
```

工具不会改系统环境变量，也不会往系统目录写东西；自动下载的 OpenOCD 在 `%LOCALAPPDATA%\flashkit`，直接删掉即可。

---

## License

MIT
