import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = TesterModel()
    @State private var confirmPaths = false
    @State private var exportJSON = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File System Case Sensitivity").font(.title2).bold()
                Spacer()
                Button("フォルダを追加…", action: chooseFolders).disabled(model.running)
                Button(model.running ? "検証中…" : "検証開始 / 再検証") { model.run() }.disabled(model.running)
            }
            List {
                Section("検証対象") { TargetListView(model: model) }
                Section("結果・履歴（最大100件・端末内に保存）") { ResultsView(results: model.results) }
            }
            if model.running { ProgressView("検証中。保存先の応答を待っています…") }
            if let message = model.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
            Toggle("出力に絶対パス・ボリューム名を含める", isOn: $model.includePaths)
            HStack {
                Text("通常はパスを伏せて出力します。詳細ログで共有内容を確認できます。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                ReportImportButton(model: model)
                Button("JSONを保存…") { prepare(json: true) }.disabled(model.results.isEmpty || model.running)
                Button("テキストを保存…") { prepare(json: false) }.disabled(model.results.isEmpty || model.running)
            }
        }.padding()
        .alert("個人情報を含むレポートを保存", isPresented: $confirmPaths) {
            Button("保存する") { save() }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("絶対パスやボリューム名にはユーザー名などが含まれる場合があります。共有前に内容を確認してください。") }
    }
    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true; panel.canCreateDirectories = false
        panel.prompt = "検証対象に追加"
        if panel.runModal() == .OK { model.addDirectories(panel.urls) }
    }
    private func prepare(json: Bool) {
        exportJSON = json
        if model.includePaths { confirmPaths = true } else { save() }
    }
    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportJSON ? .json : .plainText]
        panel.nameFieldStringValue = exportJSON ? "case-sensitivity.json" : "case-sensitivity.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try model.report(json: exportJSON).write(to: url, options: .atomic) }
        catch { model.message = "保存失敗: \(error.localizedDescription)" }
    }
}
