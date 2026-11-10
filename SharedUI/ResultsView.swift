import SwiftUI

struct ResultsView: View {
    let results: [TestResult]
    var body: some View {
        ForEach(results) { result in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(result.test.label).font(.headline)
                    Spacer()
                    Text(result.finalVerdict.rawValue).bold()
                        .foregroundStyle(result.finalVerdict == .inconclusive ? .orange : .primary)
                }
                Text(result.test.timestamp, format: .dateTime).font(.caption)
                Text("\(result.device.platform) · \(result.device.model)").font(.caption)
                Text("API: \(result.api.caseSensitivityDescription) / 実測: \(result.actualTest.verdict.rawValue)")
                Text("Case-preserving: \(result.api.casePreserving.map { String($0) } ?? "Unknown")")
                if result.api.verdict != .inconclusive, result.actualTest.verdict != .inconclusive,
                   result.api.verdict != result.actualTest.verdict {
                    Text("APIと実測が矛盾しています。最終判定はInconclusiveです。")
                        .foregroundStyle(.orange)
                }
                DisclosureGroup("詳細ログ（絶対パスを含みます）") {
                    Text(detail(result)).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.vertical, 6)
        }
    }
    private func detail(_ result: TestResult) -> String {
        do { return String(decoding: try ReportExporter.json([result], includePaths: true), as: UTF8.self) }
        catch { return "ログ表示エラー: \(error.localizedDescription)" }
    }
}

struct TargetListView: View {
    @ObservedObject var model: TesterModel
    var body: some View {
        ForEach(model.targets) { target in
            VStack(alignment: .leading) {
                HStack {
                    Text(target.label)
                    Spacer()
                    if target.selected {
                        Button("削除") { model.removeTarget(target) }.disabled(model.busy)
                    }
                }
                Text(target.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
