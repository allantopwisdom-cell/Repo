# Powercuff 1.3.6 构建与发布说明

本轮以用户上传的 powercuff-repair-source-unverified.tar.gz（SHA-256 e7e9ef279e1bf4997799088e26fb1a68fb5f62dea1ccfefd74530748202f5151）和现有 release/powercuff-1.3.6 修复分支 deebf1aa2c753370f358c2318fbbf11ac1ff88e3 为输入，完成完整源码复审、修复和发布门禁核对。详细覆盖范围、失败证据、修订及真机待测项见 AUDIT-1.3.6.md。

## 恢复行为

- 超时保持恢复锁存，自身请求的回复与延迟读取不能自动解除它；有效当前会话回复或新 product 可恢复。
- thermalmonitord 独立观察 settingschanged。明确的偏好编辑事件可启动一轮有限请求，并取消旧读取/请求任务。daemon 不读取 mobile 偏好；解析仍由 SpringBoard 完成。
- 设置事件不能绕过当前对象的 ObjC 异常或 ABI 熔断；没有 product 时不发请求。
- SpringBoard 在启动时立即发布，并在3/10/30/60秒各强制重发当前设置。每次重新读取偏好，60秒后停止；相同档位不重复调用私有 API。

## 可复核的失败证据

[40971591488](https://github.com/allantopwisdom-cell/Repo/actions/runs/40971591488)：原上传源码超时解锁导致持续读取失败的生产核心测试超过1000任务上限，退出134，未构建/发布。

[40972410830](https://github.com/allantopwisdom-cell/Repo/actions/runs/40972410830)：源码恢复锁存后，新增用例仍要求超时自动清除锁存，在相应断言退出134；持续失败的原上限测试此前已通过。现将该用例改为验证无效传输不能自我重新触发、明确设置事件可恢复，并保持1000任务上限。

## 工具链和实际包

使用macOS15/Xcode16.4、固定RootHide Theos cfba89a53a05b4a1b822121158acc3669c20602f 和iPhoneOS16.5 SDK 0222fd5413cf4b9af096f37b4621afa2688572f7。最低iOS16.0，仅arm64e/RootHide。保留CPU subtype 0x80000002（versioned userland arm64e/PAC00）门禁及原0x2反例，不修改二进制头伪装ABI。

macOS14正处于停用演练并将于2026年11月2日退役，依据GitHub官方公告：https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/ 。保留迁移后的工具链。

build.sh 必须通过归档规范化、源码静态资产对照、签名/ABI检查和真实DEB变异反例；CI还执行38项Python、C协议、Foundation/runtime及15组生产核心场景。结果以本次成功运行的SOURCE_TESTS.txt和verification.txt为准。

## 发布来源与替换

仅release/powercuff-1.3.6的push且build成功触发发布。同次artifact下载后核对VERSION、SOURCE_COMMIT和所有附件SHA256SUMS；以非覆盖方式创建绑定该SHA的tag，再通过--verify-tag发布Pre-release，已有tag/Release均不覆盖。发布后核对解析后的tag提交。

原先单独交付的本地1.3.6包已撤回（记录保留于LOCAL-BUILD-1.3.6.md）。即使版本号相同，也需重新安装本次云端Release包、核对SHA256SUMS并注销一次。未连接目标设备；自动化成功不代表实际PAC加载、温控恢复、watchdog或续航已验收。
