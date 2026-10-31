# Powercuff 1.3.11 构建与正式发行记录

目标：iPhone15,3 / iOS16.5(20F66) / RootHide Dopamine3.0.4，iphoneos-arm64e。基线正式v1.3.10为93c65728bd6872500d3c6f5a74d3b2bd2b206418，DEB18742字节，SHA-256为800caaeba29e2c3fd3fec39ce20bb99af0fd5b03b9844e5a20ea20b29f75ba83。新分支从已同步该源码及Node24维护的main ccfa07017604e1002f7ab4dfd472805d507e3064建立。

本轮修复control单段/大小写重复字段/物理行解析、无源码目录时的精确依赖/冲突门禁，以及独立13项发行必备契约。旧解析器新增5项方法产生16个失败子用例；发行缺项/额外项新增检查产生5个失败子用例。实际旧DEB临时副本插空行，旧完整校验通过但dpkg只读解析退出2。详细因果见AUDIT-1.3.11.md。

五份生产源码、档位/门控/重试预算及维护脚本保持v1.3.10字节不变；新DEB由本轮源码全量重编译，不复用旧dylib。没有新增真机稳定性证据。

GitHub macOS15/Xcode16.4、RootHide Theos cfba89a53a05b4a1b822121158acc3669c20602f、iOS16.5 SDK 0222fd5413cf4b9af096f37b4621afa2688572f7；主Actions固定Node24提交、发布runnerUbuntu24.04。实际runner/Homebrew/编译器记录于BUILD_ENVIRONMENT.txt；不承诺完整工具链逐字节可复现。

门禁顺序：70项Python、C协议、shell/plist、Foundation参数/runtime、27组核心及9组实际构造函数→clean编译/链接/签名→归档属主/时间规范化→结构/PAC00/CodeDirectory/来源对照及真实DEB变异拒绝→同运行artifact→草稿13项契约和全哈希校验→正式公开、非公测、Latest及tag复核。

SOURCE_COMMIT为实际源码，SOURCE_FILES.sha256覆盖85路径；SOURCE_TESTS.txt和verification.txt是实际执行记录。Release正文追加实际成功运行/提交/哈希，本说明不预填尚未存在的成功或新DEB摘要。

13附件：DEB、当前AUDIT/BUILD/RELEASE、SOURCE_COMMIT、SOURCE_FILES.sha256、SOURCE_TESTS.txt、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、verification.txt、VERSION、verify_release.py、SHA256SUMS。清单覆盖其余12项；GitHub digest覆盖包括清单在内全部13项；ZIP/TAR源码来自同tag。草稿和公开均强制完整契约，修改本地/远端集合再重算清单不能绕过。

交付独立核对artifact摘要/大小、安全解压、85项来源、报告和验证器字节、70/27/9记录及公开DEB与artifact相同；本地再次执行完整包/实际变异验证。

本地需要Python3.9+及RootHide Theos；先sh scripts/check.sh，设置THEOS后sh build.sh roothide。源码ZIP无Git元数据需显式SOURCE_DATE_EPOCH。勿安装失败校验留下的包。安装升级后人工注销；必要时通过越狱应用重启用户空间。PAC、真实温控、watchdog及续航按审计表真机待验。
