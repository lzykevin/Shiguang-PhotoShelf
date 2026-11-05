# 发布与更新维护说明

## 当前阶段

版本 1.0.0，构建号 10002。GitHub 仓库为 lzykevin/Shiguang-PhotoShelf。
保留 com.photoshelf.local 应用标识，使现有沙箱图库继续可用。
本地 `build.sh` 对 ad-hoc 构建关闭 Hardened Runtime，以允许加载 Sparkle；不会修改系统安全设置。正式 Archive/Export 必须使用 `ENABLE_HARDENED_RUNTIME=YES`，不能把本地构建配置用于公证。

目前没有 Developer ID Application 证书或 Apple 公证。不要将本地签名验证成功当成通过 Gatekeeper 分发检查。

Sparkle 固定为 2.10.1，通过 SPM 同时用于 Xcode 应用与 Swift 测试目标。沙箱使用 Installer/Downloader XPC 服务，不授予主应用整体网络权限。
更新源为 `https://raw.githubusercontent.com/lzykevin/Shiguang-PhotoShelf/main/updates/stable/appcast.xml`。GitHub 在某些网络下可能无法访问；更新失败应允许稍后重试，本地图库不依赖该服务。

## 密钥

Sparkle 公钥存于 Resources/Info.plist，允许公开。对应私钥已在发布者 Mac 登录钥匙串创建，账户名为 `photoshelf`；没有导出到工程。保持该钥匙串可用并自行安全备份，丢失私钥会影响既有用户接收更新。

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account photoshelf -p
```

上面只打印公钥。不要把私钥、P12、Apple API 密钥提交到仓库、Issue 或聊天。

## 发布流程

1. `swift test`、`./scripts/build.sh`、`python3 scripts/check_release.py build/Build/Products/Release/PhotoShelf.app`。
2. 实际打开测试构建，检查“检查更新”和更新设置；没有更新时应显示当前已是最新版本。
3. `./scripts/package-release.sh` 生成未公证 ZIP 及 SHA-256。只给理解未公证限制的测试者使用。
4. 创建 `v1.0.0` Release，说明签名限制和测试边界；验收后再发布。
5. **初版 appcast 保持为空**。源码发布或构建成功不是自动更新验收，不推送未经验证的包。

## 正式分发准备（需要 Apple Developer Program）

1. 在 Apple 开发者账号创建 Developer ID Application 证书并装入本机钥匙串。
2. 使用 Xcode Archive / Export（Developer ID）流程，确保 Sparkle 内部 XPC、Updater.app、Autoupdate 也使用自己的身份签名；不能只签外层应用。
3. 用 `xcrun notarytool` 提交 Apple 公证，检查 Accepted，并用 `xcrun stapler staple` 附加凭据。
4. `python3 scripts/check_release.py <app路径> --distribution` 检查应用签名、Gatekeeper 和公证凭据。
5. 将最终 app 打包 ZIP（保留符号链接）或 DMG，之后不要再修改包。
6. 使用 Sparkle 官方 `generate_appcast --help` 确认参数，以 `--account photoshelf` 从钥匙串签名；安装包下载地址使用对应 GitHub Release 固定版本资源 URL。保持构建号严格递增，更新清单必须包含正确版本、最低系统、包长度和 EdDSA 签名。
7. 在独立账户或另一台 Mac 用旧版实际升级到新版，验收签名拒绝、网络失败、取消与重试，并检查图库、评分、收藏、标签、相册及来源授权。
8. 先发布已验收的 Release 资产，验证下载，再提交生成的 stable appcast。更新资产不可覆盖。

## 自动化边界

仓库的 Build and test workflow 在 push / PR 自动测试、构建并验证 Sparkle 配置。它不持有发布密钥，也不自动发布未公证应用。
获得会员后可把签名、公证及草稿 Release 加入受保护的发布工作流。证书、Apple 凭证和 Sparkle 私钥使用专用 GitHub Actions Secrets；只在可信版本标签或人工批准的工作流中注入，不能给来自 fork 的 PR。

官方资料：
- https://sparkle-project.org/documentation/
- https://sparkle-project.org/documentation/sandboxing/
- https://sparkle-project.org/documentation/publishing/
- https://developer.apple.com/developer-id/
