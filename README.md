<p align="center">
  <img src="Lemon/Assets.xcassets/AppIcon.appiconset/appIcon256@2x.png" width="112" height="112" alt="cleaner icon" />
</p>

<h1 align="center">cleaner</h1>

<p align="center">
  <strong>轻量、纯粹、零遥测的 macOS 系统深度清理与状态栏监控工具</strong>
</p>

<p align="center">
  <a href="https://github.com/qg-hs/cleaner/releases/latest">
    <img src="https://img.shields.io/github/v/release/qg-hs/cleaner?style=flat-square&label=Release&color=f59e0b" alt="GitHub Release" />
  </a>
  <a href="https://github.com/qg-hs/cleaner/actions/workflows/package.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/qg-hs/cleaner/package.yml?style=flat-square&label=Build" alt="Build Status" />
  </a>
  <img src="https://img.shields.io/badge/macOS-12.0%2B-000000?style=flat-square&logo=apple" alt="macOS 12.0+" />
  <img src="https://img.shields.io/badge/Arch-arm64%20%7C%20x86__64%20%7C%20Universal-2563eb?style=flat-square" alt="Architectures" />
  <img src="https://img.shields.io/badge/License-GPLv2%20%2F%20GPLv3-10b981?style=flat-square" alt="License" />
</p>

---

## 核心特性

- **100% 本地扫描与隐私纯粹性**：移除全部遥测埋点、第三方崩溃收集、广告弹窗及私有服务端请求；除主动检查 GitHub Release 版本更新外，所有扫描与清理逻辑完全在本地离线执行。
- **深度定制扫描引擎**：针对 Xcode、Android Studio、微信、企业微信、QQ、Sketch、浏览器等上百款常用 macOS 应用定制缓存与日志清理规则。
- **多维磁盘空间治理**：
  - **大文件清理 (`LemonBigOldFile`)**：快速定位占用超过 50MB 的大文件与陈旧文件，支持自定义目录扫描。
  - **重复文件清理 (`LemonDuplicateFile`)**：基于哈希特征智能比对重复文件，安全释放冗余存储。
  - **相似照片清理 (`LemonPhotoClean`)**：智能识别相似与连拍照片，整理本地图库。
  - **磁盘空间分析 (`LemonSpaceAnalyse`)**：可视化树状图（TreeMap）直观展示磁盘目录占用分布。
  - **文件搬家 (`LemonFileMove`)**：一键将微信、QQ 等大体积应用产出文件迁移至外置存储。
- **系统守护与全量卸载**：
  - **应用彻底卸载 (`LemonUninstaller`)**：连根清除应用本体、偏好设置、LaunchAgents 与残留缓存，支持废纸篓拖入自动触发残留检测。
  - **开机启动项管理 (`LemonLoginItemManager`)**：统一管理系统 Login Items 与后台 LaunchAgents / LaunchDaemons 服务。
  - **浏览器隐私清理 (`LemonPrivacyClean`)**：支持 Safari、Chrome、Edge、Firefox 等多款浏览器的浏览记录、Cookie 与本地痕迹清理。
- **原生状态栏实时监控 (`LemonMonitor`)**：
  - 支持在 macOS 状态栏实时展示内存占用、磁盘空间、CPU 温度、风扇转速、实时上下行网速。
  - 浮窗一键释放内存、快速清理系统垃圾、监控高占网速与高占资源进程。
- **GitHub Releases 原生热更新 (`LMGitHubUpdater`)**：
  - 自动轮询 `qg-hs/cleaner` 最新 GitHub Release，发现新版本时自动点亮状态栏设置红点。
  - 支持在状态栏内一键下载对应当前 CPU 架构的安装包、校验解压、原子替换 `/Applications/cleaner.app` 并自动重启生效。

---

## 安装包下载

