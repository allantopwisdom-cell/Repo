# 源码深度审查（v1.0.0-1 → v1.1.0）

## 高严重度

### H1 偏好读取绕过 cfprefsd，可能读到旧值
`LoadSettings` 用 `[NSDictionary dictionaryWithContentsOfFile:]` 直接读 plist。
但 PreferenceLoader（PSLinkListCell/PSSwitchCell）通过 `defaults` 写，走 cfprefsd，
它不保证立即落盘。刚改完设置时 tweak 可能仍读到旧值。
RootHide 下该文件实际位置也由 cfprefsd 决定，硬编码 `/var/mobile/...` 不可靠。
→ 改用 `NSUserDefaults initWithSuiteName:`（内部走 CFPreferences/cfprefsd）。

### H2 `jbroot()` 用法语义错误
`PCPreferencesPath` 用 `jbroot()` 转换用户偏好路径。`jbroot()` 是把 jbroot 路径
转成 rootfs 路径；而用户偏好由 cfprefsd 管理、位于真实 rootfs，不在 jbroot 内。
转换反而可能指向不存在的位置。改用 CFPreferences 后整段路径逻辑删除。

### H3 `static id currentTarget` 强引用系统对象
ARC 下 static 强引用会 retain `CommonProduct`，阻止其正常析构/重建，
若系统重建 product 实例，缓存会指向旧对象导致状态陈旧。
→ 改 `__weak`，并每次使用时取强引用局部变量。

### H4 发布构建带 `+debug`
`make` 默认 `DEBUG=1`，产物 `1.0.0-1-1+debug`、`-O0`。
control 里 `Version: 1.0.0-1` 又被 theos 追加 `-1`，版本号出现两段 `-1`。
→ `DEBUG=0 FINALPACKAGE=1`，control `Version: 1.1.0`。

## 中严重度

### M1 低电量模式切换依赖未验证的私有 selector
只在 SpringBoard hook `_batterySaverModeChanged:`。iOS 16.5 上该方法是否存留未验证；
若不存在，"仅低电量模式"开启后切换 LPM 不会更新状态。
→ 增加 `NSProcessInfoPowerStateDidChangeNotification` 观察作为可靠回退。

### M2 安装后进程未重载，看起来"没效果"
已运行的 thermalmonitord/SpringBoard 不会加载新 dylib。
用户在设置里改档位没人响应，会误判插件失效。
→ postinst 重载 thermalmonitord 并 respring SpringBoard。

### M3 没有 Conflicts
与 com.rpetrich.powercuff、com.baldaran.powercuff-r3vamp 同时存在会双 hook
同一类，互相覆盖热模拟状态。
→ control 增加 Conflicts。

### M4 PSLinkListCell 缺 `default` 键
面板首次打开时档位可能显示未选中，与运行时默认 off 不一致。
→ 补 `default` = 0。

## 低严重度
- L1 通知回调未串行化 → 统一到串行队列。
- L2 无日志 → 增加 os_log，便于真机诊断。
- L3 卸载后 thermalmonitord 仍带 hook → postrm 在 remove/purge 时重启它。
- L4 Off 时原实现先传 nil 再传 "off"，传 nil 给系统方法有崩溃风险；
  上游与已发布二进制都只传 "off"。→ 只传 "off"。
