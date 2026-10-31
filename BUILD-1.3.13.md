# Powercuff 1.3.13 构建与正式发行记录

正式基线v1.3.12：源码eb4f83a3a3b7f6af30eadb90709d4bb05b70c03d，88项来源文件；DEB18748字节，SHA-256 7a484f3a279d4272089cd8e26de59fae5990f1fc03b6a15730229c33f12f3613。main 52ed33a58ee850711fc642e7a3bcfb85abc0af8e与标签树完全相同。

本轮修复ar大小和名称物理字段与dpkg不一致：4种非法大小、5种非法名称的完整DEB副本旧检查均接受、dpkg均退出2。现在转换前严格检查字段，规范化共享入口，异常输入不改写。原公开v1.3.12仍通过新检查。完整因果和逐项架构/参数/设备边界见AUDIT-1.3.13.md。

五份运行时代码、两设置/五档/通信预算、三份维护脚本不变；增加异常偏好通过生产核心回退Off与修正后恢复的集成检查。新包由当前源码clean完整编译，不复用旧dylib。

工具链保持macOS15/Xcode16.4、RootHide Theos cfba89a53a05b4a1b822121158acc3669c20602f、iOS16.5 SDK 0222fd5413cf4b9af096f37b4621afa2688572f7；固定Node24 Actions、Ubuntu24.04发布。实际环境写入BUILD_ENVIRONMENT.txt，runner/Homebrew不是完整锁定，不承诺跨构建逐字节复现。

门禁顺序：78项Python/C协议/shell/plist→Foundation偏好/runtime、30组生产核心、9组实际构造函数→clean编译/链接/签名→规范化前完整ar/tar检查→数值属主/时间规范化→结构/PAC00/签名页及特殊槽/源码对照→7组签名破坏、33种完整DEB变异、14次无源码反例与9次ar规范化拒绝检查→同运行artifact→草稿13附件契约/全哈希→正式公开、Latest及tag复核。实际结果见SOURCE_TESTS.txt和verification.txt，发行正文追加真实运行/提交/摘要。

SOURCE_COMMIT标识实际源码，SOURCE_FILES.sha256覆盖91项跟踪路径。13附件：DEB、当前AUDIT/BUILD/RELEASE、SOURCE_COMMIT、SOURCE_FILES.sha256、SOURCE_TESTS.txt、TOOLCHAIN_REFS、BUILD_ENVIRONMENT.txt、verification.txt、VERSION、verify_release.py、SHA256SUMS。清单覆盖其余12项，GitHub digest覆盖全部13项；旧tag/Release不覆盖。

交付独立核对artifact ZIP摘要/大小/安全成员、全部91项源码与文档/验证器字节、78/30/9实际输出；再次下载公开DEB并与artifact逐字节比较，重新执行完整包及变异检查。PR和主分支另行通过构建后同步。

本地：Python3.9+，sh scripts/check.sh；设置THEOS后sh build.sh roothide。源码ZIP无Git时设置SOURCE_DATE_EPOCH；校验失败留下的包不可安装。安装升级后人工注销；PAC、私有温控、watchdog、续航及联用安全仍待目标iPhone15,3/iOS16.5/RootHide Dopamine3.0.4真机确认。
