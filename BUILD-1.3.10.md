# Powercuff 1.3.10 构建及正式发布记录

目标：iPhone15,3 / iOS16.5(20F66) / RootHide Dopamine3.0.4，iphoneos-arm64e。基线v1.3.9提交92aedbb5fec9a9973e1a45af7c6df22d131abaa8；旧DEB SHA-256为6ec6e3bfc867b1851c2b063135989837cbff29c2d34b6140d1f10f8c77810249。保持旧包和标签不变。

本版修复半初始化通信/清理及plist类型混淆，新增重复键拒绝、实际构造函数故障回归。旧版基线运行41108411474中57项Python和27组核心通过，新增构造函数测试在test_startup.m:212的禁止半初始化发布断言失败，退出134并阻止发布。首次41107204638是测试函数名与系统头冲突，不能算作生产故障复现。详细因果与限制见AUDIT-1.3.10.md。

GitHub正式构建采用macOS15/Xcode16.4，RootHide Theos cfba89a53a05b4a1b822121158acc3669c20602f，iOS16.5 SDK 0222fd5413cf4b9af096f37b4621afa2688572f7。实际runner/工具版本记录于BUILD_ENVIRONMENT.txt；不宣称完全固定全部Homebrew依赖。

门禁顺序：63项Python、C协议、shell/plist、Foundation参数/runtime、27组生产核心、9组constructor→当前源码编译链接签名→归档属主/时间规范化→结构、PAC00 ABI、CodeDirectory完整性、受审源码资源对照及实际包反例→同运行artifact→草稿全部附件校验→正式公开/非公测/Latest复核。

源码提交以SOURCE_COMMIT为准，81个跟踪路径以SOURCE_FILES.sha256为准。SOURCE_TESTS.txt/verification.txt记录实际输出；成功运行与commit由发布流程追加到Release正文。本说明不预填尚未完成的运行成功、DEB大小或哈希。

13项附件：DEB、AUDIT/BUILD/RELEASE文档、SOURCE_COMMIT、SOURCE_FILES.sha256、SOURCE_TESTS.txt、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、verification.txt、VERSION、verify_release.py、SHA256SUMS。SHA256SUMS覆盖其余12项，GitHub资产digest还覆盖清单自身。源码zip/tar.gz来自同一tag。

只有release/powercuff-1.3.10的push可在build成功后发布；既有Release/tag不覆盖。显式--stable核对草稿/公开两阶段，draft=false、prerelease=false并设Latest。正式属性不代表目标真机已实测。

本机构建需要Python3.9+和RootHide Theos：先sh scripts/check.sh，再设置THEOS并sh build.sh roothide。无Git元数据的源码ZIP须显式SOURCE_DATE_EPOCH。不要安装失败校验留下的原包。交付独立核对artifact摘要、81项源码来源、公开DEB与artifact字节一致，并重新验证包及其反例。

未连接目标设备，真实私有API、PAC、LPM实机事件、温控恢复、watchdog、续航/热控联用按当前审计表待验。升级后人工注销一次；自动重启跳过/失败则通过越狱应用重启用户空间。
