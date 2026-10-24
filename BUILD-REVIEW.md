# PowerCuff Baldaran Trusted RootHide — 构建证据

- **源码**：基于 [Baldaran/Powercuff-r3vamp](https://github.com/Baldaran/Powercuff-r3vamp) HEAD `eb770af`（v16，纯热模拟版）
- **构建**：GitHub Actions `macos-14` + Xcode 15.4 + roothide/theos + iPhoneOS16.5 SDK
- **产物**：`com.minis.powercuff-baldaran-trusted_1.0.0-1-1+debug_iphoneos-arm64e.deb`
- **SHA-256**：`2c0c02d61af2e391abb75458eb76515aad3a765812de44e4c972cb00785982e1`
- **架构**：`arm64e` / `CPU_SUBTYPE_ARM64E (0x2)` / `caps: PAC00`
- **install_name**：`@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/Powercuff.dylib`
- **通知名**：偏好页 PostNotification 与 dylib 监听均为 `.settingschanged`
- **默认**：`PowerMode = 0`（Off）、`RequireLowPowerMode = false`

## 修复内容
1. 统一设置通知名为 `com.minis.powercuff-baldaran-trusted.settingschanged`（原 1.5.1 偏好页发布 `.update` 而 dylib 监听 `.settingschanged` 不一致）
2. 默认 Off，单一独立偏好域 `com.minis.powercuff-baldaran-trusted`
3. 去除夸大功能描述，文案仅称热模拟
4. 使用 `objc_getClass()` 避免静态类符号链接错误
5. 安装脚本无副作用，卸载前写 Off 并通知

## 未真机验证
- Moderate / LowPowerMode 档位生效
- 卸载后 thermalmonitord 状态恢复
- 与其他 PowerCuff 同时启用的冲突行为
