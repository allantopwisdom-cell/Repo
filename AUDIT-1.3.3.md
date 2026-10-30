# Powercuff v1.3.2 公测标准复审与 v1.3.3 修订

## 基线与结论

基线源码：v1.3.2 / `4b0bd73fa3e0e11ea9002a0320d65691a1001f02`。公开 DEB 为 17,020 字节，SHA-256 `74e5bccf2033c0f16bb0570c70ed8f89b0cded44b72dadafa001c7b59a79c1db`。重新核对 GitHub Release API、实际包与源文件。目标设备 iPhone15,3 / iOS 16.5 (20F66) / RootHide Dopamine 3.0.4。

本轮按公测要求评估，而不把构建成功当作正式稳定版或真机兼容证明。v1.3.2 在 GitHub 实际为 `prerelease=false`；v1.3.3 应明确标记 Pre-release。没有连接真机，不具备稳定版放行条件。

## 问题、证据与处置

| 编号 | 等级 | 证据与影响 | 修正 |
|---|---|---|---|
| B01 | 中 | 原 `objectForKey:` 搜索多个默认域，suite 不等于隔离；注册域或其他搜索域同名 PowerMode/RequireLowPowerMode 可被纳入插件设置。Apple 文档明确该搜索行为，合成 Foundation 用例可验证注册域污染。未声称用户设备已发生污染 | 使用 `persistentDomainForName:` 的单份字典快照，只读取插件持久域；两个键来自同一快照，避免两次独立读取跨越一次更新。缺失档位仍按原有限重试后 Off |
| B02 | 中 | 原 ABI 判断只比较首字符；`@?` block 编码也以 `@` 开头，原检查允许 block 参数或 block 返回值。向期待 block 的方法传 NSString 可能触发不兼容调用；没有证据表明 iOS16.5 实际私有方法采用该编码 | 将实际生产 ABI 检查移至共享 runtime 头文件，完整区分普通对象/void/block，验证参数数目与 self/SEL；未知编码保守禁用。测试使用 runtime 注册的方法元数据，不调用故意不匹配的 IMP |
| B03 | 中 | 原 tar 校验允许目录 0000/0644/0700，签名和 payload 清单正确仍可能无法由 mobile 遍历；允许 `Library//x`、`Library/./x` 等规范路径别名；ar 负尺寸/缺失奇数填充未明确拒绝 | 目录必须 0755；拒绝非规范路径；拒绝负尺寸/不合法填充；顶层 ar 恰好三个 Debian 成员，不容纳未检查的额外成员 |
| B04 | 低 | README 把旧进程统一描述为与1.3.2协议不兼容；实际1.3.1/1.3.2协议相同。升级仍需替换内存代码 | 明确协议格式兼容与进程代码替换的区别；保留安装后注销要求 |
| B05 | 发布 | 未完成真机测试但 v1.3.2 标记 Latest，用户要求本轮按公测标准交付 | 新版 GitHub Pre-release，报告列出阻塞稳定版的设备验收项，不回溯修改旧发布或宣称已真机通过 |

Apple 依据：
- https://developer.apple.com/documentation/foundation/userdefaults
- https://developer.apple.com/documentation/foundation/userdefaults/persistentdomain(forname:)?language=objc
- https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html

## 完整审查覆盖

