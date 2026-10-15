# CSVCore 公共契约 v1（M1.T1）

公共源码：`Sources/CSVCore/CSVTypes.swift`、`CSVInterfaces.swift`。T1冻结下列语义和签名，后续新增功能遵循该契约；确需破坏接口先记录迁移约定，不静默修改其他模块假设。

## 值与序列

- `CSVCell.literal`是解码、去除CSV外围引用及转义后的单元格内容，包含原始前导零、空格、小数/指数写法、任意Unicode；不是原始文件字节或包含外围引号的token。默认写出保留此字面，不承诺逐字节保持引用风格。
- `decimal: Decimal?`为独立、可选的准确数值解释。不能经过Double，不能把Decimal舍入后的结果误标为准确；超出Decimal精度/范围时置nil，但literal必须保留。改值创建新Cell，避免旧数值解释随literal修改而失配。T2负责准确识别及验证。
- `CSVTable.rows`值类型，保留不齐列；空文件=零行；空白物理行=一行一个空Cell；尾分隔符=最后显式空Cell；尾换行不额外增加一行。缺失字段与显式空值在模型中不同，没有SQL null语义。最大行宽定义columnCount。
- `firstRowAsHeader`只影响解释，首行仍保留在rows[0]，Reader不得移除；Writer不得重复添加。T4在UI适配层用稳定UUID标识行列，维护UUID至存储索引映射，重排/撤销一起更新；不以当前显示索引作为稳定身份。

## 配置与错误

- 默认UTF-8、逗号、双引号双写转义、点小数、无表头。分隔符与引用均为单个非换行Unicode scalar（Tab允许），引用与分隔符不能相同；backslash模式不允许反斜杠作分隔符或引用。读写入口必须先validate。
- `CSVEncoding`前18个case对应旧手选编码，额外gb18030仅为检测候选，明确区别gbk。T2编码映射、严格编解码/不支持错误及T3探测均不能静默用替代字符降级。T1声明类型不等于已验证19个编码可用。
- `CSVSerialization`独立记录第一种观测到的行尾、末尾换行及BOM。混合行尾允许读，写时按选定行尾统一；引用内换行属于literal，不计作记录终止。零字段行（[]）无法无损表示，Writer明确失败；不齐列补空仍只作用于输出。空文件与单空Cell序列化会有歧义，Writer应对单空Cell引用（无引用模式无法表达则失败），不能默默丢行。UTF16/32无BOM时按显式端序解码；通用utf16/32默认采用大端、BOM优先。编码/BOM冲突明确报错。
- `CSVSourceLocation`为1起始物理行及Unicode scalar列；换行计行、CRLF计一次，不是字节偏移，也不是数据表索引。编码失败的row/column若可定位同样从1起始；不可定位为nil。
- `CSVError`区分配置、解码、CSV结构、输出编码、列排列、不支持编码及尚未实现。非法引用/孤立转义必须失败，无部分成功后覆盖原文件。

## 模块接入约定

- T2提供`CSVReader: CSVReading`、`CSVWriter: CSVWriting`，均无文件系统副作用。Reader输入Data和显式配置，返回表、配置及序列信息。Writer在完整编码成功后返回Data，不改输入。
- Writer的columnOrder为nil或0..<columnCount的完整排列，重复、缺失、越界须报invalidColumnOrder；按显示顺序输出。不齐行按最大列数补空仅发生在输出，不改模型。默认`literalPolicy=.preserve`；转换小数符号必须显式`.convertDecimalMark(from:)`，仅转换符合源小数语法的字面，不经Double或Decimal重构超长数字、不去前导零。目标小数符由configuration决定。
- T3提供`CSVDetector: CSVDetecting`，实现可注入`any CSVReading`，供单测替身隔离T2依赖。输入Data和有序编码候选；输出按分数降序的配置候选、原因和歧义标识；分数只是排序，不是概率。空候选明确表示无解，不擅自选有损编码；错误与歧义由UI显示供手动校正。
- T4维护输入原字节与已编辑状态，重新解释格式不得静默丢编辑；通过上述协议接业务。T5先拿到完整编码Data再原子保存；转换不得悄悄更改当前URL和输入配置。
- T1的ContractTests只验证字面存储、配置冲突和外部消费公共协议可编译，协议替身不证明Reader/Writer/Detector已经实现；业务测试由T2/T3承接。
