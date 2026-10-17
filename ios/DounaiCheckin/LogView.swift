import SwiftUI

struct LogView: View {
    @State private var text = ""
    @State private var confirmingClear = false

    var body: some View {
        ScrollView {
            Text(text).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("运行日志")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("刷新") { refresh() }
                Button("复制") { UIPasteboard.general.string = text }
                ShareLink("分享", item: text)
                Button("清空", role: .destructive) { confirmingClear = true }
            }
        }
        .confirmationDialog("清空运行日志？", isPresented: $confirmingClear) {
            Button("清空", role: .destructive) { DiagnosticLog.clear(); refresh() }
        }
        .onAppear {
            BackgroundScheduler.capture(reason: "log-view")
            refresh()
        }
    }

    private func refresh() { text = DiagnosticLog.read() }
}
