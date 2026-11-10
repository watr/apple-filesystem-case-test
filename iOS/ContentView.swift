import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = TesterModel()
    @State private var share: SharePayload?
    @State private var exportJSON = true
    @State private var confirmPaths = false

    var body: some View {
        NavigationStack {
            List {
                Section("検証対象（アプリのサンドボックス内）") { TargetListView(model: model) }
                Section {
                    Button(model.running ? "検証中…" : "検証開始 / 再検証") { model.run() }
                        .disabled(model.running)
                    if model.running { ProgressView() }
                }
                Section("レポート共有・比較（保存済み履歴を含む最大100件）") {
                    ReportImportButton(model: model)
                    Toggle("絶対パス・ボリューム名を含める", isOn: $model.includePaths)
                    Text("共有前に確認できます。通常はパスを伏せて出力します。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("JSONを共有") { prepare(json: true) }.disabled(model.results.isEmpty || model.running)
                    Button("テキストを共有") { prepare(json: false) }.disabled(model.results.isEmpty || model.running)
                }
                if let message = model.message { Section { Text(message).foregroundStyle(.orange) } }
                Section("結果・履歴") { ResultsView(results: model.results) }
            }
            .navigationTitle("Case Sensitivity")
            .sheet(item: $share, onDismiss: removeShareFiles) { payload in ShareSheet(url: payload.url) }
            .alert("個人情報を含むレポートを共有", isPresented: $confirmPaths) {
                Button("共有する") { export() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("絶対パスやボリューム名にはユーザー名などが含まれる場合があります。詳細ログで確認してから共有してください。")
            }
        }
    }
    private func prepare(json: Bool) {
        exportJSON = json
        if model.includePaths { confirmPaths = true } else { export() }
    }
    private func export() {
        do {
            let data = try model.report(json: exportJSON)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Report-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let url = folder.appendingPathComponent(exportJSON ? "case-sensitivity.json" : "case-sensitivity.txt")
            do { try data.write(to: url, options: .atomic) }
            catch { try? FileManager.default.removeItem(at: folder); throw error }
            share = SharePayload(url: url)
            shareFolder = folder
        } catch { model.message = "レポート作成失敗: \(error.localizedDescription)" }
    }
    @State private var shareFolder: URL?
    private func removeShareFiles() {
        if let folder = shareFolder {
            do { try FileManager.default.removeItem(at: folder) }
            catch { model.message = "共有用一時ファイルを削除できませんでした: \(error.localizedDescription)" }
        }
        shareFolder = nil
    }
}
private struct SharePayload: Identifiable { let id = UUID(); let url: URL }
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
