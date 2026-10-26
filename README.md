# Powercuff 1.3.0 — RootHide

用于 iOS 16 的系统热模拟档位插件，基于 [Baldaran/Powercuff-r3vamp](https://github.com/Baldaran/Powercuff-r3vamp) 改造。重点验证目标为 iPhone 14 Pro Max / iOS 16.5 / RootHide Dopamine 3.0.4。**尚未经该设备真机验证，不承诺无崩溃、固定 CPU 频率或确定的续航提升。**

## 行为与边界

- 只注入 SpringBoard 和 thermalmonitord；不注入 App、Widget 或 Settings。
- 设置使用独立的 `com.minis.powercuff-baldaran-trusted` 偏好域，通过 SpringBoard 的 NSUserDefaults 读取。安装脚本不以 root 身份写入默认值。
- 默认关闭；档位为 Off / Nominal / Light / Moderate / Heavy。LPM 开关打开时，仅在系统低电量模式开启期间请求选中档位。
- 调用系统私有的 `putDeviceInThermalSimulationMode:`。先检查类、方法及参数 ABI；Objective-C 异常后停止对当前对象重试。此防护不能拦截 SIGBUS、SIGSEGV 或 watchdog。
- 系统可能因热策略降低性能与帧率；插件没有独立的后台冻结、固定频率或帧率控制功能。
- 不能与其他 PowerCuff 变种同时安装；Hello CPU 等其他热控插件不一定被包冲突规则识别，首次验证应停用其他热控插件。

## 安装与升级

使用匹配源码提交的 CI DEB。安装或升级后**注销一次（respring）**，让 SpringBoard 与 thermalmonitord 同时加载新协议。旧进程与 1.3.0 的通知协议不兼容；升级前的旧状态不会被当作有效的新档位。

安装脚本仅在 `configure` 阶段尝试一次 launchctl kickstart；失败才回退一次 TERM，不使用双重重启或 SIGKILL。卸载后重启 daemon 清除 hook，随后注销以卸载 SpringBoard 代码。卸载保留用户偏好，重新安装会复用它们。

首次测试从 Off → Light → Off 开始，检查低电量模式开关的进入/退出。确认 daemon 无新增崩溃，再评估 Moderate；没有经过实测的“最佳档位”。

## 构建与验证

```sh
sh scripts/check.sh
export THEOS=/absolute/path/to/roothide-theos
sh build.sh roothide
python3 scripts/verify_package.py packages/YOUR_PACKAGE.deb --version 1.3.0
```

[GitHub Actions](https://github.com/allantopwisdom-cell/Repo/actions) 使用 macOS 14 / Xcode 15.4 / iPhoneOS 16.5 SDK。RootHide Theos 与 SDK 使用固定提交；主项目第三方 Actions 仍使用主要版本标签。PR、主分支及 `audit/**` 分支执行回归测试、编译与包验证。每份产物附源码提交、工具链引用与 SHA-256。仅匹配 control 版本的 `v*` 标签会创建**草稿** Release，普通推送不改写旧 Release。

包验证检查：精确版本、arm64e Mach-O、签名数据存在、RootHide install ID、限定注入范围、偏好键一致性、控制脚本执行位。签名数据存在不等于签名密码学校验通过，也不等于设备加载成功。

## 设备诊断

以 mobile 身份在 NewTerm 运行 `sh verify-on-device.sh`；root 读取到的偏好不代表 Settings 用户域。`notifyutil` 值可残留，仅用于排查：

| 值 | 含义 |
|---|---|
| loaded.s / loaded.t = 1 | 相应进程曾执行初始化，不证明当前进程存活 |
| hook = 1 | 曾捕获 product 初始化对象 |
| applied = 0..4 | 相应档位的私有方法已返回，不证明实际节流 |
| applied = 10 | 等待对象或有效档位 |
| applied = 98 / 99 | Objective-C 异常 / ABI 不符，当前对象停止尝试 |
| thermals | 带版本头的 64 位状态，不再是裸档位数字 |

详细发现、修复依据与待验证项见 [AUDIT-1.3.0.md](AUDIT-1.3.0.md)。旧 ANALYSIS.md / BUILD-REVIEW.md 仅记录历史版本，不作为当前构建或真机验证证明。
