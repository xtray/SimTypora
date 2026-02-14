import SwiftUI
import AppKit
import UniformTypeIdentifiers

class MarkdownDocument: ObservableObject {
    @Published var content: String = "# 欢迎使用 SimTypora\n\n这是一个简洁的 Markdown 编辑器。\n\n## 功能特点\n\n- **实时预览** - 所见即所得\n- **简洁界面** - 专注于写作\n- **完整语法** - 支持标准 Markdown\n\n### 代码块\n\n```swift\nfunc hello() {\n    print(\"Hello, World!\")\n}\n```\n\n### 列表\n\n- 项目1\n- 项目2\n  - 子项目\n\n### 引用\n\n> 这是一段引用文本\n\n### 链接与图片\n\n[访问 GitHub](https://github.com)\n\n---\n\n开始你的写作吧！"
    
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
