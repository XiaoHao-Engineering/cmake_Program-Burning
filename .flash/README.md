# .flash —— 工程内的烧录工具

这个目录由 `cmake-flash-kit` 的 `install.ps1` 复制而来，**不要手动改脚本**（升级时会被覆盖），
要改行为请改 `flash.config.json`。

## 最常用

```powershell
.\.flash\flash.ps1              # 编译 + 自动识别下载器 + 烧录
.\.flash\flash.ps1 -NoBuild     # 只烧录
.\.flash\flash.ps1 -ListProbes  # 看现在插了哪些下载器
```

VS Code 里直接按 `Ctrl+Shift+B`（默认构建任务就是"编译并烧录"）。

## 出问题先看这里

| 现象 | 处理 |
| --- | --- |
| 没检测到下载器 | 换 USB 口；确认设备管理器有 ST-Link / CMSIS-DAP；检查 SWDIO/SWCLK/GND |
| DAPLink 烧录超时 | 把 `speed` 改成 `1000`（克隆 DAPLink 跑不了 10 MHz） |
| 一连接就断开 | 用 `-UnderReset`，旧程序带看门狗时会这样 |
| 提示读保护 | 先用 STM32CubeProgrammer 解除 RDP |
| 找不到 OpenOCD | 首次运行会自动下载到 `%LOCALAPPDATA%\flashkit`；离线时手动填 `openocd` 路径 |

## 配置文件

`flash.config.json` 的每个字段都有注释，见仓库根目录 README。
