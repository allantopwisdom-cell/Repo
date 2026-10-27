# Powercuff v1.3.4 真机发行验收

这是已发布v1.3.4的补充只读工具，不修改DEB运行时，也不将发行候选版自动改为稳定版。工具核对的原始DEB SHA256为 `9d1a20f0c68aaa7600573c2b6381bd5de5df521020c342c75a4b637e411f9ee6`。不要用其他分支重新编译的同版本包代替该发布附件。

## 第一次运行

1. 从v1.3.4 Release取得DEB和 `Powercuff-1.3.4-device-check.sh`。在包管理器安装DEB后注销一次；本工具不会安装、注销或重启任何服务。
2. 本轮先单独启用Powercuff，暂停Hello CPU及其他热控插件。在Dopamine界面手动核实RootHide Dopamine 3.0.4。不要为收集报告切换到root。
3. 把脚本放入NewTerm当前目录，以mobile执行：

```sh
sh Powercuff-1.3.4-device-check.sh > Powercuff-baseline.txt
```

退出码0只表示该次自动检查未发现异常；1表示观察到需要核查的异常；2表示用户/参数不适合执行；3表示证据不完整。输出中的 `NOT-RELEASE-APPROVAL` 始终保留。若命令失败，重定向仍会保留报告，终端中可用 `echo $?` 查看紧邻前一个命令的退出码。

工具只读取：目标机型/系统、Powercuff包元数据、六个已安装文件、SpringBoard和thermalmonitord进程、两个插件配置键、六个插件通知值，以及最多20个相关崩溃文件名。不上传数据，不读崩溃正文，不读取整个App或偏好数据库；输出由命令重定向保存在你指定的本地文件中。

## 功能状态采集

在设置中手动切换，每次等约5秒再运行对应命令。脚本标签只是你提供的测试场景，不自动判断系统低电量模式是否开启。

| 报告 | 事先手动设置 | 命令 | 希望观察 |
|---|---|---|---|
| off-before | 插件Off；“仅低电量生效”关闭 | `sh Powercuff-1.3.4-device-check.sh --label off-before > Powercuff-off-before.txt` | applied=0 |
| light | 插件Light；“仅低电量生效”关闭 | `sh Powercuff-1.3.4-device-check.sh --label light > Powercuff-light.txt` | applied=2 |
| off-after | 插件Off | `sh Powercuff-1.3.4-device-check.sh --label off-after > Powercuff-off-after.txt` | applied=0 |
| lpm-off | 插件Light；“仅低电量生效”开启；系统低电量关闭 | `sh Powercuff-1.3.4-device-check.sh --label lpm-off > Powercuff-lpm-off.txt` | applied=0 |
| lpm-on | 保持Light及门控；系统低电量开启 | `sh Powercuff-1.3.4-device-check.sh --label lpm-on > Powercuff-lpm-on.txt` | applied=2 |

第一轮可以先只交回 baseline、off-before、light、off-after 四份报告。发现新增thermalmonitord崩溃、watchdog或Off恢复异常时停止切换，保留当前报告及相关新崩溃日志，先排查，再继续LPM或较高档位测试。

## 如何解读

- `SESSION-MATCH`：采样的request/thermals协议头和会话一致；读取不是原子的，重启/改档过程中不一致应安静等待后重采。通知注册/状态不构成身份认证。
- `DISK-MATCH`：磁盘文件字节与原始发行DEB一致；不证明内存中已经加载该文件。安装后注销要求仍然存在。
- `DISK-DIFF`：待核查。RootHide安装器补丁/重签等可能改变字节，不据此单独判定包损坏。
- loaded/hook标记可能残留；有PID也只证明采样时存在进程，不能证明它已经加载正确插件或长期稳定。
- applied=0..4只表示某次私有方法返回；10等待；11通信超时，旧档位可能仍有效；98异常；99 ABI不符。98/99也可能残留，应结合重载时间和新日志。
- 缺失配置键可能是尚未持久化的默认值，也可能不可读；工具保留为UNVERIFIED，不擅自写入或修复。
- 崩溃文件名是有限列表，可能有旧文件或未列出的文件；没有列出新文件不等于watchdog/崩溃验收通过。必要时在系统分析数据中手动导出对应新报告。

已核对Apple notifyutil实现：`-g`可能打印读取失败却以0退出，因此工具检查准确的键名和十进制值，不只看进程退出码。参考：https://github.com/apple-oss-distributions/Libnotify/blob/main/notifyutil/notifyutil.c 。

## 仍需真机证明的发行条件

本工具及其host命令fixture测试不能验证：PAC/真实私有API线程契约、节流和温控实际恢复、掉电/帧率收益、长待机与唤醒、watchdog长期稳定性。先完成上述独立功能测试，再做相同亮度/网络/负载/温度的Off与Light对照；不要用一份“自动检查通过”替代正式稳定版验收。

原v1.3.4源码、DEB与构建记录保持原提交；补充工具的源码和命令fixture测试由独立的device-acceptance修订记录提供。
