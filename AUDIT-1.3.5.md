# Powercuff v1.3.3 公测源码复审与 v1.3.5 修订

## 审查基线与交付范围

用户要求针对已发布 v1.3.3 进行完整源码分析、验证、修复，并通过 GitHub 编译发布新 DEB。已核对公开标签 `v1.3.3` 指向 `9eb198b9bda0306ca2816d84220fde8084cdf7b9`，公开包 17,230 字节，SHA-256 `61e124e2a779a9a6df434dc482145c429dd1537626559f4a6f8d7e0a141e12b2`。原包可被本轮更严格的结构/签名检查正常读取，未发现原包遭篡改的证据。

仓库已经发布 v1.3.4，因此采用“审查 v1.3.3，保留 v1.3.4 既有修复，再修订为 v1.3.5”的升级路线；不覆盖旧标签，不将旧包改名当作新构建。补充的 1.3.4 真机采集工具继续保留为历史工具，不用于 1.3.5 的包哈希验收。

目标仍为 iPhone 14 Pro Max / iPhone15,3 / iOS 16.5 (20F66) / RootHide Dopamine 3.0.4；没有连接该设备。本报告区分自动化可验证结果和真机待验证项，发布必须保持 Pre-release。不能由本轮工作推断旧 RC2 的 SIGBUS/watchdog 根因已被解决，也不能据此承诺续航提升。

## 本轮确认的问题与精确修复

| 编号 | 等级与性质 | 复现与影响 | 修复与验证 |
|---|---|---|---|
| C01 | 中，运行时一致性 | 已成功发布 Off；随后写入 Heavy 的共享状态成功但 notify_post 失败；在旧任务重试前设置返回 Off。旧缓存仍记录 Off，新一轮普通发布被去重，旧 Heavy 共享字未纠正。迟到通知或再次读取可能见到不符合当前设置的档位。该代码同时存在于 v1.3.3 和 v1.3.4；合成传输故障不代表用户设备已发生此事 | 写入前使发布缓存失效；仅在 set_state 与 post 均成功后恢复缓存。保持原重试/代际取消机制，不增加轮询或私有调用。生产核心测试验证 Off→失败 Heavy→Off 后共享字为 Off，旧任务失效，private API 不收到 Heavy，重复 Off 不重复调用 |
| C02 | 中，签名校验遗漏 | 在公开 v1.3.3/v1.3.4 的真实签名中，将 CodeDirectory nSpecialSlots 改为 0 后，旧函数仍通过，requirements 不再进入特殊槽哈希循环；修改 scatterOffset 也未被拒绝。原验证只理解连续代码页，却未拒绝改变解释方式的扩展字段 | 对当前独立 dylib 要求 requirements 存在、类型正确且特殊槽完整覆盖；限制已知版本及对应头大小；检查标识符不能落入哈希区；拒绝 scatter、异常 team/runtime/加密/linkage/保留字段及不一致 64 位代码长度，检查可执行段范围、签名 flags/platform。替代 CodeDirectory 范围采用 Apple 头文件的排他上界。合成单测及每次真实构建的签名变异测试均覆盖关键反例 |
| C03 | 中，包兼容性校验遗漏 | 调换原 DEB 三个 ar 成员的顺序，原 verify 仍通过，但本地 dpkg-deb --info 返回 2（非 Debian binary archive）。旧 tarfile 自动探测压缩格式，也没有确认成员扩展名与字节匹配 | 要求 debian-binary、control.tar.*、data.tar.* 的顺序和数量；按 gz/xz/lzma 后缀使用明确解压格式再解析 tar，拒绝不匹配或未知格式。覆盖所有错误顺序及格式反例，并对真实构建包执行负例 |
| C04 | 低，证据交付 | 历史包报告需另外附加，artifact 本身未包含对应版本审计报告；后续设备工具绑定旧版本，直接复用会产生错误版本/哈希结论 | CI 将 AUDIT-$VERSION.md 纳入同一 artifact；README 明确历史 1.3.4 采集工具的适用范围。新发布使用成功构建的原始 DEB 和完整来源附件，不替换原版本采集清单 |

C02 是项目自己的完整性门禁加固，不是发现 Apple/iOS 的签名绕过漏洞；C03 是检查器遗漏，不是原始发布包无法安装。新校验器有意只支持本项目的独立、未加密、无外部资源签名布局，不宣称是通用 Mach-O 或证书信任验证器。

## 旧代码失败的独立证据

