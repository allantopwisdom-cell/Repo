# Powercuff v1.3.10 逐项复审及 v1.3.11 正式发行审计

日期：2026-10-31（Asia/Shanghai）。目标：iPhone14ProMax（iPhone15,3）、iOS16.5（20F66）、arm64e、RootHide Dopamine3.0.4。没有连接该设备，主机测试、Mach-O结构和签名完整性不能作为PAC执行、真实温控恢复、watchdog或续航实测证明。

## 1. 发行基线与本轮结论

正式v1.3.10：提交 `93c65728bd6872500d3c6f5a74d3b2bd2b206418`，81个跟踪路径；公开DEB18742字节，SHA-256 `800caaeba29e2c3fd3fec39ce20bb99af0fd5b03b9844e5a20ea20b29f75ba83`。重新读取GitHub Release/标签元数据并核对原包，draft=false、prerelease=false，13项上传附件齐全。

当前main为 `ccfa07017604e1002f7ab4dfd472805d507e3064`，已合并正式源码及Node24维护；与v1.3.10运行时代码一致。release/powercuff-1.3.11从此建立，继承已验证的checkout/upload-artifact固定提交和Ubuntu24.04发布runner。

本轮发现并修复3类可复现发行门禁问题，新增字段格式边界验证。**没有复现新的运行时代码缺陷；Powercuff.x、PCRCore.h、PCRPreferences.h、PCRProtocol.h、PCRRuntime.h保持v1.3.10字节不变。** 不因需要新版本号而无依据修改热压力、私有调用、线程或重试。v1.3.11从受审源码全量编译，版本、公开附件和来源单独追踪，不替换旧包。

新增当前AUDIT/BUILD/RELEASE三份文档及test_control.py，共85个跟踪路径。旧报告、旧DEB和1.3.4工具保留为历史资料，不能作为当前安装交付或真机放行证明。

## 2. 已复现问题、严重程度与修复

| 编号 | 复现/影响 | 修复与验证 |
|---|---|---|
| F1：control解析与dpkg不一致，发行阻断级 | 对原签名DEB临时副本，仅在Depends前插入空行；旧完整验证器含源码对照仍通过，dpkg-deb只读解析退出2。旧解析器忽略空行，将本应分开的段拼回一份字典 | 按单段二进制control解析：中途空行或仅空格/Tab的行结束该段，之后有字段即拒绝；允许前后空白与CRLF。实际包变异必须因多段拒绝 |
| F2：独立依赖/冲突检查缺失，适配门禁缺口 | 将preferenceloader改成其他包，旧不带source-root的完整包检查通过；dpkg读出的Depends确已变化。带source-root原先能识别，本轮补齐独立路径 | 固定4项Depends及4项Conflicts，要求集合和值准确、无遗漏/新增/重复；保持源码逐项对照。对改名、缺失、重复依赖和缺失冲突分别在有/无源码路径拒绝 |
| F3：自洽不等于完整，发行证据缺口 | 本地删掉DEB或SOURCE_TESTS、verify_release、审计等文件，同时改远端模拟集合并重算清单，旧验证器仍接受；额外加入未审阅DEB并保持所有哈希自洽也接受 | 在全部清单哈希之外独立强制13项版本匹配的必备资产集合，包含唯一正确命名DEB与当前三份文档；草稿/公开均执行，不允许通过改清单改变契约 |
| F4：字段大小写/字符/物理行边界，解析加固 | 旧解析器区分Package/package，使用Unicode splitlines/isspace会把U+0085/U+2028/U+2029当成Debian新行，未拒绝非法字段名或控制字节 | 字段名按ASCII规范检查、大小写无关拒绝重复；值仅裁剪Space/Tab；按LF/CRLF物理行解析，保留合法UTF-8值；拒绝空值、NUL/VT/裸CR等控制字符 |

上述临时副本没有改动原发布包，也没有安装或执行维护脚本。F1意味着校验器会放过无法正常解析的包，不表示已发布v1.3.10自身存在该空行；原包通过新检查。

