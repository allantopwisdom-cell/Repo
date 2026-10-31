# Powercuff 1.3.12 构建与正式发行记录

基线正式v1.3.11：源码dfa89980a5b2cf3f2180f83199145c6f8558360e；DEB18744字节，SHA-256 9eaa6d79d17054d4a9dbc48a86777a2d1a8505dc59da9b713f16545ec5ea2a20。新分支从main 9d6fd72603a641736469f793375c1aa9270bbdfe建立；该树与正式基线一致。

修复按后缀解压后再次自动探测压缩（旧验证接受、dpkg拒绝的4种真实DEB样本），补充tar完整块/两结束块/全零尾部检查，并将同一检查前置到规范化步骤。拒绝附加非零内容和拼接归档；不声称这些内容会被dpkg安装。旧公开原包仍通过新验证。详见AUDIT-1.3.12.md的证据和边界。

五份运行时源码、两设置/五档/通信预算、三份维护脚本不变；新增永久发布失败及握手中对象释放的生产核心回归。新包从本轮源码clean全量编译，不复用旧dylib，不以源码审计代替设备验收。

工具链：macOS15/Xcode16.4；RootHide Theos cfba89a53a05b4a1b822121158acc3669c20602f；iOS16.5 SDK 0222fd5413cf4b9af096f37b4621afa2688572f7。固定Node24 Actions，Ubuntu24.04发布。实际环境写入BUILD_ENVIRONMENT.txt；runner/Homebrew版本可能变化，不承诺完整逐字节复现。

门禁：74项Python/C协议/shell/plist→Foundation偏好/runtime、29组核心和9组实际构造函数→clean编译/签名→归档前检查与数值属主/时间规范化→结构/PAC00/签名代码页和特殊槽/源码对照→7组签名破坏、24种真实DEB变异和5次无源码反例→同运行artifact→13附件草稿契约及哈希→公开正式、Latest与tag复核。实际执行结果见SOURCE_TESTS.txt和verification.txt。

SOURCE_COMMIT指向实际源码；SOURCE_FILES.sha256覆盖88项跟踪文件。13附件为DEB、当前AUDIT/BUILD/RELEASE、SOURCE_COMMIT、SOURCE_FILES.sha256、SOURCE_TESTS.txt、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、verification.txt、VERSION、verify_release.py、SHA256SUMS。清单覆盖其余12项，GitHub digest覆盖全部13项；不覆盖旧tag或附件。

交付再独立核对ZIP摘要/安全成员、88项源码、文档/验证器/工具链字节、74/29/9实际记录；重新下载公开DEB，逐字节对照artifact并运行完整包及变异检查。PR/主分支另行构建后同步。

本地：Python3.9+，sh scripts/check.sh；设置THEOS后sh build.sh roothide。源码ZIP无git时显式设置SOURCE_DATE_EPOCH。验证失败留下的包不可安装。安装升级后人工注销，必要时越狱应用重启用户空间；PAC、实际温控、watchdog和续航须按审计表在目标机验收。
