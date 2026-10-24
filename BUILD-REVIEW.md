# PowerCuff Baldaran Trusted RootHide v1.1.0

基于 Baldaran/Powercuff-r3vamp（HEAD eb770af）源码的独立重建，针对
iPhone 14 Pro Max / iOS 16.5 / RootHide Dopamine 适配。

- 产物：`com.minis.powercuff-baldaran-trusted_1.1.0_iphoneos-arm64e.deb`
- SHA-256：`5bee888750377ecca2c8c0035178bc5bab593e5782c69b65728771b10236025a`
- 构建：GitHub Actions macos-14 / Xcode 15.4 / roothide-theos / iPhoneOS16.5
- 验证：`CPU_SUBTYPE_ARM64E (0x2)`、`PAC00`、11 条 PAC 指令、
  install_name `@loader_path/.jbroot/...`、脚本 0755、单一 `Installed-Size`。

## v1.1.0 修复（相对 v1.0.0-1）

| 级别 | 问题 | 修复 |
|---|---|---|
| 高 | 直接读 plist 文件，绕过 cfprefsd，可能读到旧值 | 改用 `NSUserDefaults initWithSuiteName:` |
| 高 | `jbroot()` 用于用户偏好路径，语义错误 | 移除该路径逻辑，统一走 CFPreferences |
| 高 | `static id` 强引用系统 product 对象 | 改 `__weak`，使用时取局部强引用 |
| 高 | `DEBUG=1` 产物带 `+debug`、`-O0` | `DEBUG=0 FINALPACKAGE=1` |
| 中 | LPM 切换依赖未验证私有 selector | 增加 `NSProcessInfoPowerStateDidChangeNotification` |
| 中 | 安装后进程未重载，插件看似无效 | postinst 重载 thermalmonitord + respring |
| 中 | 无 Conflicts，可与其它 PowerCuff 双 hook | 增加 Conflicts |
| 中 | PSLinkListCell 缺 `default` | 补 `default = 0` |
| 低 | 回调未串行化 | 统一串行 dispatch queue |
| 低 | 无日志 | 增加 os_log |
| 低 | 卸载后 daemon 仍带 hook | postrm 在 remove/purge 时重启 |
| 低 | Off 先传 nil，行为未定义 | 只传 `"off"` |

## 未在真机验证

- Moderate / LowPowerMode 档位的实际热节流效果
- 与其它热控类插件共存的表现（已用 Conflicts 规避）
- 卸载后 thermalmonitord 状态是否完全恢复
