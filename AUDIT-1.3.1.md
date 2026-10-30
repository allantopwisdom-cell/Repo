# Powercuff v1.3.0 复审与 1.3.1 修复记录

基线：GitHub `v1.3.0`，源码提交 `5d25a8e847d4da181999051ceed9debcd298566f`。目标验证设备：iPhone15,3 / iOS 16.5 (20F66) / RootHide Dopamine 3.0.4。

## 证据与实际发现

当前公开 DEB 为 16,022 字节，SHA-256 `c5523aa55504b1f1984e679271675f664ac793691ef2731e86372f78e3c4cbb3`。首次手工发布的同名包为 16,032 字节，SHA-256 `448143fd599d34eb5246c45050ae28e865579b63b63a2fd4360aec7dac4d2f92`。标签运行 #78 成功后替换了同名附件，而 `SHA256SUMS-release.txt` 仍保留旧包哈希。此问题已经实际发生，并非假设风险。当前发布仍为公开状态；此前担忧的“转回草稿”没有在当前状态中观察到。

审查覆盖全部运行源码、协议、注入 plist、PreferenceLoader 设置、包元数据、维护脚本、CI 及校验脚本；下载并解析当前公开二进制。未获得真机权限或进程镜像，不能做动态 hook、耗电或 watchdog 验证。

| 项目 | 等级 | 1.3.0 发现 | 1.3.1 修复/处置 |
|---|---|---|---|
| 发布附件漂移 | 高 | 标签触发二次构建，覆盖已发布 DEB，遗留旧哈希 | 移除标签自动构建及自动修改 Release 的 job；发布固定提交的已验证 artifact，公开下载后再核对 digest |
| daemon 启动残留状态 | 高 | product 捕获后先调用 PCRApplyThermals，再请求 publisher，版本相同的旧档位会立即被接受 | 协议 v2 加入非零 32 位会话号；每次 product 初始化换会话，只接受匹配会话回复；不直接应用历史状态 |
| 请求丢失恢复 | 中 | daemon 仅 post 一次请求；丢失后没有主动恢复 | 单个 product generation 最多 6 次请求，400ms 间隔；成功执行、对象消失、异常或 generation 更新即停止 |
| 发布失败恢复 | 中 | 发送失败只记录日志，依赖未来其他事件重试 | 同一 generation 内最多 6 次尝试；新事件使旧重试失效，不进行永久轮询 |
| 偏好开关异常值 | 中 | NSNumber 的 NaN、负数、2 等 boolValue 可被当作开启；mode 的 CFBoolean 被当作 0/1 | 严格 mode 整数 0..4 且拒绝 CFBoolean；gate 仅接受 NSNumber 0/1，其他值回到 Off |
| 方法不支持的诊断 | 低 | 两类 ABI 都不匹配时只留下“等待”，难以区分不支持与尚未初始化 | applied=99 并记录日志，不安装不匹配 hook |
| 脚本失败可见性 | 低 | daemon reload fallback 失败也无提示 | 提示重启/验证需求，仍保留包生命周期的 best-effort 行为 |
| 签名验证深度 | 中 | 仅证明 LC_CODE_SIGNATURE 数据范围存在 | 校验 SuperBlob/CodeDirectory 结构及每个代码页哈希；对本次构建包执行篡改和截断反例测试 |
| 测试覆盖 | 中 | Linux 检查不涉及真实 Foundation 偏好类型行为 | 抽取生产偏好解析函数，由 macOS 上的 Objective-C 测试执行 NSNumber/集合/字符串/NaN/LPM 边界 |
| 校验文件可用性 | 低 | SHA256SUMS 文件名带 packages/ 前缀，平铺下载后不能直接校验 | 在 packages 目录内按 basename 生成，下载到同一目录可执行 sha256sum -c SHA256SUMS |

## 本地验证

- 当前公开 1.3.0 DEB：版本、单一 arm64e、RootHide install ID、限定注入范围、偏好键及维护脚本检查通过。
- 当前公开 1.3.0 Mach-O：CodeDirectory 页哈希验证通过；修改首字节、修改签名之前最后一个字节、破坏签名 magic、截断签名均被拒绝。
- 协议测试：不同非零会话、会话变化、旧 1.3.0/裸值、非法保留位、头部和会话位损坏均覆盖。
- 维护脚本回归、全部 plist 解析、shell 语法与 diff 空白检查通过。
- Foundation 偏好测试只能在 macOS 执行，必须以对应 GitHub run 的结果为准；不能将本地跳过记录视为通过。

## 构建/发布验收

1. 在独立 `fix/powercuff-1.3.1` 分支提交完整源码，运行现有固定工具链。
2. macOS 执行所有测试，并编译、签名、打包 1.3.1。
3. 对实际包验证版本/架构/签名代码页/安装路径/filter/偏好与脚本，执行损坏文件反例；只有成功才上传 artifact。
4. Release `v1.3.1` 绑定成功构建的精确提交，上传 DEB、单一 SHA256SUMS、源码提交、工具链引用、验证记录。
5. 下载公开附件，核对 digest 与包校验结果。标签不再生成替换附件的运行。

## 保留的限制与工程取舍

- 主队列与系统私有 thermal product 的真实线程契约仍未经真机确认；本次不猜测另一条私有线程或扫描偏移。
- 方法匹配、ObjC 异常捕获不能阻止 SIGBUS/SIGSEGV/watchdog，weak 能力及生命周期仍依赖系统实现。
- 会话号用于 freshness，碰撞概率非零，不是认证。Darwin notify 不提供本插件独占的安全隔离；本次没有宣称防恶意同机进程。
- 缺失偏好与暂时不可读仍不可完全区分，有限重试后 Off 是保守取舍；若所有重试均失败，等待未来设置/电量/启动复查事件。
- 代码页签名验证不等于证书信任、特殊槽完整性、PAC 运行验证或越狱加载成功；不宣称完整 Apple 代码签名验证器。
- 1.3.1 协议与 1.3.0 不兼容，升级后必须注销一次。没有改变档位含义、添加 CPU 固频或后台冻结；也不自动调到 Moderate/Heavy。
- CI 固定 Theos/SDK，但 Homebrew 与第三方 Action 主版本仍可变化，DEB 也含打包时间；没有位级可复现构建承诺。
- 1.3.0 发布内容保留作为历史；不会为掩盖问题覆盖旧版本。