前往 [**GitHub Releases**](https://github.com/qg-hs/cleaner/releases/latest) 下载对应芯片架构的安装包：

| 适用机型 | DMG 磁盘映像 | ZIP 归档包 |
| :--- | :--- | :--- |
| **Apple Silicon (M1 / M2 / M3 / M4)** | [`cleaner-macos-arm64.dmg`](https://github.com/qg-hs/cleaner/releases/latest/download/cleaner-macos-arm64.dmg) | [`cleaner-macos-arm64.zip`](https://github.com/qg-hs/cleaner/releases/latest/download/cleaner-macos-arm64.zip) |
| **Intel (x86_64)** | [`cleaner-macos-x86_64.dmg`](https://github.com/qg-hs/cleaner/releases/latest/download/cleaner-macos-x86_64.dmg) | [`cleaner-macos-x86_64.zip`](https://github.com/qg-hs/cleaner/releases/latest/download/cleaner-macos-x86_64.zip) |
| **Universal (双架构通用版)** | [`cleaner-macos-universal.dmg`](https://github.com/qg-hs/cleaner/releases/latest/download/cleaner-macos-universal.dmg) | [`cleaner-macos-universal.zip`](https://github.com/qg-hs/cleaner/releases/latest/download/cleaner-macos-universal.zip) |

> **首次打开提示**：由于发行版采用本地 Ad-hoc 签名，首次打开若遇到 macOS Gatekeeper 拦截，可在终端执行以下命令移除隔离属性后直接运行：
> ```bash
> sudo xattr -cr /Applications/cleaner.app
> ```

---

## 模块架构

```text
cleaner
├── Lemon/                          # 主应用容器与主窗口 UI 控制层
├── LemonClener/                    # 核心扫描规则解析与清理执行引擎 (Framework)
├── Tools/
│   ├── LemonMonitor/               # macOS 状态栏常驻监控应用 & GitHub 热更新器 (LMGitHubUpdater)
│   ├── LemonDaemon/                # Root 提权辅助守护进程 (XPC 通信)
│   └── PrivacyProtect/             # 摄像头与麦克风隐私调用监控组件
├── localPod/                       # 模块化功能组件库 (CocoaPods 本地子模块)
│   ├── LemonBigOldFile/            # 大文件扫描与清理
│   ├── LemonDuplicateFile/         # 重复文件扫描与清理
│   ├── LemonPhotoClean/            # 相似照片识别与清理
│   ├── LemonUninstaller/           # 应用卸载与废纸篓残留监听
│   ├── LemonPrivacyClean/          # 浏览器隐私清理
│   ├── LemonLoginItemManager/      # 开机启动项与后台服务管理
│   ├── LemonSpaceAnalyse/          # 磁盘空间可视化分析
│   ├── LemonFileMove/              # 大文件外置存储迁移
│   ├── LemonHardware/              # 硬件传感器与系统信息采集
│   ├── LemonNetSpeed/              # 网络接口实时流量统计
│   ├── QMCoreFunction/             # 基础系统能力、XPC 客户端与通用工具
│   └── QMUICommon/                 # 公共 UI 组件库
├── scripts/
│   └── package.sh                  # 多架构自动化编译、Thinning、签名与 DMG/ZIP 打包脚本
└── .github/workflows/
    └── package.yml                 # GitHub Actions 矩阵构建与 Release 自动发布流水线
```

---

## 本地构建与打包

### 环境要求

- **操作系统**：macOS 12.0+
- **开发工具**：Xcode 15+ 及 Xcode Command Line Tools
- **依赖管理**：CocoaPods (`gem install cocoapods` 或 `brew install cocoapods`)

### 1. 安装依赖

```bash
pod install
```

### 2. 使用自动化脚本一键构建打包

项目内置 [`scripts/package.sh`](scripts/package.sh)，支持一键编译 `arm64`、`x86_64` 或 `universal`（包含自动 `lipo` 架构瘦身、由内向外递归 Ad-hoc 签名、生成 `.dmg` 与 `.zip` 及 `SHA256SUMS.txt`）：

```bash
# 仅构建打包 Apple Silicon (arm64)
./scripts/package.sh arm64

# 仅构建打包 Intel (x86_64)
./scripts/package.sh x86_64

# 仅构建打包双架构通用版 (arm64 + x86_64)
./scripts/package.sh universal

# 一次构建 Universal 并自动拆分产出 arm64 / x86_64 / universal 全部 6 个安装包
./scripts/package.sh all
```

所有打包产物将输出在项目根目录的 `dist/` 文件夹下。

---

## CI/CD 与版本热更新发布流程

项目通过 [`.github/workflows/package.yml`](.github/workflows/package.yml) 配置了完整的 GitHub Actions 流水线：

1. 修改 [`Lemon/Info.plist`](Lemon/Info.plist) 与 [`Tools/LemonMonitor/LemonMonitor/LemonMonitor-Info.plist`](Tools/LemonMonitor/LemonMonitor/LemonMonitor-Info.plist) 中的 `CFBundleShortVersionString`（例如升级至 `1.0.2`）。
2. 提交代码并推送带有 `v` 前缀的 Git Tag：
   ```bash
   git add -A
   git commit -m "release: v1.0.2"
   git tag v1.0.2
   git push origin master
   git push origin v1.0.2
   ```
3. GitHub Actions 将自动触发并行构建矩阵（`arm64` / `x86_64` / `universal`），并在构建完成后自动创建 `v1.0.2` GitHub Release 挂载全部 `.dmg`、`.zip` 和 `SHA256SUMS.txt`。
4. 已运行的 `cleaner` 状态栏客户端 (`LMGitHubUpdater`) 检测到新版本后将自动亮起设置红点，用户点击 **`发现新版本 v1.0.2（点击热更）`** 即可直接完成流式下载、解压替换与自动重启。

---

## 开源协议与强制署名声明 (License & Mandatory Attribution)

本项目遵循 **GPLv2 / GPLv3** 开源协议，并附加 **GPLv3 第 7(b) 条强制署名与来源标注条款 ([`NOTICE`](NOTICE) / [`LICENSE.txt`](LICENSE.txt))**：

1. `Tools/LemonDaemon` 模块遵循 **GNU General Public License v2.0 (GPLv2)** 协议。
2. 主工程 `Lemon`、`LemonMonitor` 及其他功能模块遵循 **GNU General Public License v3.0 (GPLv3)** 协议。
3. **强制署名要求（Mandatory Attribution Requirement）**：
   任何个人、团队或组织在使用、复制、修改、二次打包、分发本仓库代码，或基于本仓库开发衍生作品时，**必须在项目主页文档底部（README）、软件“关于”界面以及发行产物说明中显著保留并带上本仓库地址与作者介绍**，严禁移除、遮挡或篡改：

```markdown
---
### 致谢与上游来源 (Attribution)
本项目基于 **[cleaner](https://github.com/qg-hs/cleaner)** 二次开发/构建。
- **原项目仓库**：[https://github.com/qg-hs/cleaner](https://github.com/qg-hs/cleaner)（轻量、纯粹、零遥测的 macOS 系统深度清理与状态栏监控工具）
- **原作者**：[@qg-hs](https://github.com/qg-hs)
```

> 违反上述强制署名条款（如抹除仓库地址或作者信息进行二次分发）将依据 GPLv3 第 8 条自动终止全部开源授权，作者保留追究著作权侵权责任的权利。
