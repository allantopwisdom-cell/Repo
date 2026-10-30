# Powercuff 1.3.7 构建与发布证据说明

基线：已发布 v1.3.6 的提交 9ef8ebb01551910353c911d1bba10383aa46176e。基线 DEB SHA-256：ed5ec0c3d7b51c7c7c5b297ca7f0cd6d9f02944e104fb1d275e31b6c87e7636f。本轮使用独立 release/powercuff-1.3.7 分支，不改写旧 Release。

## 失败先于修复

[基线回归运行 41033074996](https://github.com/allantopwisdom-cell/Repo/actions/runs/41033074996) 在 v1.3.6 生产核心不变的条件下新增通知丢失场景。38 项 Python 与原核心场景通过后，test_core.m:308 的 Off 恢复断言失败，退出 134；未构建/发布包。修复修改 PCRRefreshPreferences 的实际生产流程，不删除该断言或放宽 Drain 上限。

## 成功构建的判据

- macOS 15、Xcode 16.4，先执行 host 回归，再安装 Theos/SDK 并编译。
- RootHide Theos：cfba89a53a05b4a1b822121158acc3669c20602f。
- iPhoneOS16.5 SDK：0222fd5413cf4b9af096f37b4621afa2688572f7。
- check.sh：shell 语法、Python 测试、C 协议、plist；macOS 执行真实 Foundation 参数、runtime ABI、实际 PCRCore.h 的模拟传输/虚拟时钟回归。
- build.sh：完整编译/链接/签名/打包，规范化归档属主/时间，对实际包执行结构、签名、ABI、源码对照及反例检查。
- control 版本必须为 1.3.7，实际包只允许一个。签名 payload 不经过二进制拼接或旧包复用。
- 仅成功运行产物进入发布 job；先建新标签绑定 GITHUB_SHA，再创建草稿上传全部附件；逐项核对集合、大小、SHA256、版本、源码提交、草稿/公测标记后公开，再复核公开状态。任何失败返回非零，不覆盖已有标签或发布。

## 附件对应关系

DEB、verification.txt、SOURCE_TESTS.txt、BUILD_ENVIRONMENT.txt、SOURCE_COMMIT、SOURCE_FILES.sha256、TOOLCHAIN_REFS、VERSION、AUDIT/BUILD/RELEASE-1.3.7.md、verify_release.py，共 13 项附件。SHA256SUMS 包含除自身外的全部 12 项，随后 SHA256SUMS 自身也由 GitHub 资产 digest 与发布校验器核对。GitHub 自动提供源码 zip/tar.gz，不计入这 13 项。

SOURCE_COMMIT 给出实际成功提交；SOURCE_FILES.sha256 是该提交全部跟踪文件清单，包括历史资料。最终工作树、Release 标签、运行 head_sha、公开下载字节应一致。代码页哈希和云端测试不证明目标设备实际加载或省电收益。完整风险边界见 AUDIT-1.3.7.md。
