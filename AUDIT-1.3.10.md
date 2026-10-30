# Powercuff v1.3.9 全项目复审及 v1.3.10 正式发布审计

日期：2026-10-31（Asia/Shanghai）。目标：iPhone 14 Pro Max（iPhone15,3）/ iOS16.5（20F66）/ RootHide Dopamine3.0.4 / arm64e。按用户要求在构建门禁通过后发布非 Pre-release 的正式 Release。没有连接目标设备，正式属性不代表 PAC、真实私有接口、温控恢复、watchdog 或续航已经实测。

## 1. 基线、完整范围与证据

已发布 v1.3.9 对应 `92aedbb5fec9a9973e1a45af7c6df22d131abaa8`，75 个跟踪路径。公开 DEB 18288 字节，SHA-256 为 `6ec6e3bfc867b1851c2b063135989837cbff29c2d34b6140d1f10f8c77810249`。复核公开版本、稳定发布属性及此前成功构建；保持旧标签、旧包和其他工作区不变。新分支 release/powercuff-1.3.10 从该提交建立。

本轮复读五个生产源码文件、注入和设置 plist、资源、Makefile/control/build.sh、三个维护脚本、当前诊断脚本、打包/签名/发行验证器、当前测试与 GitHub workflow。历史 AUDIT/BUILD/RELEASE、1.3.4 专用工具和根目录旧 DEB 仅作历史资料，仍列入来源清单，不作为当前二进制交付。

新增三份当前文档、constructor 提取器、原生启动故障测试、plist 专项测试，共81个跟踪路径。最终精确集合、内容及执行位以实际 GitHub tree、SOURCE_FILES.sha256、SOURCE_COMMIT、成功运行 head_sha 和新标签共同核验。本报告不预填尚不存在的构建成功或新 DEB 哈希。

## 2. 问题、因果与精准修复

| 编号 | 源码/反例证据 | 影响与修复 |
|---|---|---|
| F1：半初始化通信 | SpringBoard 的设置 observer 注册成功后，request observer 失败直接返回；前者仍存在，LPM observer 与启动安排尚未完成。其他必要注册失败亦未清理已经取得的通信令牌 | 事件可能发布档位，却不再跟踪 LPM 退出。新增所属串行队列上的 readiness 门禁；全部必要注册和角色检查完成才排队激活。失败逐一取消并重置已拥有的通信令牌；提前或取消后已排队回调均不得工作 |
| F2：plist 数值类型混淆 | 原比较使用 Python `==`，True==1、False==0、0.0==0；对实际 v1.3.9 DEB 的临时副本仅将 validValues 中整数1改成布尔True，旧完整验证器仍接受 | 运行时明确拒绝模式布尔值，错误的面板元数据可能把选项变为 Off。改为递归、严格标量类型比较；兼容 XML/二进制编码和字典顺序，保留 bool/int/float 区别。独立包校验也强制五个整数值、整数默认0、精确标题及布尔门控默认值 |
| F3：重复 plist 键被解析器丢弃 | 常规 plistlib 字典覆盖重复键；最终值相同仍可形成歧义。新增 XML 和手工二进制字典反例 | 解析时通过唯一键字典立即拒绝重复键；另检查面板恰好两项唯一偏好键，不允许重复条目或新增未审阅参数 |
| F4：构造函数验证缺口 | 原27组核心测试直接准备好通信状态，没有执行真正 `%ctor` 的注册失败分支 | 从实际 Powercuff.x 提取唯一构造函数，只替换两个 Logos hook 安装语句；用 Foundation 主机适配器模拟 notify、队列、LPM 和合成类。新增9组故障/正常路径，不复制生产分支、不执行真实hook或设备操作 |
| F5：构建文档最低版本 | 现有打包代码使用 Python3.9 的 removeprefix，旧说明仅写Python3 | 文档准确标为Python3.9+；没有增加第三方Python依赖 |

没有通过更改五档、提高默认热压力、扩大重试预算或持续轮询规避缺陷。未改动协议格式、偏好域、包ID、架构、依赖、冲突集合和维护脚本。

## 3. 复现与回归证据分级

plist 基线测试对旧比较器新增两项方法，7项方法执行中有8个子用例失败，均为应拒绝但未拒绝的布尔/整数/实数替换；新验证器拒绝这些替换。另对真实旧 DEB 的临时变异副本复现布尔档位绕过，原公开包没有被修改，也不表示原发布包已包含错误类型。

