# Powercuff 1.3.6 上传源码构建说明

## 来源与范围

- 输入：用户上传的 `powercuff-repair-source-unverified.tar.gz`。
- 输入归档 SHA-256：`e7e9ef279e1bf4997799088e26fb1a68fb5f62dea1ccfefd74530748202f5151`。
- 比较基线：已发布 v1.3.5，提交 `392e11c4bbf5ca5baf8c9e5a139423f51fea0ba0`。
- 输入目录名为 powercuff-1.3.6，control/README 仍写 1.3.5；本次统一发行元数据为 1.3.6。
- 运行源码、维护脚本及其回归测试使用上传内容；本次补齐版本、说明、构建发布流程及版本化 arm64e ABI 门禁。这不是一次新的全量源码审计。

## 上传内容相对 v1.3.5 的变化

1. `PCRCore.h`：有上限的请求恢复超时后清除 PCRRecoveryRequested，使后续独立状态通知可以重新触发恢复；超时路径自身不安排周期请求。
2. `Powercuff.x`：启动第 3/10/30/60 秒调用 PCRPublish(YES)，强制重发当前值以补偿先前丢失的通知；读取的是执行时的当前配置。
3. `postinst` / `postrm`：保留 launchctl/TERM 原始诊断和退出码，明确“请求已接受”或“TERM 已发送”不证明 daemon 重载完成。安装/卸载后仍需手动注销。
4. `tests/test_core.m`：新增超时后独立通知重新恢复、强制重发补偿丢失投递的生产核心执行用例。
5. `tests/test_scripts.py`：覆盖命令缺失、两个命令均失败、成功请求不等于重载成功，以及非目标维护阶段不执行操作。

## 构建与发布门禁

发行流程已从 macOS 14 迁移至 macOS 15：GitHub 的 macOS 14 镜像在 2026-10-29 14:00 UTC 至 2026-10-30 00:00 UTC 处于停用演练，并将于 2026-11-02 退役。当前镜像的软件清单提供 Xcode 16.4。目标仍为 iOS 16.0 起、固定 iPhoneOS16.5 SDK；实际环境与工具版本随构建产物记录。公告：https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/ 。

macOS 15 / Xcode 16.4 上执行全部 Python 测试、C 协议测试及真实 Foundation/runtime/生产核心测试，然后使用固定提交的 RootHide Theos 和 iOS 16.5 SDK 编译 arm64e、签名、规范化并打包。

`build.sh` 验证实际 DEB、Mach-O/签名完整性、RootHide 路径、依赖、注入白名单以及与本提交维护脚本和资源的一致性，并执行实际包反例测试。额外强制 CPU subtype 为 0x80000002（版本化 arm64e userland PAC00）；实际 DEB 反例必须以准确的 ABI 原因拒绝未版本化的 0x2，不能仅验证架构低位。失败时不发布。

产物附 SOURCE_COMMIT、SOURCE_FILES.sha256、SOURCE_TESTS.txt、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、verification.txt、VERSION、构建说明和 SHA256SUMS。上传源码不附带本轮构建的新 DEB；根目录内较旧 DEB 是继承的历史文件，不用于发布。

发布任务仅在 `release/powercuff-1.3.6` 的 push 且构建成功后执行，从同一次运行下载产物，核对版本/源码提交和全部附件哈希，再创建新 Pre-release；不覆盖现有 Release。构建结果以该次 Actions 日志和附件为准，本文不预先宣称 CI 成功。

## 真机边界

目标为 iPhone 14 Pro Max（iPhone15,3）/ iOS 16.5（20F66）/ RootHide Dopamine 3.0.4。未连接目标设备，未验证安装/升级/卸载、实际 PAC 加载、私有 API 线程契约、温控恢复、watchdog 长期稳定性或续航收益。

安装后注销一次，先验证 Off → Light → Off 和低电量模式进入/退出，再记录 daemon 崩溃、重启恢复和温控表现。`verify-on-device.sh` 是当前基础只读诊断入口；1.3.4 专用工具仅适用于历史包。
