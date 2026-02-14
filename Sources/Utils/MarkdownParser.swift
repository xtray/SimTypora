import Foundation
import AppKit

class MarkdownParser {
    
    static let shared = MarkdownParser()
    
    private let defaultFont = NSFont.systemFont(ofSize: 14)
    private let defaultParagraphStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        return style
    }()
    
    func parse(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        
        var inCodeBlock = false
        var codeBlockContent = ""
        var inList = false
        var listIndent = 0
        
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    let codeAttr = formatCodeBlock(codeBlockContent)
                    result.append(codeAttr)
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }
            
            if inCodeBlock {
                codeBlockContent += (codeBlockContent.isEmpty ? "" : "\n") + line
                continue
            }
            
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            
            var processedLine = line
            
            if let (indent, isOrdered) = getListInfo(processedLine) {
                let listAttr = formatListItem(processedLine, indent: indent, isOrdered: isOrdered, lineNumber: countPreviousListItems(lines: Array(lines[0..<index]), indent: indent))
                result.append(listAttr)
                continue
            }
            
            if processedLine.hasPrefix("#") {
                let headingAttr = formatHeading(processedLine)
                result.append(headingAttr)
                continue
            }
            
            if processedLine.hasPrefix(">") {
                let quoteAttr = formatBlockquote(processedLine)
                result.append(quoteAttr)
                continue
            }
            
            if processedLine == "---" || processedLine == "***" || processedLine == "___" {
                let hrAttr = formatHorizontalRule()
                result.append(hrAttr)
                continue
            }
            
            let normalAttr = formatInlineMarkdown(processedLine)
            result.append(normalAttr)
        }
        
        return result
    }
    
    private func getListInfo(_ line: String) -> (indent: Int, isOrdered: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if let _ = trimmed.first, trimmed.first?.isNumber == true {
            let parts = trimmed.split(separator: ".", maxSplits: 1)
            if parts.count == 2 {
                return (line.distance(from: line.startIndex, to: line.index(where: { !$0.isWhitespace })!), false)
            }
        }
        
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return (line.distance(from: line.startIndex, to: line.index(where: { !$0.isWhitespace })!), false)
        }
        
        return nil
    }
    
    private func countPreviousListItems(lines: [String], indent: Int) -> Int {
        var count = 0
        for line in lines.reversed() {
            let lineIndent = line.distance(from: line.startIndex, to: line.index(where: { !$0.isWhitespace }) ?? line.endIndex)
            if lineIndent == indent {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") || (trimmed.first?.isNumber == true && trimmed.contains(". ")) {
                    count += 1
                } else {
                    break
                }
            }
        }
        return max(1, count)
    }
    
    private func formatHeading(_ line: String) -> NSAttributedString {
        var level = 0
        for char in line {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }
        
        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        let fontSize: CGFloat
        let fontWeight: NSFont.Weight
        
        switch level {
        case 1:
            fontSize = 28
            fontWeight = .bold
        case 2:
            fontSize = 24
            fontWeight = .bold
        case 3:
            fontSize = 20
            fontWeight = .semibold
        case 4:
            fontSize = 18
            fontWeight = .semibold
        case 5:
            fontSize = 16
            fontWeight = .medium
        default:
            fontSize = 14
            fontWeight = .medium
        }
        
        let font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 16
        style.paragraphSpacing = 8
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ]
        
        return NSAttributedString(string: text, attributes: attributes)
    }
    
    private func formatListItem(_ line: String, indent: Int, isOrdered: Bool, lineNumber: Int) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let text: String
        if isOrdered {
            let parts = trimmed.split(separator: ".", maxSplits: 1)
            text = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : trimmed
        } else {
            text = String(trimmed.dropFirst(2))
        }
        
        let indentSpace = String(repeating: " ", count: indent)
        let bullet = isOrdered ? "\(lineNumber). " : "• "
        
        let font = NSFont.systemFont(ofSize: 14)
        let style = NSMutableParagraphStyle()
        style.headIndent = CGFloat(indent + 2) * 8
        style.firstLineHeadIndent = CGFloat(indent) * 8
        style.paragraphSpacing = 4
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ]
        
        return NSAttributedString(string: indentSpace + bullet + text, attributes: attributes)
    }
    
    private func formatBlockquote(_ line: String) -> NSAttributedString {
        let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        
        let font = NSFont.systemFont(ofSize: 14)
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 24
        style.headIndent = 24
        style.paragraphSpacing = 8
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ]
        
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "│ ", attributes: [
            .font: font,
            .foregroundColor: NSColor.systemBlue,
            .paragraphStyle: style
        ]))
        result.append(NSAttributedString(string: text, attributes: attributes))
        
        return result
    }
    
    private func formatCodeBlock(_ code: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 16
        style.headIndent = 16
        style.paragraphSpacing = 8
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.quaternaryLabelColor,
            .paragraphStyle: style
        ]
        
        return NSAttributedString(string: code + "\n", attributes: attributes)
    }
    
    private func formatHorizontalRule() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 16
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 1),
            .foregroundColor: NSColor.separatorColor,
            .paragraphStyle: style
        ]
        
        return NSAttributedString(string: "────────────────────", attributes: attributes)
    }
    
    private func formatInlineMarkdown(_ line: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: line)
        
        let fullRange = NSRange(location: 0, length: result.length)
        
        result.addAttribute(.font, value: defaultFont, range: fullRange)
        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        result.addAttribute(.paragraphStyle, value: defaultParagraphStyle, range: fullRange)
        
        processBoldItalic(result, line: line)
        processCode(result, line: line)
        processLinks(result, line: line)
        
        return result
    }
    
    private func processBoldItalic(_ result: NSMutableAttributedString, line: String) {
        let boldItalicPattern = "\\*\\*\\*(.+?)\\*\\*\\*|__(.+?)___"
        applyPattern(result, line: line, pattern: boldItalicPattern) { range, match in
            if let matchRange = range {
                let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
                result.addAttribute(.font, value: font, range: matchRange)
            }
        }
        
        let boldPattern = "\\*\\*(.+?)\\*\\*|__(.+?)__"
        applyPattern(result, line: line, pattern: boldPattern) { range, match in
            if let matchRange = range {
                let font = NSFont.systemFont(ofSize: 14, weight: .bold)
                result.addAttribute(.font, value: font, range: matchRange)
            }
        }
        
        let italicPattern = "\\*(.+?)\\*|_(.+?)_"
        applyPattern(result, line: line, pattern: italicPattern) { range, match in
            if let matchRange = range {
                let font = NSFont.systemFont(ofSize: 14, weight: .regular).italic()
                result.addAttribute(.font, value: font, range: matchRange)
            }
        }
        
        let strikethroughPattern = "~~(.+?)~~"
        applyPattern(result, line: line, pattern: strikethroughPattern) { range, match in
            if let matchRange = range {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            }
        }
    }
    
    private func processCode(_ result: NSMutableAttributedString, line: String) {
        let pattern = "`([^`]+)`"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsLine = line as NSString
        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
        
        for match in matches.reversed() {
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            result.addAttribute(.font, value: font, range: match.range)
            result.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: match.range)
        }
    }
    
    private func processLinks(_ result: NSMutableAttributedString, line: String) {
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsLine = line as NSString
        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
        
        for match in matches {
            if match.numberOfRanges >= 3 {
                let textRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                
                if let url = URL(string: nsLine.substring(with: urlRange)) {
                    result.addAttribute(.link, value: url, range: match.range)
                    result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: match.range)
                    result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
                }
            }
        }
    }
    
    private func applyPattern(_ result: NSMutableAttributedString, line: String, pattern: String, handler: (NSRange?, String?) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsLine = line as NSString
        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
        
        for match in matches {
            handler(match.range, nil)
        }
    }
}

extension NSFont {
    func italic() -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