依据：[Debian Policy 5.1/5.3](https://www.debian.org/doc/debian-policy/ch-controlfields.html)规定二进制control单段、字段大小写不敏感和字段/段边界；[deb-control(5)](https://manpages.debian.org/trixie/dpkg-dev/deb-control.5.en.html)说明实际包元数据格式。实现限定本项目产物，不宣称通用Debian打包器。

## 3. 因果验证与结果边界

修复前，新增test_control.py的5项方法在旧解析器上产生16个失败子用例；更新为真实13项资产结构的发行测试共9项方法，其中新增缺项/额外项检查产生5个失败子用例。均为“应拒绝未拒绝”或Unicode物理行解释错误；原有正例保持通过。修复后两组全部通过。

真实v1.3.10签名DEB反例中，插空行的旧完整检查通过、dpkg-deb只读读取失败；改依赖的旧独立检查通过、dpkg读取结果显示变化。新检查接受未改原包，拒绝这两个反例及缺失/重复依赖、缺失冲突。基线失败不涉及目标设备操作、主机原生编译失败或虚构崩溃。

本轮Python63→70项；原生核心27组、实际构造函数9组保持原断言和任务上限。实际包16类变异加签名反例；依赖4类、布尔档位另做无源码目录拒绝检查。最终macOS成功、实际新DEB和公开资产证明来自SOURCE_TESTS.txt、verification.txt、SOURCE_COMMIT、SOURCE_FILES.sha256及Release追加的真实构建运行，不把本说明中要求的门禁预写成已成功。

## 4. 当前源码、功能与架构逐层复核

| 文件/层 | 逐项职责、结论及边界 |
|---|---|
| Powercuff.x：入口 | 只接受SpringBoard/thermalmonitord和iOS major16；准备通信后分别检查角色；publisher必须取得LPM观察对象；daemon检查CommonProduct/GPProduct初始化/应用ABI和方法所有权。保留未就绪回调门禁 |
| Powercuff.x：hook | 包装initProduct:，使用原返回对象弱捕获，不伪造系统对象；继承实现避免重复hook。激活先入队，随后hook捕获排队；真实对象初始化时机须设备确认 |
| PCRCore.h：角色队列 | daemon使用main queue，publisher独立串行queue；状态/对象只在角色队列读写。readiness由角色队列激活，失败路径在激活提交前清理通信token；无新跨线程撤销 |
| PCRCore.h：初始化失败 | 必要注册、LPM观察或类ABI失败时关闭新通信，逐一取消并清本地token；取消失败/已排队回调不能绕过门禁；诊断注册best-effort，99保留。不能据此保证已清除旧模拟 |
| PCRCore.h：对象生命周期 | 弱引用不保活私有对象，异步解引用后用局部强引用完成一次调用；对象替换使旧请求/读取代际失效，重置每对象缓存/熔断；实际对象通信前和调用前校验ABI |
| PCRCore.h：状态发布 | 指定持久域单快照+当前LPM；延迟任务读取当前值；set_state或post失败使发布缓存失效；快速回Off仍修共享状态；不从root读mobile偏好 |
| PCRCore.h：应用与恢复 | 当前会话解码、同模式去重、明确设置事件换会话、一次有限读失败恢复；旧Heavy回复不能确认新Off；异常98/ABI99熔断，不猜档、不无限私有调用 |
| PCRPreferences.h | 模式NSNumber非布尔、有限整数值0..4，门控NSNumber/布尔0或1；异常值Off、缺值有限重读；无跨域fallback或偏好写入 |
| PCRProtocol.h | v2高24位0x504302、非零32位会话、低字节0..4/请求0xA5；拒绝旧会话/裸数字/坏头/保留位；会话是新鲜度协调，不提供认证 |
| PCRRuntime.h | 3个参数、self/cmd、对象入参和返回ABI；拒绝block/标量/错误返回；方法所有权决定独立hook，不能用相同IMP推断继承 |
| 两个plist及图标 | 注入精确两进程，两个偏好键、五个整数值和中文标题；图标逐字节、plist保留类型对照并拒绝重复键/重复设置项；无Settings/App/Widget注入 |
| Makefile/control | iOS16.5 SDK/部署16.0、arm64e、RootHide scheme、Foundation、ARC；包ID/依赖/冲突不变，版本1.3.11；不是通用rootful/rootless包 |
| build.sh/normalize_package.py | clean/package/ldid后规范化数值0/0属主与源码提交时间，保持签名payload字节；失败退出，不将旧dylib替换后冒充源码编译；ZIP源码无git时需显式SOURCE_DATE_EPOCH |
| verify_package.py | Debian成员/压缩、路径/类型/权限、Mach-O/签名、plist和受审资源对照；本轮修复control语义及独立Depends/Conflicts检查 |
| macho_signature.py | CodeDirectory版本布局、代码页和requirements特殊槽覆盖及哈希、无异常entitlement/散列范围；拒绝-O。完整性不等于证书信任/PAC可执行 |
| verify_release.py | 源码提交/tag/版本/可见性/正式属性、清单覆盖和大小/digest；本轮增加独立必备13项契约，不依赖清单自我定义完整性 |
| test_built_package.py | 在真实已签名DEB上独立变异、明确拒绝理由；保留签名/ABI/路径/资源/类型反例，新增control多段及依赖/冲突场景 |
| prepare_startup_test.py/check.sh | 从实际%ctor提取分支，仅替换hook安装调用，用Foundation模拟通知/虚拟时钟；C协议、shell/plist/Python先行，macOS原生再编译运行 |
| postinst/prerm/postrm | 按动作和确认的服务域有限重启；保留偏好、真实命令错误和人工注销提示；无root写defaults、自动注销、killall/SIGKILL；本轮未改 |
| verify-on-device.sh | mobile uid501、只读安装版本/文件/偏好/notify快照；读取失败显示有效模式未知，残留loaded/hook/applied不作活性证明；本轮未改 |
| build.yml | Node24固定Actions、固定Theos/SDK、macOS15/Xcode16.4，完整回归后打包；同运行artifact草稿核验后公开；公开后复核非公测/Latest/tag |

历史DEB、旧AUDIT/BUILD/RELEASE、旧1.3.4采集器和哈希记录作为历史文件逐项列入85路径清单；其旧结论不继承为本版设备证据。当前生产调用路径、打包/诊断/测试与发布路径按上表复核。

## 5. 全部用户设置和五档

| PowerMode | 标题 | 私有接口参数 | 解释/默认/测试 |
|---|---|---|---|
| 0，默认 | 关闭 | off | 请求退出模拟；系统真实过热保护保留；方法返回不等于温控已实测恢复 |
| 1 | 标称（仍在模拟） | nominal | 仍在模拟，不能等同关闭 |
| 2 | 轻度 | light | 首次单独验证Off→Light→Off，不承诺固定频率或省电比例 |
| 3 | 中度 | moderate | 用户可选，未认定为目标机最佳常驻档位 |
| 4 | 重度 | heavy | 保留选项，不提高默认热压力，性能/流畅度和续航须实测 |

| RequireLowPowerMode | LPM关闭 | LPM开启 | 保存的PowerMode |
|---|---|---|---|
| 缺省/false/数值0 | 请求保存档位 | 请求保存档位 | 不改写 |
| true/数值1 | 请求Off | 请求保存档位 | 不改写 |
| 非法类型或数值 | Off | Off | 不改写 |

模式接受NSNumber的0..4整数值，2.0可表示2；拒绝布尔、字符串、容器、NSNull、负数、越界、非整数、NaN/无穷等。门控仅允许数值0/1或布尔；缺档有限重读后默认Off。升级/卸载保留偏好，重装不保证因“默认Off”而清除原已保存设置。

五档×两种LPM×两种门控、同档去重和Off恢复由现有生产核心测试实际发送字符串验证。设置资源必须严格使用整数模式/布尔门控类型，不能用Python的True==1替代；该防护与重复plist键检查保持。没有独立控制中心模块、固定CPU/GPU频率、后台冻结或帧率控制功能；没有以Hello CPU联用的1428MHz设定改写插件。

## 6. 通信预算、稳定性和失败状态

| 项目 | 固定行为与风险边界 |
|---|---|
| 请求/发布/读取 | 初次+5次，400ms间隔；代际取消旧任务，不持续轮询 |
| 请求超时 | 最后请求再等400ms，状态11并结束该轮；旧模式可能仍在 |
| 设置/LPM补发 | 立即/150/600ms，读取当前值；新变更取消旧刷新 |
| 启动补发 | 立即/3/10/30/60秒，之后停止 |
| 会话 | 新对象、明确设置编辑、有限读失败恢复时更新；随机只取一次，排除零和紧邻上一值，不保证永久全局唯一 |
| 异常熔断 | 98为ObjC异常，99为ABI不符，当前对象停止尝试；设置不能绕过，新对象重新检查；不能拦截SIGBUS/SIGSEGV/watchdog |
| 诊断 | 10等待、11通信失败，均不能解释为已经Off；loaded=1仅表示曾进入初始化，不证明ready/当前进程存活 |
| 整体通知失败 | 发布端缺席、全部消息丢失、偏好可见性超出有限窗口时不能保证Off生效；需要真实日志/人工用户空间重启确认 |
| 外部热控覆盖 | 同档缓存不监视其他插件修改模拟；不能保证Hello CPU等联用安全 |

27组核心保留会话新鲜度、重放/竞态、发布缓存修复、请求有界、对象替换/释放、ABI/ObjC熔断、偏好延迟和LPM恢复。9组构造函数保留必要注册失败、提前/迟到回调、取消失败、缺LPM观察者、ABI拒绝、非目标进程/iOS17、可选诊断失败和hook期间捕获顺序。没有为“稳定性优化”新增未知私有接口、主线程同步等待或广泛服务重启。

## 7. 适配和安装维护矩阵

| 环境/环节 | 静态/主机已覆盖 | 设备限制 |
|---|---|---|
| iPhone15,3/iOS16.5(20F66) | SDK16.5、部署16.0、major16守卫、PAC00结构与ABI预检 | 无真机PAC执行、真实类/线程/温控证据 |
| RootHide Dopamine3.0.4 | scheme、iphoneos-arm64e、.jbroot安装ID/依赖路径与确切依赖集合 | 不证明目标机实际注入或服务已重载 |
| iOS16其他机型/小版本 | firmware>=16且<17、运行时不兼容停止 | 依赖区间不等于所有设备已认证；iOS17不运行 |
| rootful/普通rootless | 本次无该变体 | 不将RootHide包作为通用安装包 |
| 安装/升级/卸载 | configure/remove分支、前台域优先/system按需、一次kickstart及失败同目标最多一次TERM | exit0只说明命令被接受，不证明新PID/新代码；实际reload需日志 |
| 历史SIGBUS/watchdog/Widget | 精确注入两系统进程、ABI门禁/有限请求/ObjC熔断 | 不能宣布历史崩溃或第三方注入链问题已解决 |
| Hello CPU/其他热控 | 已知Powercuff变种冲突集合不变，独立校验现在也强制该集合 | 未知插件不一定被包冲突识别，先单独验证 |

安装/升级后人工注销一次让两端代码替换；自动重启跳过/失败时通过越狱应用重启用户空间。卸载重载daemon移除hook，人工注销publisher；偏好保留。Sileo的“某依赖可自动移除”与安装失败不同，不自动清理其他包。首轮只测试Off→Light→Off及LPM进出，再依据实测考虑Moderate。

## 8. 测试、包和正式发行链

Python70项覆盖control、plist、payload/归档/权限/属主、CodeDirectory、源码资源、发行契约、维护服务域、诊断身份及失败路径；原生Foundation参数/runtime、27组核心、9组实际constructor加C协议/shell/plist检查保留。不给测试总数赋予“军工级”或设备无崩溃保证。

macOS15/Xcode16.4，RootHide Theos `cfba89a53a05b4a1b822121158acc3669c20602f`，SDK `0222fd5413cf4b9af096f37b4621afa2688572f7`；Actions固定已核对SHA/Node24，发布runnerUbuntu24.04。Homebrew及runner未完全固定，实际版本看BUILD_ENVIRONMENT.txt，不承诺全部构建逐字节可复现。

签名完整性检查CodeDirectory代码页/requirements特殊槽；薄arm64e PAC00 subtype0x80000002、设备平台、部署16.0、精确导入集合/RootHide install ID；6个payload与4个control文件、必要目录白名单/权限/数值0/0属主。规范化只改归档时间/属主，不改已签名payload。普通控制字段格式加固不更改本包实际Depends/Conflicts或维护脚本。

正式发布只接受release/powercuff-1.3.11的push且build成功：从同运行下载artifact，检查版本/源码提交/SHA256SUMS；新tag绑定成功提交，旧tag/Release不覆盖；草稿上传13项后用新校验器验证完整契约/哈希/大小/stable类型，再公开设Latest并复核tag、公开属性和Latest ID。

13项契约为DEB、AUDIT/BUILD/RELEASE当前文档、SOURCE_COMMIT、SOURCE_FILES.sha256、SOURCE_TESTS.txt、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、verification.txt、VERSION、verify_release.py、SHA256SUMS。清单覆盖其余12项，GitHub资产digest还覆盖清单自身。GitHub源码ZIP/TAR来自同一标签。

交付独立核验artifact摘要/大小及安全解压13项、85路径来源哈希、当前报告/验证器与受审源码一致、70/27/9真实记录；公开DEB与同次artifact逐字节一致；本地再执行包与实际变异检查。不能用仅仅“清单自洽”替代已知必备集合或源码/CI来源证据。

## 9. 真机逐项验收表

| 项目 | 必须记录的目标机证据 | 本轮状态 |
|---|---|---|
| 安装升级卸载 | 版本/架构、Sileo结果、服务域、注销后两端新加载、卸载后hook移除 | 包/脚本验证，真机待验 |
| 五档与LPM | 每档选择/保存/实际字符串返回、LPM进出、保存值不变 | 主机全组合，物理效果待验 |
| Off恢复 | 当前会话Off回复、方法返回、模拟退出/自然过热保护恢复 | 合成对象逻辑，真实温控待验 |
| 两端重载/待机 | daemon/SpringBoard分别先后重载、发布端缺席、恢复/唤醒后状态 | 主机有限时序，生命周期待验 |
| 崩溃/watchdog/PAC | 新加载后无新增SIGBUS、符号化日志、thermalmonitord心跳正常 | 无新目标机证据 |
| 续航/流畅度/联用 | 同亮度/网络/负载重复对照，先单独启用再逐项加其他热控 | 无测量，不能给省电百分比/最佳档位/联用安全结论 |

mobile(uid501)只读运行verify-on-device.sh；状态可能残留，偏好不可读时有效模式未知。持续11、98/99、新增daemon崩溃或温控异常需按实际证据处理。正式元数据表示GitHub发行类型；本轮结论限于列出的源码审查、可复现门禁修复、主机和实际产物验证。
