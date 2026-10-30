# Powercuff v1.3.8 全项目复审及 v1.3.9 正式发布审计

日期：2026-10-31（Asia/Shanghai）。目标设备：iPhone 14 Pro Max（iPhone15,3）、iOS 16.5（20F66）、arm64e、RootHide Dopamine 3.0.4。按用户要求发布非 Pre-release 的正式 GitHub Release；正式发布属性不等于目标真机已经完成验证。当前没有连接目标设备，不将主机回归、签名完整性或命令成功冒充 PAC、温控、watchdog 或续航实测。

## 1. 基线、范围与可追溯证据

- 已发布 v1.3.8：`af02c532fdf9c41f4fa0bee19344c242aaa9f81e`，72 个跟踪路径。公开 DEB 为 18228 字节，SHA-256 `7e0a139b306bd2ae7a9d676b1d49e4aa6b99b83e53b370d526ae407d116527d7`。重新读取 GitHub Release 元数据与本地已核验源码，保持旧包、旧标签和其他工作区不变。
- 新分支 release/powercuff-1.3.9 从该提交建立。新版本号 1.3.9；包 ID、架构、依赖、档位默认值和维护脚本不变。
- 当前生产代码 Powercuff.x、PCRCore.h、PCRPreferences.h、PCRProtocol.h、PCRRuntime.h 全部复读；复核两个 plist、三个图标的来源、Makefile/control/build.sh、三份维护脚本、诊断工具、全部当前验证器、测试和 workflow。
- 根目录 14 个 1.1.x/1.2.x DEB、旧 AUDIT/BUILD/RELEASE 文档及 1.3.4 专用采集器属于历史资料，不作为本版二进制或设备验收依据。源清单保留它们，交付包只来自本次构建。
- 新增本版 AUDIT/BUILD/RELEASE 三份文件，预计总计 75 个跟踪路径。最终精确集合、内容和执行位由 GitHub tree、SOURCE_FILES.sha256、SOURCE_COMMIT、成功运行 head_sha 及新标签共同核对。

## 2. 本轮发现、影响与修复

| 编号 | 证据与性质 | 影响 | 修复 |
|---|---|---|---|
| F1 | 已在 macOS 上复现的请求新鲜度缺陷 | 设置编辑或读失败恢复沿用对象会话；迟到通知读取到旧缓存，可取消新请求并继续显示旧档位成功，掩盖本轮通信失败 | 设置请求和读失败恢复均更新会话；代际取消旧读取；旧缓存不再确认新周期 |
| F2 | 与 F1 同一根因的过期档位风险，新增专门回归 | 较早设置的 Heavy 回复可能在较新的 Off 请求后被接受 | 新 Off 请求使用新会话，只接受其回复；同档 private API 调用仍去重 |
| F3 | 有界性/碰撞加固，不声称设备发生过随机数异常 | 旧捕获逻辑用循环排除零，未排除上一会话随机碰撞 | 每次只取一次随机数，零或与上一会话相同则使用非零后继；UINT32_MAX 回绕为 1 |
| F4 | 诊断文字歧义 | defaults 读取失败可能被误解为当前已 Off，实际可能缺失、不可读或仍有旧模拟 | 明确报告有效档位未知；继续说明首次安装默认 Off，两者分开 |
| F5 | 正式发布适配项 | 原验证器强制 prerelease=True，不能可靠验证正式版；只改标题会造成流程与属性矛盾 | 验证器强制显式选择 --stable/--prerelease；草稿/公开两阶段核对类型；正式发布后核对 Latest |

不以增加轮询、加大热压力、反复调用私有方法或广泛重启进程来掩盖 F1。没有改动默认档位、门控语义、热字符串或 400ms 重试预算。

## 3. 基线失败与修复的因果验证

