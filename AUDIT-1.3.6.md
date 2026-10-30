# Powercuff v1.3.6 完整源码复审与发布验收

## 输入、版本与证据范围

输入为用户附加的 powercuff-repair-source-unverified.tar.gz，SHA-256 `e7e9ef279e1bf4997799088e26fb1a68fb5f62dea1ccfefd74530748202f5151`。归档含70个条目、59个普通文件，无链接或特殊文件；只在隔离目录解包。相对已发布v1.3.5，上传包改动PCRCore.h、Powercuff.x、两份维护脚本和两份测试，目录名为1.3.6，而control/README仍为1.3.5。

同时核对仓库现有release/powercuff-1.3.6分支，基线提交 `deebf1aa2c753370f358c2318fbbf11ac1ff88e3`。它已经保留恢复锁存并迁移工具链，但生产核心测试仍失败，尚未发布v1.3.6 Release。本轮在该分支基础上保留macOS15/Xcode16.4、PAC00门禁与先前本地包撤回记录，完成完整项目差异核对及定向修订。最终源码提交、DEB摘要与成功CI结果以本次Release附件为准，不在构建前预填成功结果。

目标为iPhone14ProMax/iPhone15,3、iOS16.5(20F66)、RootHide Dopamine3.0.4。没有连接目标设备；代码执行回归不等同于实际daemon加载、温控或续航测量。维持公测Pre-release，不将旧RC2的SIGBUS/watchdog归因为已解决的问题。

## 已确认的问题与处置

| 编号 | 等级/性质 | 证据与影响 | 精确处置 |
|---|---|---|---|
| R01 | 中，状态恢复循环 | 上传版在请求超时时清除PCRRecoveryRequested；请求回复可能留下超过超时时间的延迟读取，持续失败时再次启动恢复，形成反馈。macOS失败运行40971591488超过Drain的1000任务上限，退出134 | 保持超时锁存；只有有效回复、新对象或明确的设置编辑事件可启动适当恢复，传输通知不能自行解除锁存。原持续失败断言保留，明确设置事件下仍验证请求不超过六次 |
| R02 | 中，修复与测试不一致 | 现有修复分支已保持锁存，但旧用例仍要求超时后锁存为false；40972410830在该断言退出134，发布job被跳过 | 独立观察settingschanged，调用生产PCRRequestForSettingsChange；它取消旧任务并开始一轮有限请求，daemon仍不读取mobile偏好。用例先验证无效传输不自我重试，再验证明确事件恢复。无对象、98异常、99ABI熔断均不允许通过此入口发起私有尝试 |
| R03 | 中，启动丢包与验证覆盖 | 启动重发需强制发送，否则相同发布缓存会跳过补发；原新增测试仅手动调用PCRPublish(YES)，没有执行实际3/10/30/60秒计划 | 将实际启动调度移入共享生产核心，ctor调用同一函数。虚拟时钟执行到握手超时后，再修改偏好为Off并恢复投递；验证四次补发使用当前Off、只调用一次私有方法、60秒后队列清空 |
| R04 | 低，安装诊断与维护重复 | 上传脚本保留错误和退出码，但launchctl缺失/失败的TERM代码重复，易在后续维护时分歧；命令成功不能证明注入和重载成功 | 统一单个TERM回退分支，保留stdout/stderr、各命令退出码和人工注销提示；configure/remove最多一次kickstart及一次TERM，其他生命周期不动作，不写root偏好、不自动注销 |
| R05 | 中，工具链/ABI适配 | 输入仍保留旧工具链说明；已有本地记录显示未版本化arm64e子类型0x2曾被低位检查接受。macOS14正在停用演练且将退役 | 保留现有分支macOS15/Xcode16.4与固定iOS16.5 SDK，严格要求subtype0x80000002，并对真实DEB验证0x2反例拒绝原因。没有二进制改头、没有扩展iOS支持范围 |
| R06 | 中，发布来源绑定 | 自动发布原先只查询Release是否存在；已存在且指向其他提交的tag仍可能被release create复用，--target不能替代tag验证 | 通过创建git ref的非覆盖API将tag原子绑定GITHUB_SHA，已有tag则失败；再用--verify-tag创建公测Release，随后解析tag提交校验。不覆盖既有Release，不以失败构建发布 |
| R07 | 低，版本与审计交付 | 归档目录/包版本/README不一致；旧流程仅附BUILD/RELEASE，缺少本次全量源码审计附件 | 统一1.3.6、更新当前说明，AUDIT与BUILD/RELEASE随同次artifact交付，所有附件纳入SHA256SUMS，源码全文件清单另附。历史1.3.4诊断哈希不用于新包 |

