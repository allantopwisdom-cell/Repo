# Powercuff 1.3.1 全量复审与 1.3.2 修复

基线为公开 tag v1.3.1，源码 `8e1f1417c35940a44b77234401fdcc838afdf592`，公开 DEB 16,570 字节，SHA-256 `b032c3ba5aab604caebae3e5c4931a964fa57f4e5dcb1100a74b3f26317770a1`。本轮核对了发布 API、源码全树、构建记录、全部运行源码/协议/配置/脚本及实际包。目标仍为 iPhone15,3 / iOS 16.5 / RootHide Dopamine 3.0.4。

## 总体结论与证据等级

v1.3.1 公开附件与校验值一致，未再次发生 v1.3.0 的发布漂移。发现并修复的项目集中在 hook 选择条件、通知读取恢复、偏好可见性恢复和构建产物检查。静态问题和合成反例不等于已经在目标设备复现的崩溃；下表明确区分。

| 编号 | 等级 | 实际发现/证据 | 1.3.2 处置 |
|---|---|---|---|
| P01 | 高 | 实际 v1.3.1 control/data tar 全部文件数值 UID/GID 为 501/20，虽然 uname/gname 写 root/wheel；旧校验只看文件内容，未看数值属主 | 新增归档规范化：全部成员改为 0/0，固定归档时间为源码提交时间，保留 signed payload 原字节；校验阶段检查数值属主及危险权限 |
| R01 | 中 | gp 去重只比较 IMP，无法区分真正继承、子类显式注册同一实现、无关类共享同一实现；可用 runtime fixture 构造漏 hook 路径，未在真机证明该类布局 | 根据类层级和 method list 的实际归属判断；仅跳过确实经过已 hook 基类的继承方法，增加 macOS Objective-C runtime 测试 |
| R02 | 中 | thermal notify_get_state 失败或读到不匹配会话后直接返回；首次应用后请求链已停止，后续事件读取失败缺乏主动恢复 | 加入最多 6 次、400ms 间隔的读取重试；新事件/新 product 令旧 generation 失效；方法异常及 ABI 故障不重试私有调用 |
| R03 | 中 | 设置通知与跨进程偏好域可见性缺乏同步契约；若首次读取旧值且被去重，原路径没有事件后的补读；属于恢复缺口，未做真机时序复现 | 设置/LPM 事件即时读取，另在 150ms/600ms 补读当前域；新事件使旧补读失效，不捕获历史档位，不启动周期轮询 |
| V01 | 中 | 实际 v1.3.1 签名 verifier 对 requirements 特殊槽内容改一字节仍返回通过，已用原 verifier 重现 | 增加特殊槽哈希验证，并拒绝本项目不需要的额外签名 payload/entitlements |
| V02 | 中 | 原签名检查允许 codeLimit 小于签名起点，甚至可构造零页覆盖逃过代码页循环 | 要求非零且完整覆盖签名之前全部字节，增加零页覆盖反例 |
| V03 | 中 | tar parser 忽略非 regular 成员，symlink/hardlink/设备/FIFO 可不进入检查清单 | 拒绝链接及特殊成员、重复规范路径、越界路径；要求实际文件集合等于 6 个预期文件 |
| V04 | 中 | assert 检查在 Python -O 下可被关闭 | verifier 模块在 -O 下直接拒绝执行，并添加回归测试 |
| V05 | 低 | 包检查不验证平台/最低系统、load command 完整边界、精确 install ID 与依赖路径 | 检查 iOS device / iOS16.0 最低目标、load command 对齐及边界、签名末尾、精确 RootHide install ID、系统/RootHide 依赖路径 |
| T01 | 低 | 原测试只覆盖首批路径，未检验数值属主与 requirements 内容损坏 | 增加 9 项 Python 回归、真实 Objective-C runtime 反例、归档规范化幂等/字节保留测试和实际构建包的特殊槽/覆盖反例 |

## 本地检查与复现

- 原 v1.3.1 签名 requirements 内容篡改后，原校验函数仍返回 2 个 CodeDirectory 通过；新函数拒绝并报告 special slot 2 hash mismatch。
- 原 DEB 数值属主由 tar header 直接读取，控制脚本和 6 个 payload 文件均为 501/20；不能依赖 root/wheel 文本名替代数值检查。
- 将原包复制到临时路径进行规范化后，代码页和 requirements 哈希仍通过，证明规范化未破坏签名 payload。该临时包仅用于验证，不作为 1.3.2 交付。
- Python 回归覆盖：正常文件、链接/特殊文件、越界路径、重复路径、危险权限、伪 root 文本名、-O 拒绝、规范化幂等及 payload 保留；加上维护脚本生命周期回归共 9 项。
- C 协议测试、所有 plist、shell 语法和 diff 空白检查通过。macOS Foundation/runtime 测试必须由对应 CI run 验证，不把 Linux 跳过视为通过。

## 实现审查及未作不必要改动的部分

- 保持 v1.3.1 的会话格式、0..4 档位映射、有限发布/请求重试、私有方法 ABI 检查、对象异常熔断和限定进程注入。
- 主队列访问弱 product；回调读取时取强局部引用；新 product 失效旧读取重试，避免旧对象/会话的补读继续执行。
- 不增加后台定时器、App/Widget 注入、CPU 固频、后台冻结或强制低电量模式；默认仍 Off。
- 安装/卸载仍不以 root 写 mobile 偏好；kickstart 成功不再另发 kill，失败最多回退一次 TERM；脚本失败保留可见提示。
- 1.3.1 的发布隔离保持：仅分支构建，标签不重编译/覆盖附件。

## 云端验收门禁

源码提交后：Python/C/Foundation/runtime 测试 → arm64e 编译链接/签名 → 规范化 tar 数值属主 → 包及签名完整性检查 → 实际包反例测试 → artifact 上传。Release v1.3.2 绑定成功构建提交，并仅使用该次 artifact。公开下载后比较 SHA-256 与实际包检查结果。

## 未覆盖与限制

没有目标设备连接，因此未做安装、PAC 动态行为、thermalmonitord 主队列契约、真实节流/恢复、长期稳定性、耗电或 watchdog 验证。类布局反例不是对 iOS16.5 私有类布局的断言。补读/重试仍是有上限恢复，不能保证任意长 cfprefsd/notify 故障后自动恢复。会话号提供 freshness 而非认证，Darwin notify 不是本插件的安全隔离边界。

代码签名检查针对本项目的嵌入式 ad-hoc Mach-O，验证结构、完整代码覆盖、页及嵌入特殊槽哈希，不是 Apple 证书链、信任缓存或设备加载验证。RootHide/SDK 固定提交，Homebrew 和 Action 主要版本仍会变化；归档规范化不等于整个编译链可重复构建。

1.3.2 完整交付必须以对应 GitHub build 和 Release 的状态为准。安装或升级后注销一次，从 Off → Light → Off 开始，并检查新日志及崩溃报告。
