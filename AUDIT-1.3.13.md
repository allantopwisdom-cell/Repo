# Powercuff v1.3.12 全源码复核与 v1.3.13 正式发行审计

日期：2026-10-31（Asia/Shanghai）。目标：iPhone14 Pro Max / iPhone15,3、iOS16.5（20F66）、arm64e、RootHide Dopamine3.0.4。没有连接目标设备；主机和包检查不证明设备 PAC、私有 API 实际效果、温控恢复、watchdog 或续航。

## 1. 发布基线和修订范围

重新读取 GitHub Latest 与 main：正式 v1.3.12 源码 `eb4f83a3a3b7f6af30eadb90709d4bb05b70c03d`，88项跟踪路径；公开 DEB 18748字节，SHA-256 `7a484f3a279d4272089cd8e26de59fae5990f1fc03b6a15730229c33f12f3613`，非草稿、非公测、13项附件完整。main `52ed33a58ee850711fc642e7a3bcfb85abc0af8e` 与该标签具有相同树 `fd84d1c0b154629aa5f8cabe68001aa325a5052c`。本地修订基于发布标签；GitHub release/powercuff-1.3.13 从相同内容的main建立。

本轮复核五份生产源码、全部设置/档位、通信/对象/适配、防护与构建发行链，修复可复现的 ar 物理字段校验缺口。**没有复现新的运行时缺陷；Powercuff.x、PCRCore.h、PCRPreferences.h、PCRProtocol.h、PCRRuntime.h 和三份维护脚本与 v1.3.12 字节一致。** 不因新版本号而调整热压力、私有调用、队列或重试预算。

新增当前 AUDIT/BUILD/RELEASE 三份文档，共91项跟踪路径；所有文件进入来源清单。历史报告、旧DEB和1.3.4工具保留，不能替代本版设备证据。新DEB从受审源码clean全量编译，旧标签/发行不覆盖。

## 2. 已复现问题、修复与因果边界

| 编号 | v1.3.12表现与影响 | 精确修复与验证 |
|---|---|---|
| F1：ar大小字段不符合dpkg解析，发行阻断级 | 旧版直接int()，接受+4、0_4、前置Tab、后置Tab。仅改原签名DEB第一个成员头的10字节大小字段，四个临时副本的完整检查（含源码对照）全部通过，Linux dpkg-deb --info全部退出2，分别报告非法+、_或Tab | 转换前只接受ASCII数字及Space填充，保留合法前后Space和补零；拒绝符号、下划线、Tab/CR/LF/VT/FF、内部空白和空字段；四种真实DEB变异每次构建执行 |
| F2：ar名称被过度规范化，发行阻断级 | 旧.decode().strip().rstrip('/')会接受debian-binary//、前置Space、前置Tab、后置Tab、Unicode NBSP前缀；五个完整DEB副本均通过旧检查，但dpkg退出2且不识别为Debian包 | 仅移除Space尾填充；项目名称使用1..15个ASCII字母/数字/点/下划线/连字符，允许一个可选结尾斜杠；原始名称先匹配再去该斜杠，不修改非法输入的含义。五种真实DEB变异每次构建执行；NUL名称也按正确字段原因拒绝 |
| F3：规范化可能掩盖原始ar错误，中等构建门禁缺口 | normalize_package通过旧ar_members读取，再生成标准头；上述非法字段可先被改写，后续校验看不到原始问题 | 共享严格ar_members入口，规范化在改写前即失败；全部9种真实ar变异分别检查校验（含/不含源码）及规范化，确认原包字节不变且不留下.normalized文件 |

反例仅修改临时副本的ar头；未修改/安装原包，未执行维护脚本，Mach-O和tar payload不变。原公开v1.3.12仍通过修复后的全部检查，不意味着既有包已损坏。+4问题来自前次未完成的本地修订，本轮继续补齐名称与真实包路径；此前75项本地结果不被写成已完成发行。

另有三项正例：无结尾斜杠、大小前置Space、大小补零，旧检查与dpkg均接受，新检查继续允许。六组合单元正例覆盖两种合法名称和三种大小填充。名称额外NUL虽旧检查已在后面失败，新检查直接报告名称字段错误；不将其计入旧完整检查通过的9种样本。

第一阶段大小修复后，新增名称/规范化检查仍产生7个失败子用例（含NUL拒绝原因不匹配），证明仅限制大小不足；完整修复后本地78项 Python、C/shell/plist通过。新macOS参数/核心/启动、clean编译及真实包结果以当次 SOURCE_TESTS.txt/verification.txt 为准，不预写尚未发生的成功。

