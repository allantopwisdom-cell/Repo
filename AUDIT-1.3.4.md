# Powercuff v1.3.2 完整源码发行标准复审与 v1.3.4 修订

## 审计基线与发行结论

用户指定基线为 v1.3.2：源码 `4b0bd73fa3e0e11ea9002a0320d65691a1001f02`；公开 DEB 17,020 字节，SHA-256 `74e5bccf2033c0f16bb0570c70ed8f89b0cded44b72dadafa001c7b59a79c1db`。再次核对 Release API 和本地保存的公开包。GitHub 上该版本实际为 `prerelease=false`，不能据此推断已经真机验收。

本轮在 v1.3.3 的修复之上实施，以免丢失偏好域隔离、完整 ABI 检查及归档规范路径等已完成修正。v1.3.3 源码 `9eb198b9bda0306ca2816d84220fde8084cdf7b9`，DEB SHA-256 `61e124e2a779a9a6df434dc482145c429dd1537626559f4a6f8d7e0a141e12b2`，17,230 字节。

目标设备仍为 iPhone 14 Pro Max (iPhone15,3) / iOS 16.5 (20F66) / RootHide Dopamine 3.0.4。发行要求分为源码/自动化门禁与设备运行门禁。没有连接目标设备，不能签署稳定版的安装、PAC、私有热控接口线程契约、watchdog 或续航验收。v1.3.4 因此交付为**发行候选版（GitHub Pre-release）**；不是通过更改标签把未完成的真机项目标为通过。

## 问题分级、复现与修复

| 编号 | 等级/证据 | 发现与影响 | v1.3.4 处置 |
|---|---|---|---|
| F01 | 中，代码路径可确定；虚拟传输执行验证 | v1.3.2/1.3.3 首次应用后 `PCRRequestFresh` 因 lastApplied>=0 不再发起请求；读取失败重试耗尽即返回，可能保留旧档位，诊断值仍显示最后成功模式 | 分离“等待回复”和“最后应用模式”。读取耗尽后最多追加一轮六次新鲜回复请求，始终绑定当前会话；持续失败不反复启动新循环，报告状态11；同档位有效回复只恢复诊断，不重复私有调用 |
| F02 | 中，源路径可确定 | 启动请求全部耗尽但没有回复时，applied 可一直停留10，缺乏明确的超时提示 | 最后一轮请求后增加一次有限超时检查。新 generation/有效回复/对象消失/ABI或异常熔断令检查失效；状态11明确表示旧档位可能仍有效，并不代表已恢复Off |
| F03 | 中，实际 v1.3.2 包修改实验 | 旧 verifier 接受附加未审查命令的 postinst，也接受图标内容改变；这些内容不在 Mach-O 签名覆盖范围 | `--source-root` 比对全部维护脚本原字节、控制字段、静态plist语义、图标原字节。仅豁免并验证 Theos 生成的正数 Installed-Size。CI和build.sh强制源码对照 |
| F04 | 中，实际 v1.3.2 包修改实验 | 旧 verifier 接受动态库 mode=0000，代码签名仍通过但移动用户无法读取 | 精确检查动态库0755、静态文件0644、维护脚本0755、control0644；保留0/0属主及目录0755要求 |
| F05 | 低，确定的门禁缺口 | 依赖仅验证路径前缀，允许未审查的同前缀动态库；control的Depends/Conflicts未和源码比较 | 当前固定工具链下要求五项精确 Mach-O 依赖集合、无重复；包控制字段对照源码；增加实际DEB依赖元数据反例 |
| F06 | 中，构建流程缺口 | 本地 `build.sh` 原来只调用make，规范化和完整验证仅在CI之后执行；手工构建可能得到501/20属主原始包 | 将规范化、源码对照和实际包负向测试纳入 build.sh。验证失败非零退出；POSIX sh 使用重定向后cat，避免tee掩盖失败。源码ZIP构建需提供SOURCE_DATE_EPOCH |
| F07 | 低，供应链/证据缺口 | Actions采用可移动主要标签；host测试先于指定Xcode；产物只记录Theos/SDK引用，没有实际测试输出和宿主工具版本 | 固定3类Action到核对后的完整提交；先设Xcode15.4再测试；bash启用失败传播；附源码测试输出、构建环境与全仓库跟踪文件SHA256 |
| F08 | 中，测试覆盖缺口 | 旧测试验证解析/类型和归档，但不执行实际异步重试、替换对象、熔断及恢复流程 | 将生产静态核心移入PCRCore.h，由插件和macOS harness直接共享；以虚拟时钟/内存notify和假product执行真实核心。不是另写一套状态机去测试自己 |

