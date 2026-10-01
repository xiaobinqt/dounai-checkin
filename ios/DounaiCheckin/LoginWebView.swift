import SwiftUI
import WebKit

struct LoginView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var status = "请在网站原页面完成登录和验证码"

    var body: some View {
        NavigationStack {
            LoginWebView(settings: settings, status: $status)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("网页登录")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    Text(status)
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(.thinMaterial)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("返回应用") { dismiss() }
                    }
                }
        }
    }
}

private struct LoginWebView: UIViewRepresentable {
    @ObservedObject var settings: AppSettings
    @Binding var status: String

    func makeCoordinator() -> Coordinator { Coordinator(settings: settings, status: $status) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        restoreCookies(into: webView) {
            guard let url = Self.normalizedURL(settings.siteURL) else {
                status = "站点地址必须是 HTTPS 根地址"
                return
            }
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func restoreCookies(into webView: WKWebView, completion: @escaping () -> Void) {
        guard let url = Self.normalizedURL(settings.siteURL), let host = url.host else {
            completion()
            return
        }
        let pairs = settings.cookie.split(separator: ";").compactMap { item -> HTTPCookie? in
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return HTTPCookie(properties: [
                .domain: host, .path: "/", .name: pair[0].trimmingCharacters(in: .whitespaces),
                .value: pair[1].trimmingCharacters(in: .whitespaces), .secure: "TRUE"
            ])
        }
        guard !pairs.isEmpty else { completion(); return }
        let group = DispatchGroup()
        pairs.forEach { cookie in
            group.enter()
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    private static func normalizedURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        return url
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let settings: AppSettings
        var status: Binding<String>
        weak var webView: WKWebView?

        init(settings: AppSettings, status: Binding<String>) {
            self.settings = settings
            self.status = status
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            captureSession(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            status.wrappedValue = "网页加载失败：\(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            status.wrappedValue = "网页加载失败：\(error.localizedDescription)"
        }

        private func captureSession(_ webView: WKWebView) {
            webView.evaluateJavaScript("navigator.userAgent") { value, _ in
                if let value = value as? String, !value.isEmpty { self.settings.userAgent = value }
            }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                Task { @MainActor in
                    guard let host = URL(string: self.settings.siteURL)?.host?.lowercased() else { return }
                    let matching = cookies.filter {
                        let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                        return host == domain || host.hasSuffix("." + domain)
                    }
                    guard !matching.isEmpty else {
                        self.status.wrappedValue = "尚未取得登录信息，请继续在网页中登录"
                        return
                    }
                    self.settings.cookie = matching.sorted { $0.name < $1.name }
                        .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    self.settings.save()
                    self.status.wrappedValue = "已保存当前登录信息，可以返回应用"
                }
            }
        }
    }
}