R01/R02的原失败均已读取实际Actions日志。未提高Drain上限、未跳过持续故障或Off回归。新增设置事件入口是本轮有意的行为补充，不把任何普通传输通知都称为独立外部事件；它仍是Darwin通知协调机制，不提供通知来源认证。

## 失败复现记录

- [40971591488](https://github.com/allantopwisdom-cell/Repo/actions/runs/40971591488)，提交197c408eaed137f636181b21892d8011f53b5dd6：38项Python、C、Foundation/runtime通过，随后`++steps < 1000`失败，退出134；build/publish未执行。
- [40972410830](https://github.com/allantopwisdom-cell/Repo/actions/runs/40972410830)，提交deebf1aa2c753370f358c2318fbbf11ac1ff88e3：持续故障限次用例已通过，随后旧断言要求`!PCRRecoveryRequested`而失败，退出134；publish被跳过。
- 先前Linux本地1.3.6包已在LOCAL-BUILD-1.3.6.md标记撤回。本次成功云端包必须用SHA256SUMS区分，即使版本号相同也需重新安装并注销；不能仅凭文件名确认已替换。

## 完整项目覆盖

| 文件/路径 | 审查、验证与结论 |
|---|---|
| Powercuff.x | 两进程/iOS16过滤；先检查CommonProduct/GPProduct initializer/apply ABI与方法所有权再装hook。增加独立设置观察，启动重发调用生产共享函数；保留LPM观察、线程与hook点，真实初始化时机/主队列私有契约待真机 |
| PCRCore.h | 审查注册失败、状态解码、有限读取/发布/请求、所有generation取消、发布缓存、弱捕获、product替换、诊断与熔断。保留1.3.5发布失败切回Off修复。新设置事件不会解开异常/ABI熔断；保持队列串行访问 |
| PCRPreferences.h | 仅指定持久域的同一字典快照；档位必须是有限0..4整数，排除布尔/字符串/容器/小数/越界。LPM门控非法则Off。Foundation测试涵盖跨域隔离、快照与类型/门控，不引入root写偏好 |
| PCRProtocol.h | v2前缀、非零32位会话、保留位和档位边界；C用例覆盖错误头、旧格式、位翻转、会话边界。与1.3.1至1.3.5协议兼容，仍需注销替换实际代码；会话不是身份认证 |
| PCRRuntime.h | 参数数目、普通对象/void/self/SEL完整ABI验证，拒绝block和标量；检查真实方法所有权，不用相同IMP推断继承。未知编码禁用，不能据此保证私有实现安全 |
| Makefile/control | 包名/架构/版本/依赖与冲突集合核对；RootHide arm64e、最低iOS16.0、固定iOS16.5 SDK。维护脚本打包执行位由Makefile确定；未添加额外进程或其他越狱方案承诺 |
| PowercuffBaldaranTrusted.plist | 精确注入SpringBoard/thermalmonitord，无App、Widget或Settings注入；源码与产物plist语义精确比对 |
| layout/Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted | 两个偏好键的域/通知一致，五档值0..4、默认Off/false；三个PNG图标尺寸29/58/87，静态资源与产物逐字节或plist语义核对。没有硬频率/冻结/帧率功能的虚假描述 |
| layout/DEBIAN/postinst/prerm/postrm | 保留mobile偏好；仅configure/remove请求重启，最多一次TERM回退；purge/upgrade/abort路径不动作。夹具覆盖成功、失败退出码、命令缺失、诊断及生命周期；不执行设备真实重启测试 |
| build.sh | make clean、真实编译、归档规范化、源码对照、签名/ABI及真实包反例；失败即停，POSIX重定向不由tee掩盖错误。源码ZIP构建需SOURCE_DATE_EPOCH |
| scripts/normalize_package.py | 数值UID/GID归零、时间规范化、保留签名payload字节，临时文件替换；测试验证重复执行和payload保持，不承诺整个未固定runner/Homebrew链位级重现 |
| scripts/verify_package.py | Debian成员顺序和按后缀明确解压、路径规范、0/0属主、0755目录、精确文件模式、禁止链接/特殊文件、精确payload/control集合、源码脚本/元数据/图标/plist对照。检查versioned arm64e PAC00、iOS设备16.0部署、RootHide install ID和五项依赖 |
| scripts/macho_signature.py | 已知CodeDirectory版本布局、代码/特殊槽覆盖及哈希、标识符边界、requirements类型、扩展/保留字段；拒绝不支持的scatter/外部签名布局及Python-O。只做本项目完整性检查，不验证证书信任或设备PAC行为 |
| scripts/test_built_package.py | 对本次真实签名和DEB进行变异，包含代码/特殊槽/零覆盖/散列布局/64位长度/未知版本、脚本/图标/权限/依赖/成员顺序/压缩命名和legacy ABI；校验DEB反例的准确失败原因，避免错误压缩提前失败造成假通过 |
| scripts/check.sh/tests | 38项Python、C协议、shell/plist；macOS执行真实Foundation/runtime及共享生产核心15组。保留原故障/Off/LPM/弱引用等用例，增加明确设置恢复和实际启动调度。Linux跳过Foundation不算通过；成功CI输出独立交付 |
| .github/workflows/build.yml | macOS15/Xcode16.4，固定Actions、RootHide Theos和SDK；bash pipefail、checkout不保留凭据、并发取消旧运行。build只读权限，publish限指定release分支并依赖build成功；同次artifact核对来源/全附件哈希，原子创建tag、验证后发布Pre-release，拒绝覆盖 |
| verify-on-device.sh | 基础只读诊断、路径映射、mobile偏好与缓存notify值；不证明当前进程存活或实际温控生效。applied11可能残留旧档位，不代表Off |
| Powercuff-1.3.4-device-check.sh / DEVICE-ACCEPTANCE-1.3.4.md / DEVICE_TOOLS_SHA256SUMS / tests/test_device_check.py | 旧1.3.4专用工具及11项命令夹具，保留历史不进入新DEB；不能套用其旧哈希校验1.3.6。新包使用本版基础诊断和验收表 |
| README/BUILD-1.3.6/RELEASE-1.3.6/LOCAL-BUILD-1.3.6/AUDIT-1.3.6 | 当前文档统一版本、恢复边界、工具链、失败原因与安装要求；保留本地旧包撤回历史。报告随构建交付，成功run与摘要由Release记录 |
| 旧AUDIT-1.3.0至1.3.5/ANALYSIS/BUILD-REVIEW/.gitignore | 历史证据与当前构建忽略规则；旧报告不当作本版重新执行或真机验收结果 |
| 根目录历史1.1.x/1.2.x DEB | 全部纳入跟踪文件来源清单，与输入/已知仓库字节核对；不在layout或当前artifact选择中，不被重新打包冒充本次编译，不对这些历史二进制重新作真机兼容保证 |

最终63个跟踪文件均列入SOURCE_FILES.sha256，逐项与本地审查树核对；Git树还比对文件模式。没有仅以六个差异文件代替完整项目清单。新增输出只含当前包及验证材料，完整源码可从Release同一tag下载。

## 生产核心执行场景与含义

测试直接包含生产PCRCore.h；仅将notify、偏好/低电量输入、队列和时间替换为夹具。Foundation/runtime和消息派发在macOS实际执行，假product只记录调用或抛合成异常，不操作系统热控对象。

1. 注册失败无效token；没有product时明确设置事件不发请求。
2. 会话握手、有效回复取消请求、相同档位去重。
3. 发布post失败后返回Off，纠正共享状态并取消旧任务。
4. 旧会话读取后有限重取当前状态。
5. 持续读取失败，自动恢复和明确设置恢复均保持有限请求，队列排空，后续有效Off恢复。
6. publisher缺失六次请求后停止，迟到有效回复恢复。
7. 无效传输不能自行重新恢复；明确设置事件可恢复，且相同模式不重复私有调用。
8. 执行实际启动计划，丢包持续到握手超时后恢复，四次重发读取当前Off，60秒后停止。
9. 缺失偏好经过有限重试后默认Off。
10. ObjC异常对当前对象熔断，设置事件不能绕过；替换对象重新握手。
11. ABI不支持熔断，设置事件不能绕过。
12. product替换使旧会话/异步请求失效。
13. 延迟捕获不强持有已销毁的product。
14. 快速设置/LPM变化读当前值，取消旧补读。
15. set/post短暂失败在预算内恢复。

单次外部设置事件最多六次请求，但连续用户事件可以各自发起有限请求；无连续后台轮询。超时后若没有有效新发布、明确设置变化或新对象，可能维持旧模式；不能将状态11解释为已恢复Off。

## 发布验收与真实设备边界

本地已执行38项Python、C协议、shell/plist和diff检查。macOS门禁还必须执行上述Foundation/runtime/核心测试、编译链接/签名、包源码对照与真实包反例；结果不从本地或旧版本推断。构建/发布任一步失败需处理后再交付。

发布同次artifact的DEB、VERSION、SOURCE_COMMIT、SOURCE_FILES.sha256、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、SOURCE_TESTS.txt、verification.txt、BUILD/RELEASE/AUDIT文档与SHA256SUMS。发布后从公开地址下载，核对全部附件摘要、tag对应源码SHA，并再次验证公开DEB的源码资源/签名/ABI/反例及dpkg-deb可读取性。

| 真机项目 | 放行条件 | 当前证据 |
|---|---|---|
| 安装/同版替换/升级/卸载 | 注销后两端实际加载对应代码、偏好保留、卸载后hook退出 | 尚未连接设备 |
| Off→Light→Off及快速切换 | 系统实际策略生效/恢复，无新增崩溃或明显卡顿 | 仅合成API返回与状态转移 |
| LPM/充电/锁屏唤醒 | 门控切换、唤醒、两进程分别重启后恢复 | 自动化输入可控，真实调度未验收 |
| PAC/私有API线程契约 | 目标RootHide环境实际加载稳定，私有实现正常 | ABI/签名通过不等于运行通过 |
| SIGBUS/SIGSEGV/watchdog | 新crash记录与长时心跳观察无新增问题 | ObjC异常处理不能捕获这些终止 |
| 续航/流畅度/热控联用 | 同温度亮度网络负载反复对照，先单独插件再逐个恢复Hello CPU等 | 无测量，不承诺收益或组合适配 |

安装本次云端包后手动注销一次，先单独测试Off→Light→Off和LPM门控；保存新日志及crash记录。保持默认Off和原档位语义，没有为省电引入硬频率、强制冻结、App注入或扩大iOS范围。

## 外部格式/工具依据

- [GitHub macOS14退役公告](https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/)：2026年11月2日退役及此前停用演练；本轮保留macOS15配置。
- [GitHub CLI release create](https://cli.github.com/manual/gh_release_create)：--verify-tag要求已有tag。项目在发布前以非覆盖ref创建API锁定源码提交，不依赖--target纠正已存在的tag。
- Apple CodeDirectory与Debian归档格式的既有实现依据和边界保留于AUDIT-1.3.5.md；本轮保留相应门禁并执行实际包负例，不将其当作证书信任或稳定性证明。