F03/F04的旧门禁缺口已本地复现：修改公开v1.3.2的postinst、icon.png、dylib文件权限三个实验，原版本校验均返回通过。本轮实际包反例除签名外还覆盖未审查脚本、图标、不可读动态库和依赖元数据；临时变异包不会作为交付产物。

本轮不声称这些合成条件已在用户设备发生，也没有把原有thermalmonitord SIGBUS/watchdog归因于上述问题。信号崩溃和watchdog仍无法由Objective-C异常处理捕获。

## 完整项目覆盖与文件边界

| 文件/范围 | 本轮核查与结论 |
|---|---|
| Powercuff.x | ctor进程/iOS版本限制、观察者注册、CommonProduct/GPProduct hook选择、初始化返回对象捕获、SpringBoard启动补发；仅保留hook/装配，核心共享 |
| PCRCore.h | 所有生产发布、请求、偏好补读、读取恢复、私有派发、异常熔断、弱引用和generation失效；无永久轮询，新状态11可诊断超时 |
| PCRProtocol.h | v2前缀、非零32位会话、保留位和0..4档位；保留格式，不让更早版本裸值进入新会话 |
| PCRPreferences.h | 单持久域不可变快照、NSNumber与CFBoolean区别、有限整数、门控值合法性；继承1.3.3修复 |
| PCRRuntime.h | 对象/void/block编码、self/SEL、参数数目、继承和同IMP不同方法归属；继承1.3.3修复 |
| Makefile/control | arm64e单架构、iOS16.0最低目标、16.5SDK、roothide scheme、包ID/版本/依赖/冲突、作者；仅升级版本号，不声称支持rootless或其他iOS主版本 |
| build.sh/.github/workflows/build.yml | 检查传播、规范化、精确产物选择、源码/环境记录、提交固定、最小contents:read权限；标签不另行重编译覆盖附件 |
| scripts/check.sh | shell/plist、17项Python、C协议及3个macOS真实Foundation/runtime/core可执行程序 |
| scripts/verify_package.py | ar/tar边界、文件模式、allowlist、版本/控制字段、源码资产、Mach-O/精确依赖、iOS目标、RootHide install ID、签名哈希 |
| scripts/macho_signature.py | 代码完整覆盖、代码页/特殊槽哈希、slot/边界/重复/重叠；保持本项目ad-hoc校验边界，不冒充Apple信任验证 |
| scripts/normalize_package.py | 归档属主、组、mtime规范化；签名payload原字节不变；幂等测试 |
| scripts/test_built_package.py | 对实际构建包运行签名篡改和完整包变异反例，要求未改变的包先通过来源对照 |
| layout/DEBIAN/postinst/prerm/postrm | configure/remove只请求一次kickstart，失败最多一次TERM；不以root写mobile偏好、不强杀、不在purge重复重启；本轮不改生命周期动作 |
| filter与偏好plist、三张图标 | 精确限定SpringBoard/thermalmonitord；档位0..4、默认Off、门控默认false、域和通知一致；源码/产物逐项对照 |
| verify-on-device.sh | 只读路径、偏好和notify诊断；补充状态11及残留档位说明；不把通知值当存活/节流证明 |
| tests/*.py/*.m/*.c | 解析、归档、生命周期、资产来源、实际Foundation/runtime和核心异步路径；测试方法与局限见下表 |
| README/AUDIT/ANALYSIS/BUILD-REVIEW | 当前README指向本报告；旧报告仅历史证据，不参与编译，不作为本版本真机放行证明 |
| 根目录历史1.1.x/1.2.x DEB | 历史归档，不参与当前Makefile、layout或CI产物选择；未将其重新打包冒充新源码构建。全部跟踪文件哈希随本次产物记录 |

## 核心流程执行验证

tests/test_core.m 直接包含生产PCRCore.h，通过测试适配层替换时钟、队列入队、notify传输、偏好读取和LPM输入。Foundation/Objective-C runtime和真实消息派发仍由macOS执行，假product仅记录调用/抛合成异常，不触碰系统热控对象。12组场景：

1. 注册失败时token无效并拒绝启动观察。
2. 首次会话握手、响应取消后续请求、同档位不重复私有调用。
3. 成功后读到旧会话，有限重新请求当前模式。
4. 持续读失败队列最终清空、请求不超过追加预算、状态11；后续有效Off恢复。
5. publisher缺失时六次请求后停止，迟到的有效回复可恢复。
6. 偏好缺失有限等待后默认Off。
7. Objective-C异常对当前对象熔断，替换对象后重新握手。
8. 不支持ABI的对象在消息派发前拒绝。
9. 新product使旧异步请求失效，旧对象不收到迟到应用。
10. 延迟捕获不强持有已销毁的product。
11. 快速修改偏好和LPM变化使用当前值，旧补读不应用历史档位。
12. set/post短暂失败在预算内恢复。

这不等于跨进程真实notify服务、cfprefsd可见性、并发系统负载或主队列私有契约测试。它能验证实际生产函数的状态转移与任务上限，不能证明设备PAC或低功耗收益。Linux跳过macOS程序不算通过；以本版本Actions和附件SOURCE_TESTS.txt结果为准。

## 构建与发行门禁

- Linux：17项Python、C协议、shell、plist、diff检查；公开旧包用于门禁反例复现。
- GitHub macOS14/Xcode15.4：全部源码检查，包括真实Foundation、runtime及生产核心执行测试；RootHide arm64e编译链接/签名。
- build.sh：归档0/0规范化 → 精确包/签名检查与源码比对 → 实际包反例。任一步失败则不上传artifact。
- provenance：SOURCE_COMMIT、SOURCE_FILES.sha256、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、SOURCE_TESTS.txt、verification.txt、DEB SHA256SUMS。
- 发布使用同一成功run的artifact，tag绑定同一源码提交。公开下载后核对DEB SHA256、再跑源码对照/签名/反例；所有附件摘要与本地产物比较。

3类Action固定提交：checkout `11d5960a326750d5838078e36cf38b85af677262`；upload-artifact `ea165f8d65b6e75b540449e92b4886f43607fa02`；setup-xcode `ed7a3b1fda3918c0306d1b724322adc0b8cc0a90`。Theos与SDK固定引用保持不变。Homebrew、runner镜像和系统工具并未完全固定，记录实际版本不等于全链可重复构建。

## 发行阻塞项与可用性限制

| 项目 | 当前证据 | 放行要求 |
|---|---|---|
| iPhone15,3/iOS16.5/RootHide3.0.4真实加载与PAC | 无连接设备，未验收 | 全新安装/升级/卸载、注销后两进程加载正确版本，无新增崩溃 |
| 私有API与系统热策略恢复 | 仅ABI检查和假对象执行 | Off→Light→Off、LPM进出、充电/热状态变化下真实节流与恢复符合预期 |
| watchdog/长期稳定性 | 不能由静态签名和异常捕获保证 | 新日志、crash记录、待机唤醒、两进程分别重启后恢复；任一新增daemon崩溃/watchdog阻塞稳定版 |
| 续航/流畅度 | 没有测量结果 | 同亮度、网络、温度与负载多次对照，不以“已返回私有方法”替代掉电/帧率证据 |
| 与Hello CPU等叠加 | 未验收 | 先独立测试，再逐个恢复插件；不承诺竞争策略组合稳定 |

通信超时可能保留先前模式；状态11不是Off，也不执行猜测性私有恢复调用。新有效状态或新product可恢复，持续故障超过有界窗口需要新的设置事件/进程恢复。Darwin notify提供协调而非认证，32位会话防旧缓存不等于安全隔离。默认Off、档位名称、注入范围、主队列访问策略没有为“省电”而激进改变。

没有设备反馈时，继续更换hook点、线程或强制频率不能补上发行证据；本轮以确定缺口及可执行反例为依据修复，不授予无依据评级或“完美适配”结论。
