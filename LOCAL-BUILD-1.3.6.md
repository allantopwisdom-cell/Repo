# Powercuff 1.3.6 本地源码重编译记录

本文记录公开发布之前单独交付的 Linux 本地构建，所述状态仅对应该次交付。当前公开发行流程见 BUILD-1.3.6.md 和 Release 对应的 Actions 日志。

该次 DEB 使用用户上传的修订源码，在 Linux 上交叉编译、链接、签名和打包；当时尚未向 GitHub 上传，也未运行 Actions 或发布 Release。本地源码提交为 3904479eecc8643663ea65faeeb8079fd6fe0889，本地 DEB SHA-256 为 9961df82f5d8f6df73dc8534f9d7f0e182879fb931993e6abee0a5dd7675d720。公开 Release 使用后续 macOS 构建及其自身源码提交/哈希，不能混用这份本地记录的摘要。

## 构建输入

- 输入源码归档：powercuff-repair-source-unverified.tar.gz。
- 输入 SHA-256：e7e9ef279e1bf4997799088e26fb1a68fb5f62dea1ccfefd74530748202f5151。
- 上传源码相对 v1.3.5 的运行修订保持不变；仅统一为 1.3.6，完善说明和构建验证。
- RootHide Theos：cfba89a53a05b4a1b822121158acc3669c20602f，包含对应递归子模块。
- iPhoneOS 16.5 SDK：theos/sdks 提交 0222fd5413cf4b9af096f37b4621afa2688572f7。
- iOS 交叉工具链：L1ghtmann/llvm-project 的 main-update_3-eabca92，x86_64 完整归档。
- 工具链归档 SHA-256：cc9fbc7f8a3f9336f926cd4fb7cc2233a17b2ba40504cc8c0ff3211bd9df27e3。
- 该工具链发布说明列出 LLVM/Clang 19、ld64 956.6、libtapi 1600.0.11.8 以及同包 ldid。实际版本和命令记录在交付的构建日志中。

## 本轮构建检查修订

首次尝试的旧 Apple Clang 13 工具链输出未版本化的 arm64e（CPU subtype 0x2），并触发链接器 ABI 警告。虽然旧包检查只验证 arm64e 低位并通过，该产物仍被拒绝交付。

现补充明确要求 CPU subtype 0x80000002（userland PAC00）的门禁，并对实际 DEB 新增 legacy-arm64e-abi 反例，要求以准确的 ABI 原因拒绝该包。本轮使用完整 LLVM 19 工具链重新编译；不修改二进制头来伪装架构或修正 ABI。

## 验证与范围

源码 Python 回归、C 协议、shell/plist 检查在本地执行；macOS Foundation/runtime/生产核心执行测试在本环境无法运行，不能把先前版本的 macOS 结果当作本轮结果。

最终交付必须通过源码自带 build.sh 的归档规范化、实际 DEB/Mach-O/签名完整性检查、源码静态资源对照、实际包变异反例，以及新增的 PAC00 门禁。最终结果、包 SHA-256、源码提交、全部跟踪文件摘要和工具链信息以随包交付记录为准。

目标为 iPhone 14 Pro Max / iOS 16.5 / RootHide Dopamine 3.0.4。未连接目标真机，未验证实际安装/加载、私有 API、watchdog、温控恢复或耗电。本包为公测构建；安装或升级后需注销一次，先测试 Off → Light → Off 和低电量模式门控。
