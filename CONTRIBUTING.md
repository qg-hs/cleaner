# 贡献指南 (Contributing)

欢迎使用 **cleaner** 并参与项目共建。如发现 Bug、性能瓶颈或有新功能建议，欢迎提交 [Issues](https://github.com/qg-hs/cleaner/issues) 或 [Pull Requests](https://github.com/qg-hs/cleaner/pulls)。

## 提交 Issue

在提交 Issue 前请确认：

1. 属于明确的缺陷修复、性能优化或新功能提案。
2. 已检索现有 Issues，确保不存在重复问题。
3. 附上复现步骤、macOS 系统版本、芯片架构（Apple Silicon `arm64` 或 Intel `x86_64`）以及相关日志信息（如 `~/Library/Logs/LemonMonitor.log`）。

## 提交 Pull Request

在发起 Pull Request 前请确保：

1. **零遥测与隐私合规**：严禁引入任何第三方统计埋点、广告外链或未经用户显式触发的后台网络请求。
2. **多架构兼容**：代码需同时通过 `arm64` 与 `x86_64` 编译校验（可通过 `./scripts/package.sh all` 本地验证）。
3. **编译规范**：`LemonMonitor` 等模块开启了 `-std=gnu89` 编译标准，请确保 C 循环变量声明在循环头外部或使用标准 Objective-C 语法。
4. **文档同步**：涉及构建流程、配置项或核心交互变更时，请同步更新 `README.md`。
