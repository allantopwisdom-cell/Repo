# Powercuff 1.3.9 构建及正式发布记录

目标：iPhone15,3 / iOS16.5(20F66) / RootHide Dopamine3.0.4，iphoneos-arm64e。

基线 v1.3.8 为 af02c532fdf9c41f4fa0bee19344c242aaa9f81e。仅增加故障测试的 8535e48d2c8ad78bbfb05a75e5ddeb81d4ac3055 在 macOS 运行41040992053复现旧缓存误确认，构建/发布被阻止。详见 AUDIT-1.3.9.md。

本版正式构建保留 macOS15/Xcode16.4；Theos cfba89a53a05b4a1b822121158acc3669c20602f，iOS16.5 SDK 0222fd5413cf4b9af096f37b4621afa2688572f7。实际工具版本记录于 BUILD_ENVIRONMENT.txt。

检查顺序：57项Python、C协议、plist/shell、Foundation参数/runtime和27组生产核心→源码编译链接签名→数值属主/时间规范化→包结构、arm64e PAC00 ABI、CodeDirectory完整性、源码资源对照及实际包反例→本运行artifact→草稿附件完整校验→正式公开及Latest复核。

源码提交以 SOURCE_COMMIT 为准，75个跟踪路径以 SOURCE_FILES.sha256 为准；构建运行和源码commit追加到Release正文。SOURCE_TESTS.txt/verification.txt记录真实执行输出；不能把本说明当作尚未完成运行的成功证明。

附件为DEB、AUDIT/BUILD/RELEASE文档、SOURCE_COMMIT、SOURCE_FILES.sha256、SOURCE_TESTS.txt、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、verification.txt、VERSION、verify_release.py、SHA256SUMS，共13项。清单覆盖自身之外12项；公开资产digest再覆盖SHA256SUMS。源码zip/tar.gz对应同一tag。

verify_release.py现在必须选择 --stable 或 --prerelease；本版两阶段都使用 --stable。公开属性draft=false、prerelease=false，并显式设为Latest；该属性不是目标真机验收证明。

Git源码本机构建：sh scripts/check.sh；设置 THEOS 为RootHide Theos绝对路径；sh build.sh roothide。源码ZIP无Git元数据时需显式设置SOURCE_DATE_EPOCH。不要安装失败验证留下的包。

未连接目标设备。PAC执行、实际私有API、温控恢复、watchdog、续航与第三方热控联用均须按审计报告真机验收。
