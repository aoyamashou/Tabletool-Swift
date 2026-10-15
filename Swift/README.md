# TableTool Swift 本地开发版

独立Swift/AppKit文档应用，保留旧`Table Tool.xcodeproj`。核心默认保留前导零、超长数字和Unicode单元格字面；数字解释与存储分离。自动格式检测有歧义时可在编辑前手动纠正。

## 构建与运行

建议部署目标macOS13，仅在本机arm64 macOS27.0.1 / Xcode27.0实测；不要把部署目标当兼容性验证。无外部依赖或登录账号。仓库根目录执行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/m1-final-verify.sh
open -n "$PWD/tasks/M1.T5-build/DerivedData/Build/Products/Debug/TableToolSwift.app"
```

验证脚本构建新应用，使用不涉及钥匙串身份的本地ad-hoc签名应用现有沙盒entitlements，运行核心与保存集成回归，执行正/负预检。不安装到Applications，不替换旧应用，不发布、不推送、不改系统开发目录。应用使用独立bundle标识`cc.kneo.TableTool2026.Swift`。签名仅供本机调试，未公证，不是正式分发包。

关闭发起终端后窗口应继续运行；该行为与菜单/键盘/拖放/系统面板的真实验收在M2执行。固定本地提交hash由`tasks/M1-fixed-commit.txt`给出；独立验收使用已构建应用路径及`tasks/M2-acceptance-checklist.md`，验收期间禁止改源码或替换产物。

## 操作

- 新建为3列1行。网格可编辑，菜单/按钮支持行列插入删除、表头编辑、撤销重做。列拖动改变显示顺序，保存按显示顺序写出。
- 格式栏控制输入编码/分隔符（Tab填`\t`）/引用/小数/首行表头。已有编辑时拒绝从旧输入字节重新解释；成功保存刷新快照，之后可安全重读最新保存内容。
- 文件菜单“保存”使用NSDocument安全写入；“另存为”更换当前文件位置并保留原文件；“转换格式并导出副本”选择目标编码/分隔符/引用/小数/行尾，保留当前文档URL和输入配置，不允许覆盖当前文件。不能表达字符、只读路径及取消都不会写出部分结果。
- 复制/粘贴使用引用TSV（Tab分列、LF分行、双引号双写），含Tab/换行的字段保持内容。粘贴按显示列序插入新行，超宽时扩列。支持表内行移动及对外文本拖出。

## 验证与边界

核心55项（基础契约3、读写24、检测28），保存集成19项；最终机器证据见`tasks/M1-evidence/`与`tasks/M1.T5-report.md`。本次业务回归完成后，单源文件探针入口编译参数曾阻断预检，补完历史记录见报告，旧失败日志保留。预检不等于真实GUI验收。

不提供公式、样式、排序、联网或数据库；不承诺未测大文件性能。默认保存保证单元格字面，外围引用和混合行尾不承诺逐字节一致；缺少的字段仅输出时补空。没有列的行、无引用格式不能表达的字段会明确失败。编码严格核验，不用替代字符降级。

核心公共契约见`CSVCore/CONTRACT.md`；应用源代码在`TableToolApp/`，本地Package在`CSVCore/`。保留仓库MIT License及原作者归属。
