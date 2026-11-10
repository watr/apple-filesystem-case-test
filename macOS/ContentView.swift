import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = TesterModel()
    @State private var confirmPaths = false
    @State private var exportFormat: ReportFormat = .json
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File System Case Sensitivity").font(.title2).bold()
                Spacer()
                Button("フォルダを追加…", action: chooseFolders).disabled(model.busy)
                Button(model.running ? "検証中…" : "検証開始 / 再検証") { model.run() }.disabled(model.busy)
            }
            List {
                Section("検証対象") { TargetListView(model: model) }
                Section("結果・履歴（最大100件・端末内に保存）") { ResultsView(results: model.results) }
            }
            if model.running { ProgressView("検証中。保存先の応答を待っています…") }
            if let message = model.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
            if model.exporting { ProgressView("レポートを書き出しています…") }
            Toggle("出力に絶対パス・ボリューム名を含める", isOn: $model.includePaths).disabled(model.busy)
            Text("通常はパスを伏せて出力します。詳細ログで共有内容を確認できます。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                ReportImportButton(model: model)
                Spacer()
                Button("JSONを保存…") { prepare(.json) }.disabled(model.results.isEmpty || model.busy)
                Button("テキストを保存…") { prepare(.text) }.disabled(model.results.isEmpty || model.busy)
                Button("画像を保存（PNG）…") { prepare(.png) }.disabled(model.results.isEmpty || model.busy)
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
    private func prepare(_ format: ReportFormat) {
        exportFormat = format
        if model.includePaths { confirmPaths = true } else { save() }
    }
    private func save() {
        if exportFormat == .png { saveImages(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportFormat == .json ? .json : .plainText]
        panel.nameFieldStringValue = exportFormat == .json ? "case-sensitivity.json" : "case-sensitivity.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try model.report(json: exportFormat == .json).write(to: url, options: .atomic) }
        catch { model.message = "保存失敗: \(error.localizedDescription)" }
    }
    private func saveImages() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "画像の保存先を選択"
        panel.message = "検証先1件につきPNGを1枚、選択した場所の新しいフォルダに保存します。"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        Task {
            let scoped = parent.startAccessingSecurityScopedResource()
            defer { if scoped { parent.stopAccessingSecurityScopedResource() } }
            let folder = parent.appendingPathComponent("CaseSensitivityReport-\(UUID().uuidString)")
            var created = false
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                created = true
                let urls = try await model.writeReportFiles(format: .png, in: folder)
                model.message = "\(urls.count)枚の画像を保存しました: \(folder.path)"
            } catch {
                if created { try? FileManager.default.removeItem(at: folder) }
                model.message = "画像保存失敗: \(error.localizedDescription)"
            }
        }
    }

}
