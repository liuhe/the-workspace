import SwiftUI

/// Markdown 渲染：块级（headings/list/quote/code）自己解析，行内格式（bold/italic/code/link）
/// 靠 SwiftUI 的 `Text(LocalizedStringKey)` 内建渲染 —— 这是官方支持的路径，一定生效。
struct MarkdownRenderView: View {
    let source: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if source.isEmpty {
                    Text("(空)").foregroundStyle(.tertiary).italic()
                } else {
                    ForEach(Array(parseBlocks(source).enumerated()), id: \.offset) { _, block in
                        renderBlock(block)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    // MARK: - 块解析

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case number(text: String)
        case quote(text: String)
        case codeBlock(text: String)
        case paragraph(text: String)
        case blank
    }

    private func parseBlocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var inCode = false
        var codeBuf = ""
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.codeBlock(text: codeBuf))
                    codeBuf = ""
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuf += line + "\n"
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blocks.append(.blank)
            } else if let h = parseHeading(line) {
                blocks.append(.heading(level: h.0, text: h.1))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet(text: String(trimmed.dropFirst(2))))
            } else if let m = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                blocks.append(.number(text: String(trimmed[m.upperBound...])))
            } else if trimmed.hasPrefix("> ") {
                blocks.append(.quote(text: String(trimmed.dropFirst(2))))
            } else {
                blocks.append(.paragraph(text: line))
            }
        }
        if inCode && !codeBuf.isEmpty {
            blocks.append(.codeBlock(text: codeBuf))
        }
        return blocks
    }

    private func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex && line[idx] == "#" && level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[line.index(after: idx)...])
        return (level, text)
    }

    // MARK: - 渲染

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        case 5: return .headline
        default: return .subheadline
        }
    }

    /// Text(LocalizedStringKey) 是 SwiftUI 内建的 markdown inline 渲染路径，
    /// **bold** / *italic* / `code` / [link](url) 都能识别。
    @ViewBuilder
    private func inlineText(_ raw: String) -> some View {
        Text(LocalizedStringKey(raw)).textSelection(.enabled)
    }

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .bold()
                .padding(.vertical, 2)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inlineText(text)
            }
        case .number(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inlineText(text)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                inlineText(text).foregroundStyle(.secondary)
            }
        case .codeBlock(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
        case .paragraph(let text):
            inlineText(text)
        case .blank:
            Color.clear.frame(height: 4)
        }
    }
}
