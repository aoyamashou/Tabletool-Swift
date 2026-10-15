<img src="Artwork/icon.png" width="96" height="96" alt="Tabletool Swift">

# Tabletool Swift

**Tabletool Swift** 是用 Swift / AppKit 重写的 [Table Tool](https://github.com/jakob/TableTool)（原版 1.2.1）：一个简单、原生的 macOS CSV 编辑器，面向 Apple Silicon。

![Tabletool Swift](Artwork/Screenshots/TabletoolSwift.png)

## 特点

- **自动识别格式**：编码（UTF-8/16/32、Shift-JIS、EUC-JP、ISO-2022-JP、GBK、GB18030、Windows-125x、MacRoman 等）、分隔符、引号、小数点、是否有表头；有歧义时可手动纠正。
- **不改你的数据**：保留前导零、超长数字和 Unicode 单元格原文，数字解释与存储分离。
- **编辑**：单元格编辑、在上/下插入行、在左/右插入列、删除、列拖动重排、撤销重做、复制粘贴（含引用 TSV）。
- **转换**：另存为，或转换编码、分隔符、引号、小数点、行尾并导出副本。
- **够快**：5MB 的 CSV 约 1 秒打开。

## 构建与运行

需要 macOS 13+、Xcode，无第三方依赖。

```bash
open TabletoolSwift.xcodeproj      # 在 Xcode 中运行
# 或命令行构建
xcodebuild -project TabletoolSwift.xcodeproj -scheme TabletoolSwift -configuration Release build
```

## 测试

```bash
cd CSVCore && swift test
```

核心库的接口约定见 [CSVCore/CONTRACT.md](CSVCore/CONTRACT.md)。

## 范围

只做 CSV 编辑：不提供公式、样式、排序、联网或数据库。

## 致谢与许可

Table Tool 由 [Sandro Peham](https://github.com/SandroPeham)、[Andreas Aigner](https://github.com/aigi) 和 [Jakob Egger](https://github.com/jakob) 创作；本仓库是其 Swift 重写版本，沿用 [MIT 许可](LICENSE)。
