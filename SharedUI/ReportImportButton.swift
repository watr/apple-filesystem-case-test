import SwiftUI
import UniformTypeIdentifiers

struct ReportImportButton: View {
    @ObservedObject var model: TesterModel
    @State private var choosing = false
    var body: some View {
        Button("JSONを読み込み・比較…") { choosing = true }
            .disabled(model.busy)
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.json], allowsMultipleSelection: true) { selection in
                switch selection {
                case .success(let urls): model.importReports(urls)
                case .failure(let error): model.message = "読み込み失敗: \(error.localizedDescription)"
                }
            }
    }
}
