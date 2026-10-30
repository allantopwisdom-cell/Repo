# Powercuff 1.3.8 构建与发布说明

基线为已发布v1.3.7提交bdca4810397010c49696eab57325a825cbc8d778，使用独立release/powercuff-1.3.8分支。基线DEB SHA256：3cf1e41b2a195b0a584534b1f6ad350e0be73e695c0dd5c4415e09993f5b9f35。

## 回归依据

基线运行41037610718仅新增测试，生产代码未改：49项Python通过，发布端缺席时不兼容对象未在IPC前熔断的断言失败，退出134，未构建或发布。新修复在生产PCRCaptureProduct中前置实际对象ABI检查并取消旧请求，保留原断言、Drain上限和时钟单调规则。服务域新测试也确认旧脚本未探测前台域。

## 构建门禁

- macOS15、Xcode16.4；先执行54项Python、C协议、shell/plist及Foundation参数/runtime和22组生产核心模拟场景。
- RootHide Theos固定cfba89a53a05b4a1b822121158acc3669c20602f，iPhoneOS16.5 SDK固定0222fd5413cf4b9af096f37b4621afa2688572f7；第三方Actions固定提交。
- 完整编译、链接、签名、打包；归档UID/GID规范为0/0、时间来自源码提交，不改变已签名payload。
- 精确一个1.3.8 DEB，通过versioned arm64e PAC00、签名页/特殊槽、iOS部署、依赖、RootHide路径、文件/目录清单、设置及静态资源/维护脚本源码对照。
- 实际Mach-O/DEB篡改、错误ABI/权限/归档/目录/尾斜杠反例必须拒绝。

## 发布门禁及附件

只允许该发布分支push的成功产物。非覆盖创建v1.3.8标签绑定成功提交；先草稿上传并核对全部附件集合、大小、SHA256、版本、SOURCE_COMMIT和草稿/公测状态，公开后复核；不另行重编译，不覆盖历史发布。

共13项附件：DEB、verification.txt、SOURCE_TESTS.txt、BUILD_ENVIRONMENT.txt、SOURCE_COMMIT、SOURCE_FILES.sha256、TOOLCHAIN_REFS、VERSION、AUDIT/BUILD/RELEASE-1.3.8.md、verify_release.py、SHA256SUMS。SHA256SUMS覆盖除自身外全部12项，自身也校对GitHub资产digest。GitHub自动提供的源码zip/tar.gz不计入13项。

SOURCE_FILES.sha256包含本次全部跟踪文件；SOURCE_COMMIT是实际成功提交。最终交付还应比对本地/远程完整文件与权限、公开下载DEB与构建产物字节。目标设备安装、PAC执行、私有API、watchdog、真实温控与续航仍须真机验收；详见AUDIT-1.3.8.md。
