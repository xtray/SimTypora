import SwiftUI

@main
struct SimTyporaApp: App {
    @StateObject private var document = MarkdownDocument()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(document)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建") {
                    document.content = ""
                    document.fileURL = nil
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("打开...") {
                    document.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("保存") {
                    document.saveFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button("另存为...") {
                    document.saveFileAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
