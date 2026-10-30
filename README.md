# Powercuff 1.3.8 — RootHide 发行候选版

用于 iOS 16 的系统热模拟档位插件，基于 [Baldaran/Powercuff-r3vamp](https://github.com/Baldaran/Powercuff-r3vamp) 改造。重点验证目标为 iPhone 14 Pro Max / iOS 16.5 / RootHide Dopamine 3.0.4。**尚未经该设备真机验证，不承诺无崩溃、固定 CPU 频率或确定的续航提升。**

## 行为与边界

- 只注入 SpringBoard 和 thermalmonitord；不注入 App、Widget 或 Settings。
- 设置使用独立的 `com.minis.powercuff-baldaran-trusted` 偏好域，通过 SpringBoard 的 NSUserDefaults 读取指定持久域的一份快照，不使用跨域搜索。安装脚本不以 root 身份写入默认值。
- 默认关闭；档位为 Off / Nominal / Light / Moderate / Heavy。Nominal（标称）仍属于模拟；退出模拟应选 Off。LPM 开关打开时，仅在系统低电量模式开启期间请求选中档位。
- 捕获 initializer 返回对象后先检查该对象的实际方法 ABI，再启动会话通信；不兼容立即报告99并停止请求，发布端缺席也不会误报成通信超时。替换对象取消旧请求；实际调用前仍复核 ABI。
- 调用系统私有的 `putDeviceInThermalSimulationMode:`。每次 product 初始化创建新的会话标识，仅接受当前会话的档位回复；先检查类、方法及参数 ABI；Objective-C 异常后停止对当前对象重试。此防护不能拦截 SIGBUS、SIGSEGV 或 watchdog。
- 通知读取重试耗尽后，最多追加一轮当前会话请求；持续失败报告状态11并停止主动请求。有效回复/新对象可恢复；明确的设置变更事件可启动新一轮有限恢复，超时和自身回复不能自行解除限制。不会通过猜测档位反复调用私有方法。
- 发布状态写入或通知发送失败时立即使去重缓存失效；快速切回原档位（包括 Off）仍纠正共享状态，旧的延迟任务不能覆盖新设置。
- 设置或 LPM 变更在立即、150、600 毫秒各读取当前值并有限重发，弥补首次通知丢失；新变更取消旧重发，同档私有调用仍去重。不增加持续轮询。若整个窗口消息都丢失或发布端未收到变更事件，仍不能保证自动恢复。
- SpringBoard 启动时立即发布，并在 3/10/30/60 秒各重发一次当前设置，恢复丢失的启动通知；60 秒后停止这些定时任务，同档位仍不重复调用私有方法。
- 系统可能因热策略降低性能与帧率；插件没有独立的后台冻结、固定频率或帧率控制功能。
- 不能与其他 PowerCuff 变种同时安装；Hello CPU 等其他热控插件不一定被包冲突规则识别，首次验证应停用其他热控插件。

## 参数设置

| PowerMode | 设置标题 | 私有接口参数 | 含义 |
|---|---|---|---|
| 0（默认） | 关闭 | `off` | 请求退出模拟，系统真实过热保护仍保留 |
| 1 | 标称（仍在模拟） | `nominal` | 标称模拟，不能等同关闭 |
| 2 | 轻度 | `light` | 首次功能验收从此档位开始 |
| 3 | 中度 | `moderate` | 性能和续航影响须实测 |
| 4 | 重度 | `heavy` | 未作为本机推荐常驻档位 |

RequireLowPowerMode 默认关闭。开启时：系统 LPM 关闭→请求 Off，系统 LPM 开启→请求保存档位，不改写 PowerMode。PowerMode 只接受 0..4 的整数 NSNumber，拒绝布尔、字符串、越界、非整数、NaN/无穷；门控只接受数值 0/1 或布尔，异常输入回退 Off。缺少档位时有限重读后使用 Off。此插件不含独立控制中心模块。

## 安装与升级

此前本地 1.3.6 撤回记录保留在 LOCAL-BUILD-1.3.6.md。本次修复使用新版本号 1.3.8；只安装本次 Release 的 DEB，并核对该 Release 的 SHA256SUMS。仓库根目录的 1.1.x/1.2.x DEB 仅作历史资料，不作为本版交付。

使用匹配源码提交的 CI DEB。安装或升级后**注销一次（respring）**，让 SpringBoard 与 thermalmonitord 同时加载新协议。1.3.1 / 1.3.2 / 1.3.3 / 1.3.4 / 1.3.5 / 1.3.6 / 1.3.7 / 1.3.8 使用同一协议格式，但仍需注销以替换两端实际运行代码；更早版本协议不兼容。旧会话缓存不会被当作新会话回复。

安装/卸载脚本在 configure/remove 阶段先只读探测 user/foreground，再按需探测 system 服务域，只对选定的服务尝试一次 kickstart；该命令失败才最多通过 launchctl 向同一服务域发送一次 TERM，不按进程名 killall。找不到服务域或缺少 launchctl 时跳过自动重启，提示通过越狱应用人工重启用户空间；不盲目发送信号。保留实际重启命令诊断、退出码与人工注销提示；探测/命令退出0均不代表已确认重载。不使用双重重启或 SIGKILL。卸载后重启 daemon 清除 hook，随后注销以卸载 SpringBoard 代码。卸载保留用户偏好，重新安装会复用它们。

首次测试从 Off → Light → Off 开始，检查低电量模式开关的进入/退出。确认 daemon 无新增崩溃，再评估 Moderate；没有经过实测的“最佳档位”。

## 构建与验证

```sh
sh scripts/check.sh
export THEOS=/absolute/path/to/roothide-theos
sh build.sh roothide # 内置规范化、源码对照及实际包反例验证
python3 scripts/verify_package.py packages/YOUR_PACKAGE.deb --version 1.3.8 --source-root .
```

构建需要 Python 3；Git 源码提交时间用于归档时间，下载源码 ZIP 时请显式设置 `SOURCE_DATE_EPOCH`。构建检查失败会以非零状态退出，勿安装失败构建留下的原始包。

[GitHub Actions](https://github.com/allantopwisdom-cell/Repo/actions) 使用 macOS 15 / Xcode 16.4 / iPhoneOS 16.5 SDK。RootHide Theos 与 SDK 使用固定提交；主项目第三方 Actions 也固定到已核对的提交；设置 Xcode 后才执行 host 回归。打包后统一数值 UID/GID 为 0/0，归档时间来自源码提交；签名 payload 字节不变。PR、主分支及 `audit/**`、`fix/**`、`review/**`、`release/**` 分支执行回归测试、编译与包验证。每份产物附源码提交、全部跟踪文件 SHA-256、工具链引用、实际构建环境与完整源码测试输出。仅 release/powercuff-1.3.8 的 push 在全部构建门禁通过后，使用同一运行产物创建草稿并上传全部附件；逐一核对集合、大小、哈希、版本和源码提交后才公开，再核对公开状态。既有标签/Release 不覆盖，标签不另行重编译。

包验证检查：Debian 成员顺序与压缩格式、精确版本、versioned arm64e PAC00（subtype 0x80000002）Mach-O、CodeDirectory 版本布局及代码页/特殊槽覆盖和哈希、数值属主 0/0、iOS 部署目标、文件与必要父目录白名单、RootHide install ID、限定注入范围、偏好键一致性、控制脚本执行位、精确依赖集合；使用 `--source-root` 对照维护脚本、控制元数据、静态 plist 和图标。代码页及特殊槽完整性通过不证明证书信任、PAC 运行行为或设备加载成功。

## 设备诊断

以 mobile（uid 501）身份在 NewTerm 运行 `sh verify-on-device.sh`；root/其他身份或身份读取失败会在采集前退出，避免混淆 Settings 用户域。工具会补充安装版本和请求状态；只做只读快照，不做发行放行判断。`notifyutil` 值可残留，仅用于排查：

| 值 | 含义 |
|---|---|
| loaded.s / loaded.t = 1 | 相应进程曾执行初始化，不证明当前进程存活 |
| hook = 1 | 曾捕获 product 初始化对象 |
| applied = 0..4 | 相应档位的私有方法已返回，不证明实际节流 |
| applied = 10 | 等待对象或当前会话的有效档位 |
| applied = 11 | 通信超时/读取耗尽，旧档位可能仍在生效；不代表已恢复 Off |
| applied = 98 / 99 | Objective-C 异常 / ABI 不符，当前对象停止尝试 |
| thermals | 带版本头的 64 位状态，不再是裸档位数字 |

详细发现、修复依据与待验证项见 [AUDIT-1.3.8.md](AUDIT-1.3.8.md)。旧 AUDIT-1.3.7.md / AUDIT-1.3.6.md / AUDIT-1.3.5.md / AUDIT-1.3.4.md / AUDIT-1.3.3.md / AUDIT-1.3.2.md / AUDIT-1.3.0.md / ANALYSIS.md / BUILD-REVIEW.md 仅记录历史版本，不作为当前构建或真机验证证明。

## 发行验收

本轮以发行标准检查源码、流程和包，GitHub Release 仍标记 Pre-release（发行候选版）。自动化验证不替代真机验收：安装/升级/卸载、Off → Light → Off、LPM 门控、SpringBoard/daemon 分别重启后恢复、待机与温控恢复、崩溃及 watchdog 检查均须记录。未连接目标设备，当前不具备正式稳定版的真机放行证据；不得据此认定省电幅度或与 Hello CPU 联用安全。完整公测表见当前审计报告。

1.3.4 专用验收工具和哈希清单仅供该历史包使用；不要用它们校验 1.3.8。当前版本的只读诊断入口为 `verify-on-device.sh`，完整验收步骤见 AUDIT-1.3.8.md。
