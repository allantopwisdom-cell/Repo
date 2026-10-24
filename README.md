# PowerCuff Baldaran Trusted RootHide

基于 [Baldaran/Powercuff-r3vamp](https://github.com/Baldaran/Powercuff-r3vamp) 公开源码（v16 / HEAD `eb770af`）的独立适配工程。

## 修复与适配

1. **通知名统一**：偏好页、dylib、prerm 三处均使用 `com.minis.powercuff-baldaran-trusted.settingschanged`，无冲突。
2. **RootHide 路径**：通过 `jbroot()` API 自动切换 `/var/mobile/…` 与 `/var/jb/var/mobile/…`，支持所有 RootHide 设备。
3. **安装脚本**：`postinst` 写入默认 `PowerMode=0`（Off）并初始化 LPM 开关；`prerm` 卸载前显式写 Off 并发通知。
4. **注入范围**：仅 `SpringBoard` + `thermalmonitord`（`Executables` 过滤）。
5. **架构**：单一 `arm64e`（真 PAC）。
6. **描述诚实**：只称"热模拟 profile"，无冻结后台/帧率上限等未实现功能。

## 构建

- 本地：`sh build.sh`（需要 roothide/theos + iPhoneOS16.5 SDK）
- CI：推送 main 分支自动触发 [macos-14 + roothide/theos](https://github.com/allantopwisdom-cell/powercuff-baldaran-trusted/actions)

## 验证门禁

- dpkg-deb 控制脚本执行位检查 ✅
- arm64e CpuSubType = 0x2 / PAC00 ✅
- install_name = `@loader_path/.jbroot/…` ✅
- 单一偏好域，无旧域引用 ✅