格式依据：[Debian deb(5)](https://manpages.debian.org/bookworm/dpkg-dev/deb.5.en.html) 指定common ar、可选单个结尾斜杠及10位ASCII十进制大小。本项目校验器是当前包的严格门禁，不是通用ar/所有Debian格式实现。新增限制不改设备侧执行代码。

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
| Makefile/control | iOS16.5 SDK、部署16.0、arm64e、RootHide、ARC、Foundation；保留包ID、精确四依赖与四冲突，版本1.3.13；不扩展到其他越狱包格式 |
| build.sh | clean→package/签名→规范化→源码对照→真实包变异；验证失败退出。源码ZIP无git需 SOURCE_DATE_EPOCH；不将旧dylib重新封装为新源码构建 |
| normalize_package.py | 继续检查单层解压、完整tar；本轮共享严格ar字段入口；原签名payload不改、数值属主0/0、时间来源提交；失败保留输入，合法包幂等 |
| verify_package.py | 本轮修复ar大小/名称字段解析；保留单层解压及完整tar边界；保留ar顺序、路径/类型/权限白名单、单段control、依赖/冲突、Mach-O、签名和源码静态资源对照；带/不带源码均执行结构策略 |
| macho_signature.py | CodeDirectory版本布局、代码页/requirements特殊槽覆盖和哈希、索引/区间及无额外entitlement；拒绝-O。完整性不证明证书信任、PAC或注入成功 |
| verify_release.py | 独立强制13项当前版本附件契约；源码提交/tag/版本、草稿或公开、非公测、大小/digest及清单全覆盖；集合自洽不能替代必备文件 |
| test_built_package.py | 在当次真实签名DEB上测试33种完整包变异（新增9种ar字段问题），要求正确拒绝原因；另有7组签名破坏和14次无源码反例检查，并对9种ar变异确认规范化失败且不改原包 |
| prepare_startup_test.py/check.sh | 从实际 %ctor 提取分支，替换hook安装操作；不模拟一份独立生产实现。先 Python/C/shell/plist，macOS 再编译 Foundation 偏好/runtime、30组核心和9组构造函数 |
| postinst/prerm/postrm | 按动作选择服务，先探测foreground，再按需system；一次kickstart失败才对同目标一次TERM；不写root偏好、不killall、不SIGKILL、不自动注销；命令成功不等于重载确认 |
| verify-on-device.sh | mobile uid501只读采集；偏好读失败显示有效档位未知；loaded/hook/applied可能残留，不作为当前进程活性或实际节流证明 |
| build.yml | 固定Node24 Actions、Theos/SDK，macOS15/Xcode16.4构建；仅当前release分支push使用同运行artifact，草稿核对后公开；不覆盖旧tag/Release |
| 其余跟踪路径 | 旧报告、历史DEB、1.3.4采集器及哈希、测试和忽略配置列入完整91路径来源清单；历史工具仅按现存回归检查，不用于1.3.13设备放行 |

新增核心场景使11种异常模式与8种异常门控经真实 PCRCore.h 的发布、当前会话传输和接收路径到达 Off，并确认原偏好不被改写；修正为合法设置和切换 LPM 后可恢复 Light/Heavy。它使用虚拟时钟、内存通知与合成对象，不调用真实温控对象。已有永久传输失败、弱对象释放、延迟回复和有限恢复检查继续执行。

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

基线74项 Python、29组核心、9组构造函数。当前要求78项 Python、30组核心、9组构造函数，加 Foundation 偏好/runtime、C协议、shell/plist 和实际 DEB 反例。保留7组签名破坏检查，完整DEB变异24→33种；新增9种ar变异均以字段错误拒绝，并分别验证无源码检查与规范化不改输入（独立检查合计14次，ar规范化9次）。

GitHub 使用固定 RootHide Theos `cfba89a53a05b4a1b822121158acc3669c20602f`、SDK `0222fd5413cf4b9af096f37b4621afa2688572f7`；Actions固定Node24提交，macOS15/Xcode16.4，Ubuntu24.04发布。实际编译器/Python/Homebrew版本见 BUILD_ENVIRONMENT.txt；runner和系统包不是完整锁定，不承诺不同构建的Mach-O逐字节相同。

仅 release/powercuff-1.3.13 的push在全部测试、clean编译/链接/签名、规范化和包校验成功后，下载同运行artifact，创建新tag/草稿；核对13项附件的源码、版本、集合、大小与全部SHA-256后正式公开、设置Latest，再复核。旧tag/发行不覆盖。SOURCE_COMMIT和91项SOURCE_FILES.sha256标识实际来源，SOURCE_TESTS.txt/verification.txt记录实际执行；Release正文追加实际运行与哈希，不在本说明预填尚未发生的成功。

独立交付复核artifact ZIP大小/摘要与安全成员；核对完整源码路径/字节、当前文档/验证器、工具链引用、测试与变异输出；运行公开发行校验，重新下载公开DEB并与artifact逐字节比较，再执行包检查和实际变异。PR与主分支另行通过构建后同步当前源码。

## 8. 目标真机逐项验收（未执行）

1. 保存可回退旧包与用户偏好；首次单独验证，暂时停用其他热控修改，安装本次Release唯一DEB并核对哈希。
2. 人工注销一次；确认SpringBoard/thermalmonitord均已重载。以mobile运行verify-on-device.sh并结合新进程日志；残留loaded=1不足以确认注入。
3. 验证Off→Light→Off，再按需验证Nominal/Moderate/Heavy，记录设置值、接口返回、新崩溃与实际温控/性能；Nominal不能代替Off。
4. 对保存档位分别测试门控关闭/开启、LPM进入/退出，保存PowerMode应不被改写，退出LPM应实际恢复Off；状态10/11必须按未知/可能残留处理。
5. 单独重启SpringBoard与daemon、待机/唤醒、快速切回Off；确认有限恢复结束及当前会话生效。离线/持续通信失败时不要把旧档位当成已清除。
6. 对比同条件温度、帧率、CPU及耗电；至少观察完整待机/使用周期，检查thermalmonitord/SpringBoard新SIGBUS/watchdog。出现新崩溃先恢复Off/卸载并确认进程重载，采集真实报告后再定根因。
7. 验证升级/卸载/重装后的资源、偏好保留与实际卸载；当前GitHub正式发布属性不等于这些项目已获设备验收。
