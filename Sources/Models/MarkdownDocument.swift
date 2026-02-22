import SwiftUI
import AppKit
import UniformTypeIdentifiers

class MarkdownDocument: ObservableObject {
    @Published var content: String = """
# SimTypora Markdown Demo

> 启动后默认展示这份完整语法笔记，用于验证渲染效果。

## 1. 标题层级

### H3 标题

#### H4 标题

## 2. 强调与行内样式

这是 **粗体**、*斜体*、~~删除线~~、`行内代码` 的组合示例。

支持链接：[OpenAI](https://openai.com) 和 [GitHub](https://github.com)。

## 3. 列表

- 无序列表 A
- 无序列表 B
  - 二级子项 B.1
  - 二级子项 B.2
- 无序列表 C

1. 有序列表 1
2. 有序列表 2
3. 有序列表 3

## 4. 任务列表

- [x] 完成 Markdown 渲染框架
- [x] 接入表格与代码块
- [ ] 增加导出能力

## 5. 引用

> Markdown 的核心价值是可读性与可移植性。
> 
> 这是一段多行引用。

## 6. 代码块

```swift
struct User: Codable {
    let id: Int
    let name: String
}

func greet(_ user: User) {
    print("Hello, \\(user.name)")
}
```

```bash
xcodebuild \\
  -project SimTypora.xcodeproj \\
  -scheme SimTypora \\
  -configuration Debug
```

## 7. 表格（含对齐）

| 功能模块 | 状态 | 说明 |
| --- | :---: | ---: |
| 标题/段落 | 已完成 | 基础排版 |
| 列表/任务 | 已完成 | GFM 常见语法 |
| 代码块 | 已完成 | 支持 fenced code |
| 表格 | 已完成 | 左/中/右对齐 |

## 8. 分隔线

---

## 9. 快捷键速览

- Cmd/Ctrl + C / V / X：复制 / 粘贴 / 剪切
- Cmd/Ctrl + B：粗体（**）
- Cmd/Ctrl + I：斜体（*）
- Cmd/Ctrl + Shift + X：删除线（~~）
- Cmd/Ctrl + K：行内代码（`）
- Cmd/Ctrl + 1 / 2 / 3：标题 H1 / H2 / H3（行级切换）
- Cmd/Ctrl + Shift + 7 / 8 / 9：有序列表 / 无序列表 / 引用（行级切换）

以上内容用于启动即验收 Markdown 渲染与快捷键行为。
"""

    @Published var fileURL: URL?

    private var isModified: Bool = false

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText, UTType(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                content = try String(contentsOf: url, encoding: .utf8)
                fileURL = url
            } catch {
                print("Error opening file: \(error)")
            }
        }
    }

    func saveFile() {
        if let url = fileURL {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Error saving file: \(error)")
            }
        } else {
            saveFileAs()
        }
    }

    func saveFileAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "untitled.md"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                fileURL = url
            } catch {
                print("Error saving file: \(error)")
            }
        }
    }
}
