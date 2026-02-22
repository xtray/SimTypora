import Foundation

private enum TestFailure: Error {
    case failed(String)
}

private func expectTrue(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TestFailure.failed(message)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure.failed("\(message)\nexpected: \(expected)\nactual:   \(actual)")
    }
}

private func run(_ name: String, _ body: () throws -> Void) throws {
    do {
        try body()
        print("[PASS] \(name)")
    } catch {
        print("[FAIL] \(name): \(error)")
        throw error
    }
}

private func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var start = haystack.startIndex
    while let range = haystack.range(of: needle, range: start..<haystack.endIndex) {
        count += 1
        start = range.upperBound
    }
    return count
}

#if MARKDOWN_HTML_TEST_MAIN
@main
struct MarkdownHTMLRendererTests {
    static func main() {
        do {
            try run("unordered list uses one list wrapper") {
                let html = MarkdownHTMLRenderer.shared.renderFragment("- first\n- second\n- third")
                try expectEqual(occurrences(of: "<ul>", in: html), 1, "unordered items should be grouped into one <ul>")
                try expectEqual(occurrences(of: "<li", in: html), 3, "unordered list should contain one <li> per item")
            }

            try run("ordered list uses one list wrapper") {
                let html = MarkdownHTMLRenderer.shared.renderFragment("1. first\n2. second")
                try expectEqual(occurrences(of: "<ol>", in: html), 1, "ordered items should be grouped into one <ol>")
                try expectEqual(occurrences(of: "<li", in: html), 2, "ordered list should contain one <li> per item")
            }

            try run("renderer includes compact spacing rules") {
                let html = MarkdownHTMLRenderer.shared.renderFragment("- item")
                try expectTrue(
                    html.contains(".markdown-body > :first-child { margin-top: 0 !important; }"),
                    "first child margin reset should avoid extra top gaps"
                )
                try expectTrue(
                    html.contains(".markdown-body > :last-child { margin-bottom: 0 !important; }"),
                    "last child margin reset should avoid extra bottom gaps"
                )
                try expectTrue(
                    html.contains(".markdown-body ul,"),
                    "list spacing rule should exist"
                )
                try expectTrue(
                    html.contains("margin: 0.25em 0;"),
                    "lists should use tighter vertical margins"
                )
                try expectTrue(
                    html.contains(".markdown-body li { margin: 0.1em 0; }"),
                    "list items should use compact spacing"
                )
            }

            print("All markdown HTML renderer tests passed")
        } catch {
            exit(1)
        }
    }
}
#endif
