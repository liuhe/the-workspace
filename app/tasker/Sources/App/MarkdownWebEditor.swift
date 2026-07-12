import SwiftUI
import WebKit

/// WKWebView + Toast UI Editor 的 WYSIWYG markdown 编辑器。
/// 存储层还是 markdown 文本；WKWebView 侧持有富文本编辑体验。
/// 把 CSS/JS 直接内联进 HTML 再 loadHTMLString，避免 file:// 的 CORS 限制。
struct MarkdownWebEditor: NSViewRepresentable {
    @Binding var markdown: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "editor")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // 右键 → Inspect Element / Cmd+Alt+I 打开 Web Inspector
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        webView.loadHTMLString(Self.buildInlinedHTML(), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.ready else {
            context.coordinator.pendingMarkdown = markdown
            return
        }
        context.coordinator.push(markdown, to: webView)
    }

    // MARK: - HTML 构造：内联 CSS + JS

    private static func buildInlinedHTML() -> String {
        let css = readResource("toastui-editor.min", ext: "css",
                               subdir: "Resources/toastui") ?? ""
        let js = readResource("toastui-editor-all.min", ext: "js",
                              subdir: "Resources/toastui") ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
        \(css)
        html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
        #editor { height: 100%; }
        .toastui-editor-defaultUI { border: none; }
        </style>
        </head>
        <body>
        <div id="editor"></div>
        <script>
        \(js)
        </script>
        <script>
        (function () {
          var editor = new toastui.Editor({
            el: document.querySelector('#editor'),
            height: '100%',
            initialEditType: 'wysiwyg',
            previewStyle: 'tab',
            hideModeSwitch: false,
            usageStatistics: false,
            toolbarItems: [
              ['heading', 'bold', 'italic', 'strike'],
              ['hr', 'quote'],
              ['ul', 'ol', 'task'],
              ['table', 'link'],
              ['code', 'codeblock']
            ]
          });

          var lastPushed = '';
          editor.on('change', function () {
            var md = editor.getMarkdown();
            if (md === lastPushed) return;
            lastPushed = md;
            window.webkit.messageHandlers.editor.postMessage({ type: 'change', md: md });
          });

          window.setMarkdown = function (md) {
            if (typeof md !== 'string') return;
            if (editor.getMarkdown() === md) return;
            lastPushed = md;
            editor.setMarkdown(md, false);
          };

          // Cmd+click 链接 → 交给系统浏览器（不让 prosemirror 吃掉）
          document.addEventListener('click', function (e) {
            if (!e.metaKey) return;
            var a = e.target && e.target.closest ? e.target.closest('a') : null;
            if (!a || !a.href) return;
            e.preventDefault();
            e.stopPropagation();
            window.webkit.messageHandlers.editor.postMessage({ type: 'openLink', url: a.href });
          }, true);

          window.webkit.messageHandlers.editor.postMessage({ type: 'ready' });
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func readResource(_ name: String, ext: String, subdir: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdir) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MarkdownWebEditor
        weak var webView: WKWebView?
        var ready = false
        var pendingMarkdown: String?
        var lastPushed = ""

        init(_ parent: MarkdownWebEditor) { self.parent = parent }

        // 拦截所有导航：允许初始 about: 加载；其它 URL（http/https/file）交给系统浏览器
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                let md = pendingMarkdown ?? parent.markdown
                if let wv = webView { push(md, to: wv) }
                pendingMarkdown = nil
            case "change":
                if let md = dict["md"] as? String {
                    lastPushed = md
                    DispatchQueue.main.async { self.parent.markdown = md }
                }
            case "openLink":
                if let s = dict["url"] as? String, let url = URL(string: s) {
                    NSWorkspace.shared.open(url)
                }
            default: break
            }
        }

        func push(_ md: String, to webView: WKWebView) {
            guard md != lastPushed else { return }
            lastPushed = md
            let js = "window.setMarkdown(\(jsQuote(md)));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func jsQuote(_ s: String) -> String {
            var out = "\""
            for c in s.unicodeScalars {
                switch c {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\u{2028}": out += "\\u2028"
                case "\u{2029}": out += "\\u2029"
                default:
                    if c.value < 0x20 {
                        out += String(format: "\\u%04x", c.value)
                    } else {
                        out.append(Character(c))
                    }
                }
            }
            out += "\""
            return out
        }
    }
}
