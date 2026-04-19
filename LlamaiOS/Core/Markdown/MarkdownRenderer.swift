import SwiftUI
import UIKit

struct MarkdownRenderer: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownBlock.blocks(from: text)) { block in
                switch block.kind {
                case .paragraph:
                    Text(attributed(block.content))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language):
                    CodeBlockView(code: block.content, language: language)
                }
            }
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(.caption)
                    .foregroundStyle(Design.secondaryText)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.22))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Design.separator)
        )
    }
}

struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph
        case code(language: String?)
    }

    let id = UUID()
    var kind: Kind
    var content: String

    static func blocks(from text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var codeLanguage: String?
        var inCode = false

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                result.append(.init(kind: .paragraph, content: joined))
            }
            paragraph.removeAll()
        }

        func flushCode() {
            result.append(.init(kind: .code(language: codeLanguage), content: code.joined(separator: "\n")))
            code.removeAll()
            codeLanguage = nil
        }

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                    codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if inCode {
                code.append(line)
            } else {
                paragraph.append(line)
            }
        }

        if inCode {
            flushCode()
        } else {
            flushParagraph()
        }

        return result.isEmpty ? [.init(kind: .paragraph, content: text)] : result
    }
}