| 范围 | 已检查内容与结论 | 限制 |
|---|---|---|
| 注入范围 | filter仅 SpringBoard/thermalmonitord；ctor再次检查进程与iOS主版本；无App/Widget注入 | loader/PAC真实行为待设备 |
| 私有ABI与hook | 类和selector存在性、返回/参数编码、真实方法归属、继承/同IMP别名；未知ABI保守跳过 | 不能证明私有API线程契约或各设备类布局 |
| 生命周期/对象 | 弱引用product、主队列强局部引用、对象更换失效旧generation、同对象去重；异常对当前对象熔断 | 无法捕获SIGBUS/SIGSEGV/watchdog |
| 协议 | session非零、前缀/保留位/模式范围、旧session拒绝；session提供新鲜度而非认证 | notify不是安全隔离边界 |
| 恢复与功耗 | 发布/请求/读取重试均有上限；设置事件两次补读；无无限轮询；同档位避免重复私有调用 | 超过窗口的故障可能保留旧档位；需新事件/重启恢复，不保证最终一致性 |
| 设置与LPM | 单持久域快照、NSNumber/CFBoolean区别、整数范围0..4、NaN/Infinity拒绝、门控返回Off | cfprefsd可见性/进程权限须实测 |
| 安装升级卸载 | configure与remove分别一次kickstart，失败最多一次TERM；不写root偏好；purge不再重启 | 不执行设备维护命令；没有真机卸载/回滚记录 |
| DEB与签名 | 数值属主0/0、目录遍历权限、脚本执行位、路径/文件allowlist、iOS16 arm64e、RootHide install ID、依赖前缀、代码页和特殊槽哈希 | ad-hoc结构/哈希不等于Apple信任/PAC设备加载 |
| 构建发布 | 固定RootHide Theos和SDK；macOS编译、源码/实际包反例、artifact、源码commit、SHA256；Release用同一artifact | Homebrew/Actions主要标签仍非全链可重复构建；不宣称供应链已完全锁定 |

## 自动化验收

1. Linux：12项Python用例、C协议测试、shell语法、plist解析、diff空白检查。
2. macOS CI：运行同一套检查，并执行真实Foundation偏好解析/域隔离/快照测试与Objective-C runtime继承及完整ABI反例。
3. 实际构建：RootHide arm64e编译、链接、签名、数值属主规范化、完整包验证。
4. 实际Mach-O：拒绝代码篡改、签名头破坏、截断、requirements篡改和零页覆盖。
5. 发布后：重新公开下载DEB，对比构建SHA256并再次运行包及反例验证。最终通过状态以该版本Release附件和对应Actions记录为准。

新增反例针对可观察的错误，不把Linux无法运行的Foundation测试算作通过。旧1.3.2包在新版校验器仍通过，说明本轮不是宣称旧包权限已经损坏。

## 真机公测与稳定版放行表（当前全部待执行）

测试前单独启用Powercuff，停用Hello CPU及其他热控插件以隔离变量；保留可用的越狱禁用插件/安全模式恢复入口。默认Off，不自动改Moderate或CPU固频。

| 场景 | 合格依据 | 当前 |
|---|---|---|
| 全新安装、1.3.2升级、卸载/重装 | 包管理成功，旧设置按预期保留，无维护脚本重复重启；注销后两端运行新代码 | 待真机 |
| Off → Light → Off | 当前会话档位正确，私有API返回，退出后实际温控行为恢复；结合新日志，不只看残留notify值 | 待真机 |
| LPM门控与快速改档 | LPM关闭回Off，开启恢复选中档位；快速改档最终收敛到当前配置 | 待真机 |
| SpringBoard/daemon分别重启 | 新session拒绝旧缓存，重新握手，有限恢复后正确应用 | 待真机 |
| 长待机、唤醒、充电、温度变化 | 没有新增daemon崩溃、watchdog、异常发热或无法恢复；记录工作负载与环境温度 | 待真机 |
| 性能/续航对照 | 同亮度/网络/负载/温度，比较Off与Light/Moderate多次结果，记录掉电、帧率和温控，不承诺固定收益 | 待真机 |
| 与Hello CPU联用 | 先独立通过，再单变量加回其他插件，确认策略竞争与恢复行为 | 待真机 |

任一新增thermalmonitord崩溃、watchdog、热失控或Off恢复失败均阻塞稳定版。没有设备反馈时继续机械修改档位、线程或hook点不能替代验证，本轮不作此类推测改动。