GitHub 原生基线分支相对 v1.3.9 只增加 tests/test_startup.m、scripts/prepare_startup_test.py、scripts/check.sh，生产代码未改。首次运行41107204638因测试辅助函数 Enqueue 与 macOS 系统头声明冲突而编译失败，该结果不算生产故障复现；测试函数加专属前缀后，以 `aa94798529ca3eb51c04f5625f73459a2bb494f6` 重新运行 [41108411474](https://github.com/allantopwisdom-cell/Repo/actions/runs/41108411474)。macOS15/Xcode16.4上57项Python、C协议、plist、Foundation参数/runtime及27组核心通过，随后test_startup.m:212的 `ModePosts == 0 && RequestPosts == 0 && PreferenceReads == 0 && !LPMHandler` 断言失败，Abort trap、退出134；build失败、publish跳过。该场景在第二个发布端observer失败后运行实际旧constructor已排队的首个回调，确认出现半初始化发布，属于真实生产逻辑复现，非环境/编译错误。

修复版保留全部27组生产核心断言、任务上限和代际取消约束。新增启动回归9组：

1. 发布端四个必要注册分别失败，禁止读取偏好/发布，无残留通信令牌；迟到回调仍无动作。
2. daemon 四个必要注册分别失败，不安装hook、不请求、不调用合成私有方法。
3. LPM观察对象缺失，发布端关闭通信且不发送档位。
4. 初始化期间已排队事件不能抢先工作；正常激活仍按0/3/10/30/60秒发布五次；退出LPM按0/150/600ms发送Off，保存档位不变。
5. notify_cancel 返回失败时仍清空本地令牌并保持未就绪；已排队/迟到回调不能重新启用发布。不能据此声称服务端资源已释放。
6. 无兼容thermal类时关闭通信，保留99诊断，不安装hook。
7. 非目标进程或iOS17不注册、不发布。
8. best-effort诊断注册失败不替代必要通信检查，兼容daemon仍可正常激活。
9. 激活先于hook期间捕获排队；无发布端时仅六次请求，当前会话Off回复可到达合成接收对象。

新增6项Python方法（57→63），包括递归类型比较、XML/二进制等价与重复键拒绝；实际构建 DEB 的布尔档位及重复键变异也必须拒绝。布尔档位还在没有源码目录时独立检查拒绝理由。主机结果不证明 notify 服务在设备上的时序或真实私有类行为。

## 4. 架构、对象和线程

| 层 | 职责及本轮检查 |
|---|---|
| Powercuff.x | iOS major16/目标进程守卫；准备角色通信；publisher取得LPM观察者才激活；daemon通过类/ABI/方法所有权检查后，先排队激活再安装初始化hook |
| PCRCore.h：初始化 | readiness初值NO，只在角色串行队列写YES/读取；注册回调统一包装门禁；失败只在激活排队前执行取消，不与已激活状态并发撤销。五个通信token各取消一次并置-1；诊断token保持可读 |
| PCRCore.h：publisher | SpringBoard独立串行队列；每次读取指定持久域快照和当前LPM；有限补发读取当前值，旧代际不能覆盖新编辑；失败使去重缓存失效 |
| PCRCore.h：daemon | 主队列处理弱product、会话、请求、应用、去重与熔断；实际对象捕获及调用前均检查ABI；对象替换使旧任务失效。保留1.3.9的新请求周期换会话修复 |
| PCRPreferences.h | 指定持久域单快照，不跨域fallback；模式类型/范围、LPM门控及无效值Off；升级不写入或重置用户设置 |
| PCRProtocol.h | v2高24位头、非零32位会话、低字节模式0..4或请求0xA5；会话仅用于新鲜度，不是认证 |
| PCRRuntime.h | 3个参数、self/cmd、对象入参和返回类型；拒绝block/标量错配；按方法真实所有权避免继承initializer重复hook |
| 资源与依赖 | 两个系统进程注入、两个设置项、五档；Foundation/libSystem/objc/substrate链由包检查约束；未新增daemon、网络请求、启动项、CC模块或App/Widget注入 |
| 维护/诊断 | 选定服务域有限重启；只读mobile诊断；失败不冒充Off、notify残留不冒充当前活性 |
| 打包/发布 | 从当前源码重编译签名；资源/脚本与受审源码对照；同一运行artifact先草稿核验后公开 |

注册阶段可能在constructor线程，而角色队列已收到回调。回调此时只读队列所属readiness并返回，不接触尚在构造的通信状态；激活通过dispatch提交建立顺序。daemon激活入队先于hook捕获任务，避免刚捕获的对象被未就绪门禁丢弃。失败路径没有把readiness从其他线程强改成NO，也未增加原子轮询。

主线程亲和性对真实私有对象仍需真机确认。初始化失败只阻止新通信，不强制清除共享状态或调用Off；此前模拟可能仍存在，必要时应通过越狱应用重启用户空间。loaded=1仅表示初始化曾进入，不表示ready或进程存活。

## 5. 功能、全部参数和档位

| PowerMode | 设置标题 | 私有参数 | 准确语义 |
|---|---|---|---|
| 0，缺省 | 关闭 | off | 请求退出模拟；方法返回不等于已经测量温控恢复 |
| 1 | 标称（仍在模拟） | nominal | 仍属于模拟，不能与Off混同 |
| 2 | 轻度 | light | 首次验收从Off→Light→Off开始，不给固定频率或续航保证 |
| 3 | 中度 | moderate | 保留用户选项，性能/帧率/温度影响须实测 |
| 4 | 重度 | heavy | 未提高默认值，不宣称适合目标设备常驻 |

| RequireLowPowerMode | 系统LPM关 | 系统LPM开 | PowerMode保存值 |
|---|---|---|---|
| 缺省/false/数值0 | 保存档位 | 保存档位 | 不修改 |
| true/数值1 | Off | 保存档位 | 不修改 |
| 非法类型/数值 | Off | Off | 不修改 |

运行时PowerMode接受0..4整数值的NSNumber（2.0可表示2），拒绝CFBoolean、字符串、容器、NSNull、负数、越界、非整数、NaN/无穷等。门控只接受NSNumber/布尔的0或1；缺档有限重读后Off。发行资源必须严格保留已审阅整数/布尔类型，运行时对手工偏好的有限容错不构成更改面板类型的理由。五档×两种LPM×两种门控已由保留核心测试检查实际发送字符串、保存值与去重，不测量真实CPU/GPU频率。

插件没有固定CPU频率、帧率、独立后台冻结功能。只保留单次off路径，不擅自加入未经目标设备确认的nil/off双重私有调用。

## 6. 固定预算、恢复和残余风险

| 项目 | 行为 |
|---|---|
| 请求/读取/发布尝试 | 初次+5次，间隔400ms，代际取消过期任务 |
| 请求超时 | 最后请求后再等待400ms，状态11后停止该轮 |
| 设置/LPM补发 | 立即、150ms、600ms；新变更取消旧刷新 |
| SpringBoard启动补发 | 立即、3/10/30/60秒，结束后不持续轮询 |
| 会话更新 | 新对象、明确设置变更、有限读失败恢复各换会话；随机一次，排除零/上一会话；32位不保证永久全局唯一 |
| 应用去重 | 当前会话有效回复可恢复诊断；相同模式不重复调用；不监控其他热控插件覆盖 |
| applied10/11 | 等待/通信失败，旧模拟可能仍在，不能解释为Off |
| applied98/99 | ObjC异常/ABI不符，当前对象熔断；不能捕获SIGBUS/SIGSEGV/watchdog |
| 诊断loaded/hook/applied | 历史快照，不能独立证明活性、实际节流或新的代码已经加载 |

旧缓存不能确认较新请求，也不能将较早Heavy应用于新Off周期。持续通知故障、偏好可见性超出有限窗口、发布端缺席和初始化关闭通信仍可能保留旧档位；不能为了宣称恢复而猜测档位或无界调用私有方法。未发现新的参数/预算调整依据，因此保持数值不变。

## 7. 适配、安装和卸载

| 维度 | 本轮证据 | 边界 |
|---|---|---|
| iPhone15,3 / iOS16.5 | SDK16.5、部署16.0、major16守卫、arm64e PAC00结构 | 无真机连接，PAC执行、类/API存在和实际线程行为待验 |
| RootHide Dopamine3.0.4 | RootHide scheme、iphoneos-arm64e、.jbroot install ID和精确依赖 | 不保证实际注入；未产出通用rootful/rootless包 |
| iOS16其他版本/设备 | control允许>=16且<17，ABI错配关闭 | 依赖区间不等于已覆盖全部机型；iOS17不运行 |
| 维护服务域 | user/foreground优先，必要时system；只对选定服务一次kickstart，失败同目标最多一次TERM | 命令接受不证明重载，仍需真实PID/加载记录 |
| 与其他热控联用 | 已知Powercuff变种冲突集合保留 | Hello CPU等不一定被识别，可能覆盖模式；没有联用安全证据 |
| App/Widget与历史崩溃 | 注入过滤无App/Widget，无全局基础类hook | 不能宣布此前SIGBUS/watchdog或第三方注入问题已修复 |

包ID保持com.minis.powercuff-baldaran-trusted；依赖mobilesubstrate>=0.9.9000、preferenceloader、firmware>=16且<17；四个冲突包不变。维护脚本只在configure/remove阶段动作，不写defaults、不自动注销、不按进程名killall、无SIGKILL。不能确认服务域或缺launchctl时跳过自动重启并提示人工处理；保留真实诊断和退出码。

安装升级后人工注销一次以替换两端代码；重启跳过/失败时通过越狱应用重启用户空间。卸载重新加载daemon以清hook，并人工注销publisher；保留偏好供重装复用。Sileo自动移除建议不代表此包缺依赖，不自动卸载其他包。

## 8. 构建、包安全和正式发布

macOS15 / Xcode16.4；固定RootHide Theos `cfba89a53a05b4a1b822121158acc3669c20602f`、iPhoneOS16.5 SDK `0222fd5413cf4b9af096f37b4621afa2688572f7`，主workflow的第三方Actions固定提交。真实工具版本记在BUILD_ENVIRONMENT.txt；Homebrew依赖和runner并非完全固定，不宣称逐字节可复现全部工具链。

先执行63项Python、C协议、shell/plist、Foundation参数/runtime、27组核心和9组constructor检查；成功后clean/package、ldid签名、归档数值UID/GID0/0与提交时间规范化，签名payload字节不变。检查Debian成员顺序/压缩、无重复/链接/额外路径/空目录、普通文件规范路径、权限、脚本执行位和精确控制字段；与源码逐项核对维护脚本、plist、图标及元数据。

Mach-O要求薄versioned arm64e PAC00（subtype0x80000002）、iOS设备平台/部署16.0、RootHide install ID及精确导入库集合。检查CodeDirectory版本布局、代码页和特殊槽覆盖/哈希，保留真实已编译DEB的代码/签名/requirements篡改、截断、零覆盖、旧ABI、脚本/图标/依赖变化、权限、压缩/成员顺序/路径异常反例；新增布尔档位与重复plist键反例。完整性不等于证书信任或设备PAC加载。

只在release/powercuff-1.3.10 push且build成功后发布同一运行artifact，版本/提交/清单核对；拒绝覆盖既有tag/Release，新tag绑定成功源码。13个附件先上传非公测草稿，核对集合、大小、digest、清单覆盖、源码提交/tag及显式stable属性，再公开并设Latest，随后复核公开属性和Latest ID。源码zip/tar.gz来自同一标签，不重新编译。

交付后独立下载artifact并核对API摘要/大小，安全解压13项；以受审验证器再核对公开Release及全部附件哈希；81路径的SOURCE_FILES.sha256与受审源码和Git tree一致；公开DEB与同一成功artifact逐字节一致，再运行完整包和实际包反例检查。真实结果见SOURCE_TESTS.txt、verification.txt及该Release追加的成功运行/源码提交/哈希，不能将本文的门禁要求视为已成功执行。

## 9. 目标设备待验收记录

| 项目 | 必须采集的证据 | 当前状态 |
|---|---|---|
| 安装/升级/卸载 | 安装版本、命令服务域、注销后两端新加载、卸载后hook移除 | 主机脚本/包检查；实机待验 |
| 初始化故障/LPM | 正常两端加载，LPM进出有效档位，保存设置不变 | 主机constructor故障注入；实机时序待验 |
| Off→Light→Off/五档 | 当前会话、private返回、最终模拟退出，必要时记录其他档 | 合成接收对象及矩阵；真实温控待验 |
| 进程重载/待机恢复 | 两端先后重载、发布端缺席、恢复后Off，唤醒后状态 | 有限状态测试；真实生命周期待验 |
| PAC/watchdog/异常 | 新版本daemon无新增崩溃，心跳、符号化日志、温控恢复 | 无新设备证据，不宣称历史故障解决 |
| 续航/帧率/联用 | 同亮度/网络/工作负载重复测量；先单独启用再逐项评估冲突 | 无测量，不给百分比、最佳档位或联用保证 |

只读诊断须mobile(uid501)运行verify-on-device.sh，无法读取偏好时有效档位未知；状态值可能残留。首次单独验收Off→Light→Off，再考虑Moderate。持续11、98/99、新增daemon崩溃或温控异常须按实际记录处理。结论限于明确列出的源码修复、主机验证、实际包和发布核验，不承诺所有未知风险已经消除。
