# Powercuff v1.3.11 全源码复核与 v1.3.12 正式发行审计

日期：2026-10-31（Asia/Shanghai）。目标：iPhone14 Pro Max / iPhone15,3、iOS16.5（20F66）、arm64e、RootHide Dopamine3.0.4。没有连接目标设备；主机测试、包结构及签名完整性不证明设备 PAC 执行、私有 API 实际效果、真实温控恢复、watchdog 或续航。

## 1. 发布基线和修订范围

重新读取 GitHub Latest、v1.3.11 Release 和 main：正式基线源码为 `dfa89980a5b2cf3f2180f83199145c6f8558360e`，85个跟踪路径；公开 DEB 18744字节，SHA-256 `9eaa6d79d17054d4a9dbc48a86777a2d1a8505dc59da9b713f16545ec5ea2a20`，非草稿、非公测、13项上传附件完整。main `9d6fd72603a641736469f793375c1aa9270bbdfe` 的树与该版本一致，新修订从此建立独立 release/powercuff-1.3.12 分支。

发现并修复归档解析与规范化的三处相关缺口。**未复现新的运行时缺陷；Powercuff.x、PCRCore.h、PCRPreferences.h、PCRProtocol.h、PCRRuntime.h 与三份维护脚本保持 v1.3.11 字节不变。** 不凭包检查推断崩溃根因，不改热档、私有方法参数、队列或重试预算。增加两组生产核心故障场景，并从本轮受审源码完整重编译新 DEB。

本版新增 AUDIT/BUILD/RELEASE 三份文档，共88个跟踪路径。历史 DEB、旧审计和1.3.4专用采集器保留；当前发布路径和当前测试的覆盖范围列于下文，历史资料不能替代本版设备证据。

## 2. 实际复现、因果与修复

| 编号 | 旧版表现与影响 | 修复及证据 |
|---|---|---|
| F1：解压层数与 dpkg 不一致，发行阻断级 | 在原签名 v1.3.11 DEB 的临时副本中，只将 control.tar 或 data.tar 的解压结果再包成 gzip/xz，保留外层正确后缀和原始文件。旧完整校验（含 source-root）四种样本全部通过；Linux dpkg-deb --info/--contents 全部退出2，报告压缩归档不能当 tar 读取 | 按成员后缀只解压一次，下一层必须以 r: 读取未压缩 tar；禁止再次自动探测压缩。所有支持的外层 gz/xz/lzma × 内层 gzip/xz × 两种归档，共12组单元反例；真实 DEB 再测4种嵌套反例 |
| F2：tar 结束后未检查字节，中等发行门禁缺口 | 旧 tarfile 成员迭代遇到结束块即停止；追加非零内容或第二份 tar 仍通过全部既有文件/源码对照，截去结束块也可被接受。dpkg 对部分尾部样本也忽略，因此此项是本项目完整归档策略的缺口，不声称隐藏文件会被安装 | 要求512字节块对齐、最后实际成员后至少两个完整零块，剩余尾部全为零；拒绝非零尾部、拼接归档、缺失/不完整结束。允许正常额外零填充；USTAR/GNU/PAX 和1/511/512/513字节内容作正例，避免误伤合法包 |
| F3：规范化会先丢弃异常尾部，中等构建证据缺口 | 旧 normalize_package.py 先用普通 tarfile 读取，再重写数值属主和时间；原包后附非零尾部会被静默忽略，之后校验看不到原始异常。旧规范化对双重压缩本身已报 ReadError，不能把这一点误报为旧版接受嵌套 | 规范化与验证共享显式解压和完整 tar 检查，在重写前拒绝异常输入；失败不替换原 DEB、不留下 .normalized 文件。数值0/0、时间统一及签名 payload 字节保持的幂等测试继续通过 |

所有实验只操作临时副本，只读调用 dpkg；未安装样本、未执行维护脚本。原始公开 v1.3.11 通过修复后的完整验证，以上发现不意味着既有公开 DEB 已损坏。四个嵌套样本的可复现拒绝原因来自压缩层/块结构，非签名、版本或源码不一致。

修复前新增归档单元检查产生12个嵌套与6个结束/尾部失败子用例；规范化错误类型另有一项不匹配。后续加入合法扩展头和文件填充正例。修复后本地主机74项 Python、C协议、shell/plist 检查通过；macOS 的 Foundation、核心和构造函数结果由 SOURCE_TESTS.txt 记录，不将未执行的目标设备验证写成通过。

