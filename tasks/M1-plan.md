# M1：Swift原生ARM实现队列

当前开发codex-oracle；项目/源码根目录为/Users/corndog/dev/tabletool2026/TableTool2026。M0最终评审通过，工具环境完整Xcode27.0、macOS27.0.1、原生arm64；用户已授权的Git署名已仅配置本仓库，origin匹配https://github.com/aoyamashou/TableTool2026。不要推送或替换现用应用。

## 启动条件

当前未开始M1。依AGENT_PROTOCOL.md第8.3节，M0结束先向用户申请Reset Session & Restart（不要Full Reset）。用户完成后或明确免重置继续后，由Neo重新读取三份协议/状态文件并派发M1.J1预检与M1.T1。不能仅因todo行存在即开工。所有范围细节以M0.T1-report.md的A01–A11及M0.R1-review.md最终决策为准。

## 任务与完成标准

| ref | owner | 目标和通过条件 |
|---|---|---|
| M1.J1 | tank | 按Neo提供的精确命令执行完整Xcode路线预检；exit0及逐项日志，使用进程DEVELOPER_DIR，不改系统/全局配置 |
| M1.T1 | dev | 定义CSVCore公共类型、原始字面/Decimal、配置、错误与序列语义；创建纯Swift核心及Swift AppKit文档应用骨架；新arm64目标可构建、公共接口能编译，不桥接旧CSV业务。接口/构建说明落文件供后续模块复用，旧工程保留 |
| M1.T2 | dev | 实现Reader/Writer和核心回归；覆盖A04/A06及A09核心读写部分，原13项读取用例、编码/引用/行尾/空值/不齐列、错误失败、前导零/大整数/Unicode、写出无副作用及往返；锁定接口后可与T3/T4并行 |
| M1.T3 | dev | 实现检测器、格式/编码候选与原20项推断回归；候选不确定时可手动校正，兼容已有GBK等样本，不静默用替代字符；依赖T1接口，集成时再接T2 |
| M1.T4 | dev | Swift NSDocument/NSTableView、菜单与格式控件、编辑/行列/UndoRedo/复制粘贴/拖动/生命周期；覆盖A02/A05/A07/A08/A10，可在T1接口冻结后与核心并行，最终接读写与检测模块 |
| M1.T5 | dev | 整合安全保存/另存/转换，配置/表头/显示顺序往返、编码失败与取消不改原文件；arm64.app构建及本地启动说明、所有适用测试与最终预检证据，产物锁定提交，为M2独立验收准备账号无需求的启动方法/样本/清单 |

## 共同边界

- 新业务使用Swift；原始字面无损与保存安全优先。原项目没有的公式、样式、联网、排序、数据库不扩展。
- 以arm64主机实测为准；macOS13是建议部署下限，未在13实测不得宣称兼容已验证。
- dev负责代码与handoff，Git/构建/运行与测试命令直接派tank；需要新job行时向Neo ask；不由Neo代写代码或动手测试。
- 里程碑末产物落文件，board无doing后执行复盘与重置申请。M2另派独立验收subagent，输入仅固定hash、启动/样本文件路径和A01–A11判定清单，不给实现上下文。
