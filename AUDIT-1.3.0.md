# Powercuff 1.3.0 深度审查与修复记录

审查基线：`ee60f62cf19f88ea7a8fb4e25ee3d224a298007a`，main 中的 1.2.4 源码与同版本 DEB。目标：iPhone15,3 / iOS 16.5 (20F66) / RootHide Dopamine 3.0.4。审查涵盖仓库全部源码、注入 filter、偏好页、构建及维护脚本、文档；旧二进制归档保留，未重新声明其安全性。

## 总体评估

1.2.4 的用途是热模拟档位下发，无法从源码推导具体频率或续航收益。其主要风险集中在关键系统 daemon 内的私有调用、跨线程对象状态、跨用户偏好域与发布证据。当前修复减少可确认的实现缺陷，但缺少目标设备进程镜像、真实调用轨迹及长期真机测试，不能评为“完美适配”或“无风险”。此前 thermalmonitord SIGBUS/watchdog 不能仅凭这些缺陷定因，也不能声称已经消除。

## 逐项发现与措施

| 编号 | 严重度 | 1.2.4 实际问题 | 1.3.0 措施 |
|---|---|---|---|
| H01 | 高 | postinst/postrm 先 kickstart 再无条件 killall -9，成功重启后仍再次杀进程 | 首选成功即停止；失败才 TERM；仅 configure/remove 执行 |
| H02 | 高 | initializer 原线程写弱缓存，独立串行队列读；私有调用线程归属无依据 | daemon 缓存与调用统一主队列，捕获弱引用后在队列取强局部；主队列是否符合私有实现仍须真机验证 |
| H03 | 高 | 任意偏好对象直接 integerValue/boolValue，数组/字典可触发无法识别 selector | 只接受 NSNumber；拒绝越界、非整数、NaN；异常数据回到 Off |
| H04 | 高 | root 维护脚本的 defaults 与 mobile Settings 域不同，不能保证初始化/卸载复位 | 删除 root 偏好读写；由 SpringBoard 读取，缺失键短暂重试后明确默认 Off |
| M01 | 中 | notify 初始 0、有效 Off、旧版本残留无法区分 | 增加版本头并拒绝裸值与非法 payload；升级必须 respring |
| M02 | 中 | daemon 重启后仅依赖历史 notify 状态，publisher 会去重 | product 初始化请求 publisher 强制重新发布；保留正常档位去重 |
| M03 | 中 | notify_set_state/post 失败仍更新“已发布”缓存 | 只有两步成功后才更新缓存；注册/观察失败记录并停止依赖该通道 |
| M04 | 中 | hook 不验证 initializer/selector 是否存在及 ABI | 安装 hook 前校验 object 参数、返回类型、参数数目；继承同一 initializer 时避免双 hook |
| M05 | 中 | NSObject 异常无边界 | 捕获 ObjC 异常，当前对象熔断；明确不捕获进程信号及 watchdog |
| M06 | 中 | 偏好重试任务可堆叠，首次缺失键永久不发布 | generation 使旧重试失效；每次最多 5 次短重试，另有 3/10/30/60 秒启动复查，无周期轮询 |
| M07 | 中 | 未证实的 SpringBoard 私有电量回调 hook | 删除，保留公开低电量状态通知 |
| M08 | 中 | after-package chmod 在包生成后才改权限 | 改为 before-package，并在实际 DEB 内验证执行位 |
| M09 | 中 | 每次推送覆盖固定 v1.0.0-1 Release，产物来源混淆 | 精确版本校验、按 commit 命名 artifact、仅版本标签生成草稿 Release |
| M10 | 中 | 无 PR 检查、工具链源跟随 HEAD、无产物门禁 | 加回归检查与包内容门禁，固定 Theos/SDK，限制默认 token 为只读 |
| L01 | 低 | 构建 clean 失败被忽略、运行目录不确定 | 进入脚本目录、set -eu、失败立即退出 |
| L02 | 低 | 默认 0 被诊断脚本解释为“安装且有效”；root defaults 混淆 | 展示原始分层状态并说明残留与用户域；不把发布等同于执行或节流 |
| L03 | 低 | README 仍宣称 jbroot 自动路径、确定 PAC 验证、旧版本下载 | 按当前实现重写，移除无证据的保证，历史文档标为历史 |
| L04 | 低 | 描述“不会限制帧率”可能被理解为性能无影响 | 明确热模拟可间接影响性能/帧率 |

## 验证范围与证据

- 本地回归：状态协议 C 测试覆盖 0..4 往返、旧值、非法低位、每个高位损坏及越界编码；维护脚本测试覆盖重启成功、失败 fallback、upgrade/purge/abort 无副作用；所有 plist 解析及 shell 语法检查。
- 旧 1.2.4 包：读取 ar/tar 与文件清单；新的安全门禁会拒绝其 SIGKILL / root defaults 写入，符合预期。旧包的 tar gid=20 在本 Linux 容器不能 chown，改用内存解析，不能据此判定 DEB 损坏。
- 新 1.3.0：以对应提交的 GitHub Actions 结果为编译证据；包验证脚本验证实际打包内容，不以源码文件代替产物。
- 未执行：目标真机安装、签名加载、PAC 运行行为、私有 API 真实副作用、温控恢复、24 小时耗电比较。云端编译成功不能代替上述验证。

## 仍需保留的限制

1. main queue 只是保守的执行归属选择，未取得该 iOS 私有实现的线程契约。weak 引用能力和 product 生命周期仍取决于系统对象实现。
2. CommonProduct/GPProduct 在构造时不存在或产品初始化不经过对应方法时会不生效；本版本不进行猜测地址扫描或广泛进程注入。
3. Darwin notify 是同机协调通道，版本头用于格式校验，不是身份认证。其他具相应权限的进程仍可干预；没有宣称安全隔离。部分沙箱环境可能不允许写状态，日志需实测。
4. NSUserDefaults 缺失键与暂时不可读不能完全区分，短暂重试后选 Off 是安全性取舍；启动有界复查不能保证恢复任意时刻的 cfprefsd 异常。
5. 方法正常返回只代表调用完成；系统是否接受、覆盖或延迟执行该档位需另行观测。本插件也不能保证与其他热控插件协同。
6. 源仓库没有明确许可证，保留既有作者归属，不擅自授予新的开源许可。Theos/SDK 已固定提交，Actions 的主要版本标签和 Homebrew 包仍可能变化，尚非位级可复现构建。
7. 不自动删除历史 DEB，不自动合并主分支，不自动发布公开 Release。

## 真机验收建议

安装前保留可移除插件的入口，先停用其他热控干预以便归因；安装后注销。依次测试 Off → Light → Off、LPM gate 开/关并切换系统 LPM、手动 daemon 重启后的恢复、用户主动卸载后的 stock 恢复。每步记录新 PID、对应时间日志与崩溃报告，不能只读取可能残留的 notify 值。稳定后，在相同亮度、网络、前台负载与电池温度条件下做多轮耗电比较，再决定是否采用 Moderate。

## 本次实际交付状态

本地 C 协议测试、维护脚本回归、plist 解析、shell 语法和 `git diff --check` 均通过。GitHub App 创建分支返回 HTTP 403（Resource not accessible by integration）；标准 Git 推送因缺少 HTTPS 用户凭据失败。远端 main 未修改，尚未触发 1.3.0 云端构建，也没有生成新 DEB。工程包含完整源码与可执行的 Actions 流程，编译结果须待恢复仓库写权限后取得。
