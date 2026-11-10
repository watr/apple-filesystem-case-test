import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = TesterModel()
    @State private var share: SharePayload?
    @State private var exportFormat: ReportFormat = .json
    @State private var confirmPaths = false

    var body: some View {
        NavigationStack {
            List {
                Section("検証対象（アプリのサンドボックス内）") { TargetListView(model: model) }
                Section {
                    Button(model.running ? "検証中…" : "検証開始 / 再検証") { model.run() }
                        .disabled(model.busy)
                    if model.running { ProgressView() }
                }
                Section("レポート共有・比較（保存済み履歴を含む最大100件）") {
                    ReportImportButton(model: model)
                    Toggle("絶対パス・ボリューム名を含める", isOn: $model.includePaths).disabled(model.busy)
                    Text("共有前に確認できます。通常はパスを伏せて出力します。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("JSONを共有") { prepare(.json) }.disabled(model.results.isEmpty || model.busy)
                    Button("テキストを共有") { prepare(.text) }.disabled(model.results.isEmpty || model.busy)
                    Button("画像を共有（1枚にまとめる）") { prepare(.png) }.disabled(model.results.isEmpty || model.busy)
                    Button("画像を共有（検証先ごと）") { prepare(.pngSeparate) }.disabled(model.results.isEmpty || model.busy)
                    Text("一覧の結果を1枚にまとめて共有できます。検証先ごとに画像を分けることもできます。")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.exporting { ProgressView("レポートを書き出しています…") }
                }
                if let message = model.message { Section { Text(message).foregroundStyle(.orange) } }
                Section("結果・履歴") { ResultsView(results: model.results) }
            }
            .navigationTitle("Case Sensitivity")
            .sheet(item: $share, onDismiss: removeShareFiles) { payload in ShareSheet(urls: payload.urls) }
            .alert("個人情報を含むレポートを共有", isPresented: $confirmPaths) {
                Button("共有する") { export() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("絶対パスやボリューム名にはユーザー名などが含まれる場合があります。詳細ログで確認してから共有してください。")
            }
        }
    }
    private func prepare(_ format: ReportFormat) {
        exportFormat = format
        if model.includePaths { confirmPaths = true } else { export() }
    }
    private func export() {
        Task {
            var folder: URL?
            do {
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Report-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                folder = destination
                let urls = try await model.writeReportFiles(format: exportFormat, in: destination)
                shareFolder = destination
                share = SharePayload(urls: urls)
            } catch {
                if let folder { try? FileManager.default.removeItem(at: folder) }
                model.message = "レポート作成失敗: \(error.localizedDescription)"
            }
        }
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
private struct SharePayload: Identifiable { let id = UUID(); let urls: [URL] }
private struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