先仅向 GitHub 提交新的 C01 行为用例，生产 PCRCore.h 仍为 v1.3.4 原实现。提交 `fa55d969072072b3952299c57e105bf38d9a7ed3` 的 [Actions 40518081925](https://github.com/allantopwisdom-cell/Repo/actions/runs/40518081925) 在 macOS/Xcode 15.4 执行真实生产头文件，断言 `repairedMode == 0 && PCRLastPublished == 0` 失败，退出 134；构建/上传阶段被跳过。随后才上传修复，最终成功 run 及 SOURCE_TESTS.txt 随 Release 记录。失败 run 仅作问题复现，不能作为可安装构建。

C02/C03 在本地读取公开 DEB 后仅修改临时副本复现，未修改公开附件。新版验证器继续接受未修改的原 v1.3.3 包；这可排除“仅因不认识旧版本而拒绝反例”的误判。

## 全部源码、资源及交付路径覆盖

| 文件/路径 | 审查结论、处理与边界 |
|---|---|
| Powercuff.x | 仅在 SpringBoard/thermalmonitord 和 iOS 16 初始化；动态检查 CommonProduct/GPProduct 初始器和 apply ABI；继承关系决定是否另装 hook。LPM 通知转发至 publisher 串行队列。保留 hook 点和线程策略，真实初始化时机与主队列契约待设备验收 |
| PCRCore.h（v1.3.3 中对应 Powercuff.x 的核心部分） | 逐段审查注册、观察、解码、弱对象捕获、product 替换、会话生成、发布缓存、重试、代际取消、异常终止。修复 C01；保留 v1.3.4 的有界读取恢复和状态11。所有缓存访问沿各进程的串行队列；不强持有 daemon product |
| PCRPreferences.h | 指定持久域的一份快照，不搜索其他默认域；数值有限且为0..4整数，拒绝布尔档位/字符串/容器/越界/小数；LPM 门控非法值回 Off。Foundation 测试验证搜索域隔离、快照一致性及解析 |
| PCRProtocol.h | v2 前缀、32位非零会话、保留位和档位校验；C 测试遍历档位/边界会话/头部翻转/错误回复。会话是防旧缓存的协调值，不提供认证；本轮保持协议兼容 |
| PCRRuntime.h | 严格校验实例方法参数数目、普通对象参数与返回值、self/SEL；拒绝 block/scalar/未知签名；判断真实方法所有权而非仅比较 IMP。runtime 注册的合成类覆盖继承、别名及不相关相同 IMP |
| Makefile/control | arm64e、RootHide、iPhoneOS16.5 SDK、最低 iOS16.0；依赖与冲突集合、包名和新版本精确比对。支持范围仍为 iOS16/RootHide，不扩展为其他越狱方案的兼容承诺 |
| PowercuffBaldaranTrusted.plist | 精确注入两个进程，产物与源码 plist 语义一致；无 App/Settings/Widget 注入 |
| layout/Library/PreferenceLoader/Preferences/PowercuffBaldaranTrusted | PowerMode 与 RequireLowPowerMode 的域/通知一致，默认 Off/false；五档标题和值对应。三张图标逐字节比对；不添加无依据的固定频率/帧率/省电描述 |
| layout/DEBIAN/postinst/prerm/postrm | configure/remove 一次 kickstart，失败最多一次 TERM；升级/卸载生命周期不以 root 改 mobile 偏好、不广播旧状态、不重复强杀。受控命令夹具验证成功、失败回退及 noop 路径 |
| build.sh | 失败即停；make clean 后本地真实构建，再规范化数值属主/时间，源码对照、签名/包检查和真实 DEB 变异测试；不会由 tee 隐藏验证失败。源码 ZIP 构建需 SOURCE_DATE_EPOCH |
| scripts/normalize_package.py | 在临时文件中重建归档后原子替换；归一化数值属主0/0和时间，不改变签名 payload 字节。合成测试验证 payload 保持与重复执行一致。不能由此推断全链位级可重现 |
| scripts/verify_package.py | 本轮 C03；延续精确 payload 清单、路径安全、目录0755、文件精确模式、禁特殊文件/链接、源码元数据/脚本/图标/静态plist对照，以及 RootHide install ID、五项动态依赖和部署目标检查 |
| scripts/macho_signature.py | 本轮 C02；校验实际代码页、特殊槽摘要和解析边界；遇未知布局失败。拒绝 Python -O，避免 assert 检查失效。完整性检查不证明平台信任或 PAC 运行 |
| scripts/test_built_package.py | 对本次实际签名/包做变异；C03 修复后反例也保持原压缩类型，确保脚本/图标等负例不会因错误压缩格式提前失败而冒充目标检查有效 |
| scripts/check.sh / tests | Python36项、C协议、shell/plist语法；macOS Foundation偏好、runtime ABI 和实际生产核心13组执行测试。Linux 的 Foundation 跳过明确记为未执行，最终以 Actions 输出为准 |
| .github/workflows/build.yml | macOS14/Xcode15.4，固定 Actions/Theos/SDK 提交；最小 contents:read、checkout不保留凭据、bash pipefail、并发取消旧构建；报告与来源清单随 artifact 一起上传。Homebrew与runner镜像并非固定快照，记录实际环境 |
| verify-on-device.sh | 只读基础诊断；通知值可能缓存，不能当作实时加载/真实节流证明。状态11代表超时且旧模式可能残留；root 默认域不代表 mobile |
| Powercuff-1.3.4-device-check.sh / DEVICE-ACCEPTANCE-1.3.4.md / DEVICE_TOOLS_SHA256SUMS / tests/test_device_check.py | 历史1.3.4工具及11项命令夹具；独立读取、不进入新DEB、不改写历史包哈希。README明确勿用于1.3.5版本校验 |
| README.md / AUDIT-* / ANALYSIS.md / BUILD-REVIEW.md / .gitignore | 当前README更新至本报告和1.3.5；旧报告保留为历史，不混充当前验证证据；忽略构建/缓存目录。全体跟踪文件均记录 SHA-256 |
| 根目录历史1.1.x/1.2.x DEB | 作为历史归档逐项纳入来源清单，不在 layout 中、不参与当前 make package 或新 artifact 文件选择，未重新发布为新二进制 |

## 验证层次与发布门禁

1. 本地：36项Python、C协议、shell/plist语法与diff检查；公开旧包完整性读取、实际签名/归档反例。
2. GitHub：先确认 C01 新测试在未修复核心上失败；最终提交再通过全部 Foundation/runtime/生产核心测试、Theos arm64e 编译链接及签名。
3. 打包：规范化→精确结构与源码对照→实际包负例。构建报错不发布。
4. 来源：SOURCE_COMMIT、SOURCE_FILES.sha256（全部跟踪文件）、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、SOURCE_TESTS.txt、verification.txt、AUDIT-1.3.5.md 及 DEB SHA256SUMS。
5. 发布：tag 绑定同一成功构建提交；上传该 run 的原始 artifact，不重新打包二进制。公开下载后核对 Release API 摘要及本地摘要，再执行源码比对/签名/负例，并用 dpkg-deb 读取包。

最终构建结果、源码SHA、DEB大小/摘要和链接以同一 Release 的附件与正文为准；本报告随源码提交，不能在构建前预填尚未发生的成功结果。

## 真机验收表与当前证据边界

| 项目 | 验收动作 | 当前结论 |
|---|---|---|
| 安装/升级/卸载 | mobile偏好保持正确，安装后注销；确认两个进程加载同版代码，卸载后hook退出 | 无连接真机，待验证 |
| 档位与 Off 恢复 | Off→Light→Off；快速往返，保存新日志，确认真实系统策略恢复 | 仅合成 API 返回和状态正确，待真机 |
| LPM 门控 | 开关LPM、充电切换，选中档位与Off按设置生效 | Foundation/核心用例通过后仍需实测 |
| 两端重启/唤醒 | SpringBoard与daemon分别重启、锁屏待机/唤醒，不沿用旧会话 | 合成会话/替换/弱引用用例覆盖，真实调度待验收 |
| 稳定性与兼容 | 检查新生成的thermalmonitord crash、SIGBUS/SIGSEGV/watchdog、RootHide加载/PAC | 静态校验和ObjC异常处理不能证明这些项目 |
| 续航/流畅度与热控恢复 | 同温度/亮度/网络/负载重复对照；先独立插件，再逐个恢复其他热控插件 | 无测量，不承诺收益或Hello CPU组合适配 |

持续通信失败可能保留先前模式；状态11不是Off。有效新回复或新product可恢复，超出有限重试窗口后需要新的设置事件或进程恢复。保持默认Off、原档位语义、有限重试和注入范围，未为“优化”引入后台轮询、硬频率或强制策略。

## 格式依据

- Apple开源 [XNU cs_blobs.h](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h)：CodeDirectory分版本布局、特殊槽与替代目录索引上界。实现采用适用于本项目产物的更小支持范围，不是所有合法Apple签名的兼容解析器。
- Debian官方 [deb(5)](https://manpages.debian.org/bookworm/dpkg-dev/deb.5.en.html)：ar成员次序与压缩命名；本项目限制为当前工具链使用的gz/xz/lzma。