[基线运行 41040992053](https://github.com/allantopwisdom-cell/Repo/actions/runs/41040992053)，提交 `8535e48d2c8ad78bbfb05a75e5ddeb81d4ac3055`。GitHub compare 证明相对 v1.3.8 只修改 tests/test_core.m，增加 14 行，生产代码未动。

macOS15/Xcode16.4 上 54 项 Python、C 协议、plist、Foundation 参数/runtime 检查通过；新增场景在 test_core.m:209 的 `RequestPosts - editRequests == 6 && PCRAwaitingReply && Status() == 11` 断言失败，Abort trap 退出134，构建和发布跳过。故障并非编译环境异常。

场景执行真实 PCRCore.h：先成功应用 Moderate；随后用户请求 Off，但发布端暂时不回应；迟到通知触发读取旧 Moderate 缓存。旧代码将其当作新编辑的有效回复，提前取消请求。新代码要求新周期会话：继续最多六次请求，失败显示11并停止；发布端恢复后的当前 Off 回复可正常恢复。测试没有将旧模式仍在生效误判为已 Off。

修复后的新增回归还覆盖：读失败恢复被旧缓存打断、Heavy→Off 的过期回复、零/重复/最大会话候选、五档×两种 LPM 状态×两种门控及同档去重。保留原有22组，形成27组生产核心场景；不放宽 Drain 任务上限、虚拟时钟单调性或旧断言。最终通过证明来自本次 SOURCE_TESTS.txt 与成功 job 日志。

## 4. 源码、功能与架构逐层复核

| 层/文件 | 职责、生命周期与检查结果 |
|---|---|
| Powercuff.x | 仅 SpringBoard/thermalmonitord 且 iOS major16；初始化通知与两个角色队列，按运行时 ABI/方法所有权决定 CommonProduct/GPProduct initializer hook，观察系统 LPM |
| PCRCore.h：对象 | initializer 返回对象弱捕获，主队列解引用；对象消失则不保持；替换对象使旧 apply/request generation 失效；实际对象通信前和调用前均校验 ABI |
| PCRCore.h：消费者 | 当前会话解码、私有调用去重、Objective-C 异常/ABI 熔断、有限读取/请求恢复；本轮将请求周期与旧回复隔离 |
| PCRCore.h：发布者 | SpringBoard 专属串行队列；每次从指定持久域取一份快照并读取当前 LPM；发布与设置补发都读取当前值，不在延迟任务中保存旧档位 |
| PCRPreferences.h | NSNumber 类型、非布尔模式、有限整数0..4、门控0/1；拒绝跨域 fallback；异常值回退 Off |
| PCRProtocol.h | v2 头、非零32位会话、模式/请求低字节；旧会话、裸数字、坏头、保留值拒绝；格式不变 |
| PCRRuntime.h | 3个参数、self/cmd、对象参数与正确返回值；拒绝 block/标量/错误返回；按方法真正所属类判定继承 hook，不能用相同 IMP 假定继承 |
| 设置/过滤/图标 | PreferenceLoader 两个设置键和五个选项；只注入两个系统进程；资源与源码对照。没有独立控制中心模块 |
| 构建与包工具 | 从源码编译、链接、ldid 签名，归档数值属主/时间规范化，实际 payload 与来源检查；没有替换旧 dylib 冒充源码重编译 |
| 维护/诊断 | 按已确认服务域有限重启；当前诊断只读、限 mobile、失败不冒充有效 Off；历史1.3.4工具不适用于本版 |
| workflow/发行校验 | 回归先于打包，固定工具链；仅最终 release 分支通过后发布同一运行产物；所有附件先草稿核对再公开 |

两个角色运行于不同进程，内存中的状态不跨进程共享。daemon 的对象缓存/状态只在主队列访问；发布者事件汇入串行队列。私有对象主线程亲和性仍需目标设备验证，合成 NSObject 接收对象不能证明系统对象线程语义。没有增加 daemon、网络请求、启动项、应用注入或全局 NSString hook。

## 5. 全部用户参数与每个档位

| PowerMode | 显示标题 | 调用参数 | 源码行为与验证边界 |
|---|---|---|---|
| 0，默认 | 关闭 | off | 请求退出模拟；一次调用去重；方法返回不等于物理温控已确认恢复 |
| 1 | 标称（仍在模拟） | nominal | 仍在模拟，不能作为退出模拟选项 |
| 2 | 轻度 | light | 首次功能验证用 Off→Light→Off；不承诺固定频率或耗电比例 |
| 3 | 中度 | moderate | 保留用户可选项；本设备流畅度/温控/续航仍需测量 |
| 4 | 重度 | heavy | 保留选项；没有自动提高到该档，也不宣称适合本机常驻 |

RequireLowPowerMode 缺省/false/数值0：按保存档位；true/数值1：LPM关时有效Off、LPM开时有效保存档位。门控不改写 PowerMode。默认 Off 与默认门控关闭只是缺省行为；卸载保留偏好，升级/重装不会偷偷把已保存的档位改为 Off。

PowerMode 只接受0..4的整数 NSNumber，2.0可表示2；布尔、字符串、数组/字典、NSNull、负数、5以上、非整数、NaN/无穷、ULLONG_MAX 等无效值回退 Off。缺少档位有限重读后用 Off。门控只接受布尔或数值0/1；其他类型、分数或非有限数回退 Off。测试验证数值边界、独立持久域和一份快照的连贯性。

生产核心新增全组合检查真实发送的五个字符串和门控后的有效模式、保存值不变、重复发布不多次调用以及最终Off。此验证不测量五档实际 CPU/GPU 时钟、温度或帧率。

与[上游固定提交 Powercuff.x](https://github.com/Baldaran/Powercuff-r3vamp/blob/eb770afc4f403936ae9eb3b60669fa314fbcebb3/Powercuff.x)对照，五个字符串一致。上游 Off 路径还先发送 nil；该私有语义未经目标设备确认，本版继续采用已审阅的单次 off，不把未经验证的双重调用重新加进关键服务。

## 6. 请求新鲜度、取消与失败边界

| 触发/结果 | 本版处理 |
|---|---|
| 新 product | 取消旧任务、重置每对象缓存/熔断、预检实际 ABI；成功才建立新会话与请求，失败立即99且0新请求 |
| 明确设置事件且对象可用 | 使旧读取无效、等待诊断10、更新会话、启动一轮请求；之前私有模式可能仍在，10不等于Off |
| 读取耗尽 | 状态11并最多启动一轮带新会话的恢复；锁存不因自身无效回复或超时而重新开启 |
| 迟到旧周期回复 | 会话不匹配，不能应用也不能清除等待/取消新请求 |
| 当前周期有效回复 | 取消请求重发、清等待/恢复锁存；同模式不重复调用，必要时恢复诊断 |
| 请求失败/无发布端 | 每轮初次+5次，400ms间隔；最后再等400ms后11，不进入无限轮询 |
| ABI不符 / ObjC异常 | 当前对象99/98并停止私有调用；设置补发不能绕过熔断，新对象才重新验证 |

会话每轮最多取一次随机数，排除零和紧邻的上一会话；不保证32位空间永久全局唯一，也不提供身份认证。协议编码不变，但两端运行代码仍必须升级并注销替换。新会话不能保证 cfprefsd 已在该瞬间反映最新编辑；原有有限重读/重发仍保留。

| 固定参数 | 值 |
|---|---|
| 模式、协议头 | 0..4；v2高24位0x504302，32位会话，低字节模式或请求0xA5 |
| 请求/发布/读取重试 | 各自初次+5次，400ms间隔；代际取消旧任务 |
| 设置/LPM有限补发 | 立即、150ms、600ms；新变更取消旧 refresh 补发 |
| SpringBoard启动补发 | 立即、3、10、30、60秒；结束后不持续轮询 |
| 请求超时 | 最后请求后再等待400ms；报告11并停止该轮 |
| 异常状态 | 10等待、11通信失败且旧档位可能仍在、98 ObjC异常、99 ABI不兼容 |

保留 state 写入成功但 post 失败时使发布缓存失效的处理，返回 Off 可修复共享值。持续通知故障、全部消息丢失、发布端缺席或偏好可见性超过有限窗口，仍可能保留旧档位；新实现能避免旧缓存掩盖本轮失败，不能保证不可用发布端也执行 Off。没有为假定恢复而直接调用未知私有对象。

## 7. 目标平台与适配性

| 维度 | 已验证/保留 | 未验证/限制 |
|---|---|---|
| iPhone15,3 / 16.5(20F66) | SDK16.5、部署16.0、iOS16进程守卫 | 无目标机连接，真实类/API/线程/PAC仍待实机 |
| RootHide Dopamine3.0.4 | RootHide Theos、iphoneos-arm64e、.jbroot install ID及 substrate 依赖路径 | 主机Mach-O检查不证明该设备实际注入或加载 |
| iOS16其他版本/机型 | control允许>=16且<17；ABI异常停止hook/调用 | 不宣称其他设备已支持，依赖区间不是设备覆盖证明 |
| 原生rootless/rootful | 没有输出该变体 | 本交付只面向 RootHide，不作为通用包安装 |
| 服务域 | 前台域优先，按需system，选中目标一次kickstart；失败同目标最多一次TERM | 查询/退出0不证明新PID或新代码加载，真实reload需日志确认 |
| App/Widget | 注入过滤不包含它们，无全局基础类hook | 不能据此宣布其他注入链造成的历史Widget/daemon崩溃已经解决 |
| Hello CPU等热控 | 不硬锁1428MHz，不新增调度/冻结策略 | 其他插件可覆盖热模拟，同档缓存不能识别外部改动；不宣称联用安全 |

核对[RootHide开发者说明](https://github.com/roothide/Developer)：简单 tweak 使用 roothide scheme；访问越狱文件才需要对应路径 API。本插件不自行遍历越狱根路径读取偏好，而由 SpringBoard 读取明确持久域。包的实际链接路径仍通过验证器检查，不根据名称推断适配。

## 8. 安装、升级与卸载

维护脚本沿用1.3.8的已限定服务域实现：configure/remove 之外不执行动作；前台域可查则不试system；无法解析域或缺launchctl不发送全局信号；失败只向原目标发一次TERM，保留真实错误码。没有 SIGKILL、自动注销、defaults 写入或按进程名 killall。

安装升级后人工注销一次；若日志提示自动重启跳过/失败，通过越狱应用重启用户空间。须核对实际安装版本及两个进程新加载日志，残留 loaded/hook 标志不是活性证明。卸载保留偏好，按域尝试重新加载daemon，然后人工注销以移除publisher。

包ID com.minis.powercuff-baldaran-trusted；依赖 mobilesubstrate>=0.9.9000、preferenceloader、firmware>=16.0且<17.0；冲突包集合不变。没有新增CFPreferences依赖、CC模块、libcspreferences或后台服务。Sileo提示某依赖可自动移除不等于安装本插件缺失依赖，不代用户清理其他包。

## 9. 构建、签名、归档与正式发布

保留 macOS15/Xcode16.4，固定 RootHide Theos `cfba89a53a05b4a1b822121158acc3669c20602f`、SDK `0222fd5413cf4b9af096f37b4621afa2688572f7` 与第三方 Action 提交。先执行全部源码检查，再 clean/package、规范化数值0/0属主与提交时间，不修改已签名payload字节。

验证 Debian ar 成员顺序/压缩、路径及必要父目录白名单、文件类型、无重复/链接/额外空目录、权限和脚本执行位；控制元数据、静态plist、图标及脚本与本次源码逐项对照。Mach-O要求薄 versioned arm64e PAC00（subtype0x80000002）、iOS设备平台/16.0部署、精确导入库集合和RootHide install ID。CodeDirectory版本、布局、代码页与requirements特殊槽的覆盖/哈希均检查。

保留实际已编译DEB的独立反例：代码/签名/requirements篡改、截断、零覆盖、异常签名布局、旧ABI、脚本/图标/依赖变化、权限、成员顺序/压缩错标、额外control/data目录和尾斜杠普通文件。不能用主机签名完整性证明证书信任、设备PAC执行或无watchdog。

只在 release/powercuff-1.3.9 的 push 且 build 成功后发布；同一运行下载产物，核对版本/源码提交/SHA256SUMS；拒绝覆盖既有tag或Release；新tag绑定成功提交。先建非公测草稿上传全部13项附件，再核对集合、大小、digest、完整清单覆盖、source commit、tag和显式stable属性，才公开并设置Latest；随后重复公开验证并核对Latest ID。源码zip/tar.gz由GitHub按同一标签提供，不另行重编译。

verify_release.py 的 --stable/--prerelease 为必选互斥参数，避免误判类型。类型选择只决定元数据预期，不能关闭任何资产/来源校验。实际文件SHA256SUMS覆盖自身之外12项，自身与GitHub资产digest核对。

## 10. 自动化结果与交付追踪

本轮 Python 检查54→57（两项发布类型检查、一项未知偏好诊断）；生产核心22→27组。另含Foundation参数/runtime、C协议、shell/plist、实际签名DEB反例。当前Linux本地57项Python通过；Foundation核心及最终包以本版成功macOS运行的 SOURCE_TESTS.txt/verification.txt 为准，不能把尚未完成的运行算作通过。

最终交付核验：下载GitHub实际构建artifact并核对其API digest；安全展开13项附件；与公开Release资产和完整SHA256SUMS匹配；SOURCE_FILES.sha256与75个跟踪文件及来源SHA对照；公开DEB字节与同一构建产物一致；在本地再运行实际包和反例检查。最终运行/commit/DEB哈希以Release及附件为准，本报告不预填尚不存在的产物结果。

## 11. 真机验收表与仍需确认的边界

| 项目 | 需要的目标设备记录 | 当前证据 |
|---|---|---|
| 安装/升级/卸载 | 正确版本、服务目标、人工注销后两端加载、卸载清理 | 主机脚本矩阵与包检查；实机待验 |
| Off→Light→Off | 设置保存、当前会话回复、private返回、最终模拟退出 | 27组主机核心覆盖对应逻辑；物理效果待验 |
| 五档与LPM | Off/Nominal/Light/Moderate/Heavy及门控进出、保存值不变 | 主机字符串/门控矩阵；真实性能待验 |
| 进程分别重载 | SpringBoard先/后、daemon先/后、无发布端、待机唤醒恢复 | 生产核心时序模拟；实机生命周期待验 |
| 故障与恢复 | 设置Off时发布端暂缺，超时11，恢复后Off | 本轮基线失败与定向回归；实机待验 |
| PAC/温控/watchdog | 新加载后无新增SIGBUS/连续崩溃、心跳正常、Off后自然温控恢复 | 没有目标机运行证据 |
| 续航/热控联用 | 单独启用插件，同亮度/网络/负载重复比较，再逐项评估冲突 | 没有测量结果，不给节电百分比或最佳档位保证 |

首次安装验收先单独测试Off→Light→Off，再考虑Moderate。任何98/99、持续11、daemon新增崩溃或异常温控都不应因“正式版”名称而忽略。历史thermalmonitord SIGBUS/watchdog记录没有足够新证据判定解决。本版已完成的结论限定于明确列出的源码修复、自动化和实际包/发布核验；不承诺消除所有未知故障。
