# cmake-flash-kit

**一条命令，把「Ctrl+Shift+B 一键烧录」装进任意 CMake 工程。**

支持 ST-Link / DAPLink，工具链和 OpenOCD 全自动查找，缺了自动下载。不绑定 CubeMX 目录结构，不要求工程改名，不污染系统环境。

```
cmake -S . -B build  →  cmake --build  →  识别探针  →  openocd program  →  verify  →  reset
```

---

## 解决什么

每开一个新 CMake 工程，烧录都要重配一遍：`.vscode/tasks.json`、OpenOCD 的 `interface/target cfg`、SWD 速度、`.elf` 路径、构建目录名；换台电脑，`arm-none-eabi-gcc` 和 `openocd` 的路径又全变了；这个工程用 ST-Link、那个用 DAPLink，配置还得改。

本工具把这些收敛成 **一个 `.flash/` 目录 + 一次安装**，之后每个工程的手感完全一致。

## 30 秒上手

```powershell
git clone https://github.com/XiaoHao-Engineering/cmake_Program-Burning.git C:\tools\cmake_Program-Burning
cd D:\你的CMake工程
C:\tools\cmake_Program-Burning\install.ps1 -Project .
```

然后用 VS Code 打开该工程，按 **`Ctrl+Shift+B`**：

```
==> 编译固件            ninja: no work to do.
==> 定位固件            build\your_project.elf
==> 准备 OpenOCD        target: stm32h7x  (来源: your_project.ioc)
==> 识别下载器          DAPLink  FAED:4873  Horco CMSIS-DAP v2
==> 烧录中 (@2000 kHz)  ** Verified OK **
  OK  烧录成功，用时 2.4 s
```

`install.ps1` 只做三件事：复制 `.flash/`、生成 `flash.config.json`、把烧录任务**合并**进 `.vscode/tasks.json` 并设为唯一默认构建任务——所以 `Ctrl+Shift+B` 不会再弹"选择任务"。

## 优势

| | 说明 |
|---|---|
| **真·一键** | `Ctrl+Shift+B` = 配置（按需）→ 编译 → 烧录 → 校验 → 复位，改完代码按一下就行 |
| **双下载器** | ST-Link 与 DAPLink（CMSIS-DAP）自动识别，也支持 `-Probe` 强制指定 |
| **零手配工具链** | gcc / cmake / ninja 自动从 PATH、STM32 VS Code 扩展、CubeIDE、EIDE、PlatformIO、CLion 里找 |
| **OpenOCD 自举** | 没装就自动下载 xPack 0.12 到 `%LOCALAPPDATA%\flashkit`，可随时删除 |
| **自动认芯片** | 由 `-DSTM32H723xx` / `.ioc` / `*_FLASH.ld` / `startup_*.s` 推断 `stm32h7x` 等 target，无需填表 |
| **失败自愈** | 烧录失败自动降速重试（2000 → 1000 → 500 kHz）；`-UnderReset` 专治旧程序带看门狗 |
| **随处可跑** | 路径含中文/空格、PowerShell 5.1 与 7、`build` 与 `cmake-build-debug` 都能直接用 |

## 常用命令

```powershell
.\.flash\flash.ps1              # 编译 + 自动识别 + 烧录（= Ctrl+Shift+B）
.\.flash\flash.ps1 -NoBuild     # 只烧录
.\.flash\flash.ps1 -ListProbes  # 看当前插了哪些下载器
.\.flash\flash.ps1 -UnderReset  # 复位时连接（旧程序带看门狗）
.\.flash\flash.ps1 -DryRun      # 只打印命令，不执行
```

VS Code 任务面板（`Ctrl+Shift+P` → `Tasks: Run Task`）内置 6 个任务：默认烧录、仅烧录、强制 ST-Link、强制 DAPLink、复位时连接、列出下载器。

## 配置

`.flash/flash.config.json`，通常只需要改这几项，其余保持 `auto` 即可：

| 字段 | 默认 | 说明 |
|---|---|---|
| `probe` | `auto` | `auto` / `stlink` / `daplink` |
| `speed` | `0` | SWD kHz，0 = 自动（DAPLink 2 MHz，ST-Link 4 MHz） |
| `target` | `auto` | OpenOCD target，如 `stm32h7x` |
| `buildDir` | `build` | 构建目录 |
| `configureArgs` | `[]` | 额外 cmake 参数，如工具链文件 |

完整字段（含注释）见 [`flash.config.schema.json`](.flash/flash.config.schema.json)。

## 常见问题

- **提示"没有检测到下载器"**：换 USB 口、检查 SWDIO/SWCLK/GND 与目标板供电；DAPLink 必须是 CMSIS-DAP 固件。
- **DAPLink 烧录超时**：克隆 DAPLink 跑不到 10 MHz，把 `speed` 设为 `1000`（工具也会自动降速重试）。
- **一连接就断开**：旧程序开了看门狗，用 `-UnderReset`。
- **烧完不运行**：查 `BOOT0`、`.ld` 的 `FLASH ORIGIN`、`HSE_VALUE` 与晶振是否一致。
- **想用 CLion**：`include(.flash/cmake/FlashKit.cmake)` 后 `cmake --build build --target flash`。

## 已验证

| 环境 | 结果 |
|---|---|
| STM32H723VGT6 + Horco CMSIS-DAP v2（DAPLink） | 编译 + 烧录 + 校验 **2.4 s**，`Verified OK` |
| 空工程从零开始（无 build、无配置） | 自动配置 + 编译 + 烧录 **2.1 s** |
| GCC 14.3.1 / CMake 4.3.1 / Ninja 1.13.2，中文路径 | 全部通过，PowerShell 5.1 与 7 均验证 |

## 目录

```
install.ps1                 # 装到任意 CMake 工程
.flash/flash.ps1            # 主入口：配置→编译→识别→烧录
.flash/lib/                 # 工具链发现 / 探针识别 / 构建与芯片推断
.flash/cmake/FlashKit.cmake # 可选的 CMake target（CLion / 命令行）
.vscode/tasks.json          # 任务模板（默认 Ctrl+Shift+B）
```

## License

MIT