规范依据：[Debian deb(5)](https://manpages.debian.org/trixie/dpkg-dev/deb.5.en.html) 描述按成员后缀压缩的 tar；[Python tarfile 文档](https://docs.python.org/3/library/tarfile.html) 区分透明压缩读取与未压缩读取，并说明默认空块即结束。完整零尾部是本项目更严格的发行策略。修复不声称实现全部 Debian 格式；本项目仍只接受已审阅的三成员与 gz/xz/lzma 配置。

## 3. 完整源码与架构逐项复核

| 文件/层 | 复核内容与结论 |
|---|---|
| Powercuff.x 入口 | 仅 SpringBoard/thermalmonitord、iOS major16；先准备必要通信，再按角色检查 LPM 观察者或 thermal 类/初始化/应用 ABI；失败不激活、不装新 hook |
| Powercuff.x hook | 使用原 initProduct: 返回对象，弱捕获；CommonProduct/GPProduct 依据实际方法所有权避免重复继承 hook；激活先入队，再安装 hook，避免初始化期捕获早于 readiness |
| PCRCore.h 队列 | daemon 主队列、publisher 独立串行队列；状态在角色队列内修改；已提前排队或取消后抵达的回调由 readiness 门禁阻断。实际私有对象线程亲和性待设备确认 |
| PCRCore.h 对象 | 弱引用不保活对象，调用期间局部强引用；新对象取消旧 apply/request 代际，清理旧对象缓存与熔断；先检查实际返回对象 ABI 再开始会话，真正调用前再次检查 |
| PCRCore.h 发布 | SpringBoard 读取 mobile 指定持久域快照和当前 LPM；重试/补发重新读取当前值；set_state/post任一失败均使发布缓存失效，后续 Off 能修正只写未发的 Heavy 字段 |
| PCRCore.h 应用 | 当前会话0..4解码、同档私有调用去重；设置编辑和传输恢复更换会话，旧回复不能确认新请求；ObjC异常98、ABI不符99后当前对象熔断 |
| PCRCore.h 恢复 | 六次有限请求/发布/读尝试；读失败最多追加一轮新会话恢复；无无限恢复环。新设置事件可明确重启一轮，失效回复/超时不能自行反复解锁 |
| PCRPreferences.h | NSNumber 非布尔、有限整数值0..4；门控0/1或布尔；非法输入Off、缺值有限重读；不读跨域 fallback，不写偏好 |
| PCRProtocol.h | v2高24位0x504302、非零32位会话、低字节模式0..4或请求0xA5；拒绝旧会话/裸数字/坏头。会话用于新鲜度协调，不是认证 |
| PCRRuntime.h | 检查实例方法3参数、self/cmd及对象/void ABI；拒绝 block @?、标量、错误返回；方法列表判断所有权，不以相同IMP推断继承 |
| 注入/设置 plist、三图标 | 两进程精确过滤；两个键、五个整数档位、布尔门控默认及中文标题对应；拒绝重复键、类型替换和多余设置项；图标字节对照 |
| Makefile/control | iOS16.5 SDK、部署16.0、arm64e、RootHide、ARC、Foundation；保留包ID、精确四依赖与四冲突，版本1.3.12；不扩展到其他越狱包格式 |
| build.sh | clean→package/签名→规范化→源码对照→真实包变异；验证失败退出。源码ZIP无git需 SOURCE_DATE_EPOCH；不将旧dylib重新封装为新源码构建 |
| normalize_package.py | 本轮在转换前检查单层解压、完整tar；原签名payload不改、数值属主0/0、时间来源提交；失败保留输入，合法包幂等 |
| verify_package.py | 本轮修复解压/归档边界；保留ar顺序、路径/类型/权限白名单、单段control、依赖/冲突、Mach-O、签名和源码静态资源对照；带/不带源码均执行结构策略 |
| macho_signature.py | CodeDirectory版本布局、代码页/requirements特殊槽覆盖和哈希、索引/区间及无额外entitlement；拒绝-O。完整性不证明证书信任、PAC或注入成功 |
| verify_release.py | 独立强制13项当前版本附件契约；源码提交/tag/版本、草稿或公开、非公测、大小/digest及清单全覆盖；集合自洽不能替代必备文件 |
| test_built_package.py | 在当次真实签名DEB上测试24种完整包变异（新增8种tar问题），要求正确拒绝原因；另有7组签名破坏和5次无源码反例检查 |
| prepare_startup_test.py/check.sh | 从实际 %ctor 提取分支，替换hook安装操作；不模拟一份独立生产实现。先 Python/C/shell/plist，macOS 再编译 Foundation 偏好/runtime、29组核心和9组构造函数 |
| postinst/prerm/postrm | 按动作选择服务，先探测foreground，再按需system；一次kickstart失败才对同目标一次TERM；不写root偏好、不killall、不SIGKILL、不自动注销；命令成功不等于重载确认 |
| verify-on-device.sh | mobile uid501只读采集；偏好读失败显示有效档位未知；loaded/hook/applied可能残留，不作为当前进程活性或实际节流证明 |
| build.yml | 固定Node24 Actions、Theos/SDK，macOS15/Xcode16.4构建；仅当前release分支push使用同运行artifact，草稿核对后公开；不覆盖旧tag/Release |
| 其余跟踪路径 | 旧报告、历史DEB、1.3.4采集器及哈希、测试和忽略配置列入完整88路径来源清单；历史工具仅按现存回归检查，不用于1.3.12设备放行 |

新增核心场景分别覆盖永久发布 set/post 失败的有限结束及后续 Off 修正、握手中对象已释放后停止请求与新对象重新取得 Off。这些执行生产 PCRCore.h，使用虚拟时钟/通知/接收者；不调用真实系统温控对象。

## 4. 功能、参数与全部档位

| PowerMode | 中文标题 | 私有参数 | 行为与边界 |
|---|---|---|---|
| 0（默认） | 关闭 | off | 请求退出模拟；不绕过真实过热保护。接口返回仍需确认真实温控恢复 |
| 1 | 标称（仍在模拟） | nominal | 保留模拟，不能作为 Off 使用 |
| 2 | 轻度 | light | 首次单独验证 Off→Light→Off；没有固定 CPU/GPU 频率承诺 |
| 3 | 中度 | moderate | 保留可选项，不认定为 iPhone15,3 最佳常驻值 |
| 4 | 重度 | heavy | 保留选项，不提升默认热压力；性能、帧率及续航须实际比较 |

| RequireLowPowerMode | 系统LPM关闭 | 系统LPM开启 | 保存值 |
|---|---|---|---|
| 缺省/false/数值0 | 请求所选档位 | 请求所选档位 | 不改写 PowerMode |
| true/数值1 | 请求 Off | 请求所选档位 | 不改写 PowerMode |
| 非法类型/数值 | 请求 Off | 请求 Off | 不改写 PowerMode |

模式接受0..4的整数值 NSNumber（2.0可表示2），拒绝 bool、字符串、容器、NSNull、负数、越界、非整数、NaN/无穷等。门控仅0/1或布尔；不存在的 PowerMode 在有限重读后使用 Off。默认Off不等于升级/重装时清除已有偏好：安装、卸载保留保存值。

五档 × 两种LPM × 两种门控、同档去重、Off回切和异常值由现有参数/核心检查覆盖。此插件没有独立控制中心模块、后台冻结、固定CPU频率或帧率控制功能；不写入1428MHz等设备频率参数。

## 5. 稳定性、通信预算与诊断

| 路径 | 固定预算/行为 | 限制 |
|---|---|---|
| 请求/发布/读取 | 初次+5次，400ms间隔，旧代际失效 | 全部失败后停止；不是持续轮询 |
| 请求超时 | 最后请求后再400ms报告11 | 旧模拟可能仍在，不自动声称已Off |
| 设置/LPM重发 | 立即/150/600ms，读取当前值 | 新变更取消旧重发；整个窗口失联仍不能保证恢复 |
| 启动重发 | 立即/3/10/30/60秒 | 60秒后无后台定时轮询 |
| 会话更新 | 新对象、明确设置编辑、一次读失败恢复 | 排除零和紧邻上次随机值，不承诺永久全局唯一 |
| applied 0..4 | 私有方法已返回对应参数 | 不证明真实节流、频率、续航或热状态 |
| applied 10/11 | 等待/超时或状态读取耗尽 | 旧模式可能保持；通知值也可能残留 |
| applied 98/99 | ObjC异常/ABI不符，当前对象停止调用 | 不能捕捉SIGBUS、SIGSEGV或watchdog；新对象再检查 |
| 外部热控联用 | 包冲突只覆盖列出的Powercuff变种 | Hello CPU/HelloMemoryStatus和其他策略可能干扰，未获联用安全证据 |

没有复现或宣称修复目标设备历史 SIGBUS/watchdog；单靠异常捕获、静态 ABI 和 ad-hoc 签名不能证明私有接口安全。偏好可见性超出有限窗口、两端未重载、通知/进程整体失效等情况仍需真实日志与人工恢复。

## 6. 适配、安装与维护

| 项目 | 校验/支持边界 |
|---|---|
| 构建目标 | iOS16.5 SDK，iOS16.0最低部署，构造函数要求major16；control限制16.x；其他iOS版本不支持 |
| 架构 | iphoneos-arm64e，薄Mach-O subtype0x80000002（PAC00）；结构通过不证明目标机PAC运行 |
| 越狱环境 | RootHide scheme与.jbroot加载路径；不作为通用rootful或普通rootless包 |
| 依赖 | mobilesubstrate >=0.9.9000、preferenceloader、firmware >=16.0且<17.0；精确集合无额外/重复 |
| 注入和资源 | 仅SpringBoard/thermalmonitord；四控制文件、六payload文件及必要父目录，数值属主0/0，限定权限 |
| 安装/升级 | Sileo安装新包后人工注销一次，使两进程加载匹配源码；服务探测或重启命令成功不证明完成重载 |
| 无服务/命令失败 | 保留诊断；通过越狱应用人工重启用户空间并确认daemon日志，不盲目扩大信号范围 |
| 卸载/重装 | 卸载后daemon重载及人工注销，保存偏好仍在；重装沿用偏好 |
| 目标环境 | iPhone15,3/iOS16.5/RootHide Dopamine3.0.4；Procursus/bindfs等实际运行适配、待机与watchdog仍待目标机确认 |

## 7. 构建、包和正式发布门禁

基线70项 Python、27组核心、9组构造函数。当前要求74项 Python、29组核心、9组构造函数，加 Foundation 偏好/runtime、C协议、shell/plist 和实际 DEB 反例。真实签名反例7组，完整DEB变异16→24种；新8种覆盖两归档的双重gzip/xz、非零尾部及缺失EOF，逐一校验拒绝原因。

GitHub 使用固定 RootHide Theos `cfba89a53a05b4a1b822121158acc3669c20602f`、SDK `0222fd5413cf4b9af096f37b4621afa2688572f7`；Actions固定Node24提交，macOS15/Xcode16.4，Ubuntu24.04发布。实际编译器/Python/Homebrew版本见 BUILD_ENVIRONMENT.txt；runner和系统包不是完整锁定，不承诺不同构建的Mach-O逐字节相同。

仅 release/powercuff-1.3.12 的push在全部测试、clean编译/链接/签名、规范化和包校验成功后，下载同运行artifact，创建新tag/草稿；核对13项附件的源码、版本、集合、大小与全部SHA-256后正式公开、设置Latest，再复核。旧tag/发行不覆盖。SOURCE_COMMIT和88项SOURCE_FILES.sha256标识实际来源，SOURCE_TESTS.txt/verification.txt记录实际执行；Release正文追加实际运行与哈希，不在本说明预填尚未发生的成功。

独立交付复核artifact ZIP大小/摘要与安全成员；核对完整源码路径/字节、当前文档/验证器、工具链引用、测试与变异输出；运行公开发行校验，重新下载公开DEB并与artifact逐字节比较，再执行包检查和实际变异。PR与主分支另行通过构建后同步当前源码。

## 8. 目标真机逐项验收（未执行）

1. 保存可回退旧包与用户偏好；首次单独验证，暂时停用其他热控修改，安装本次Release唯一DEB并核对哈希。
2. 人工注销一次；确认SpringBoard/thermalmonitord均已重载。以mobile运行verify-on-device.sh并结合新进程日志；残留loaded=1不足以确认注入。
3. 验证Off→Light→Off，再按需验证Nominal/Moderate/Heavy，记录设置值、接口返回、新崩溃与实际温控/性能；Nominal不能代替Off。
4. 对保存档位分别测试门控关闭/开启、LPM进入/退出，保存PowerMode应不被改写，退出LPM应实际恢复Off；状态10/11必须按未知/可能残留处理。
5. 单独重启SpringBoard与daemon、待机/唤醒、快速切回Off；确认有限恢复结束及当前会话生效。离线/持续通信失败时不要把旧档位当成已清除。
6. 对比同条件温度、帧率、CPU及耗电；至少观察完整待机/使用周期，检查thermalmonitord/SpringBoard新SIGBUS/watchdog。出现新崩溃先恢复Off/卸载并确认进程重载，采集真实报告后再定根因。
7. 验证升级/卸载/重装后的资源、偏好保留与实际卸载；当前GitHub正式发布属性不等于这些项目已获设备验收。
