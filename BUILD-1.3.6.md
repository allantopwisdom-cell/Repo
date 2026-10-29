# Powercuff 1.3.6 云端构建与恢复循环修复

## 来源与复现

基线为用户上传的 powercuff-repair-source-unverified.tar.gz（SHA-256 e7e9ef279e1bf4997799088e26fb1a68fb5f62dea1ccfefd74530748202f5151），以及由该源码构建但未经 macOS 执行测试的本地 1.3.6。

macOS 15 / Xcode 16.4 上的失败运行：https://github.com/allantopwisdom-cell/Repo/actions/runs/40971591488 。38 项 Python、C 协议、plist 和 Foundation/runtime 测试通过后，持续读取失败的生产核心用例触发 Drain 的 1000 任务上限，退出码 134。该次运行未构建和发布 Release；此前本地 1.3.6 包请暂停安装，改用通过该回归的最终云端包。

原因：上传源码在 PCRRequestFresh 超时时清除 PCRRecoveryRequested。请求引发的发布通知仍可能留下延迟读取；持续读取失败时，后续耗尽路径因锁存已清除而再次启动请求。请求、回复通知、读取重试形成反馈循环。此处是模拟真实生产核心逻辑的故障复现，尚不等同于真机耗电/watchdog 复现。

## 精确修复

- 请求超时保持 PCRRecoveryRequested 锁存；只有有效的当前会话回复或新 product 对象才重新允许请求恢复。每个失败阶段的主动请求仍有上限，不由自身延迟通知递归启动下一轮。
- 有效的晚到发布可恢复档位并重新允许下一次恢复；任意无效通知不解除锁存。
- 保留上传源码的第 3/10/30/60 秒强制启动重发和安装/卸载诊断修订。
- 保留持续读取失败的原始限次回归；修订新增用例，明确验证无效通知不再触发请求、有效晚回复可恢复。没有提高或删除 Drain 上限，也没有跳过失败用例。
- 保留已授权的 1.3.6 发行版本；最终云端包与早先本地包必须通过源码提交和 SHA-256 区分。请重新安装 Release 中的新包并注销一次。不是一次全量源码审计。

## 编译与发布

macOS 15 / Xcode 16.4；固定 RootHide Theos cfba89a53a05b4a1b822121158acc3669c20602f 和 iPhoneOS16.5 SDK 0222fd5413cf4b9af096f37b4621afa2688572f7。最低部署 iOS 16.0，包架构 iphoneos-arm64e，注入范围仅 SpringBoard/thermalmonitord。

发布前必须通过全部 Python/C、真实 Foundation/runtime/生产核心执行测试、编译/签名、CPU subtype 0x80000002（userland PAC00）、签名完整性、实际 DEB 与源码资源对照及实际包反例。原始未版本化 0x2 ABI 包必须被准确拒绝。

仅 release/powercuff-1.3.6 的 push 且 build 成功才发布；下载同次运行产物，核对 VERSION、SOURCE_COMMIT、SHA256SUMS 后创建新 Pre-release，不覆盖现有 Release。附件包括构建说明、完整测试输出、包验证、SOURCE_FILES.sha256、源码提交和实际工具链环境。成功与否以对应 Actions/附件为准。

macOS 14 已迁移：GitHub 当前停用演练公告 https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/ 。

## 验证边界

面向 iPhone 14 Pro Max / iOS 16.5 / RootHide Dopamine 3.0.4。未连接目标设备；实际 PAC 加载、私有 API、温控/性能恢复、崩溃/watchdog 和续航仍需真机验收。安装或升级后注销一次，先验证 Off → Light → Off 及低电量模式进入/退出。1.3.4 专用采集工具仅适用于历史包；当前基础只读诊断使用 verify-on-device.sh。
