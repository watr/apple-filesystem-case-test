import Foundation
import SwiftUI

struct TargetDirectory: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let url: URL
    let selected: Bool
}

@MainActor
final class TesterModel: ObservableObject {
    @Published var targets: [TargetDirectory] = []
    @Published var results: [TestResult] = []
    @Published var running = false
    @Published var exporting = false
    var busy: Bool { running || exporting }
    @Published var message: String?
    @Published var includePaths = false
    private var scopedURLs: [URL] = []
    private var historyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CaseSensitivityTester", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    init() {
        let manager = FileManager.default
        targets = [
            TargetDirectory(label: "Documents", url: manager.urls(for: .documentDirectory, in: .userDomainMask)[0], selected: false),
            TargetDirectory(label: "Application Support", url: manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0], selected: false),
            TargetDirectory(label: "Temporary Directory", url: manager.temporaryDirectory, selected: false)
        ]
        if manager.fileExists(atPath: historyURL.path) {
            do {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                results = try decoder.decode([TestResult].self, from: Data(contentsOf: historyURL))
            } catch { message = "履歴を読み込めませんでした: \(error.localizedDescription)" }
        }
    }

    func addDirectories(_ urls: [URL]) {
        for url in urls where !targets.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            // A false return is not proof of denied access: NSOpenPanel may already grant it.
            if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
            targets.append(TargetDirectory(label: "Selected folder \(targets.filter(\.selected).count + 1)", url: url, selected: true))
        }
    }

    func removeTarget(_ target: TargetDirectory) {
        guard !busy, target.selected else { return }
        if let index = scopedURLs.firstIndex(of: target.url) {
            scopedURLs.remove(at: index).stopAccessingSecurityScopedResource()
        }
        targets.removeAll { $0.id == target.id }
    }

    func run() {
        guard !busy else { return }
        running = true; message = nil
        let locations = targets
        Task {
            let newResults = await Task.detached(priority: .userInitiated) {
                locations.map { target in
                    if !target.selected {
                        // Only app-owned default directories may be created automatically.
                        do { try FileManager.default.createDirectory(at: target.url, withIntermediateDirectories: true) }
                        catch {
                            var evidence = ActualTest()
                            evidence.errors = ["Prepare directory: \(error.localizedDescription)"]
                            return TestResult(directory: target.url, label: target.label,
                                              api: VolumeInspector.inspect(target.url), actual: evidence)
                        }
                    }
                    return FileSystemTester().test(directory: target.url, label: target.label)
                }
            }.value
            results.insert(contentsOf: newResults, at: 0)
            results = Array(results.prefix(100))
            persistHistory()
            running = false
        }
    }

    func importReports(_ urls: [URL]) {
        guard !busy else { return }
        running = true; message = nil
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    var combined: [TestResult] = []
                    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                    for url in urls {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        guard let size = values.fileSize, size <= 5_000_000 else {
                            throw CocoaError(.fileReadTooLarge)
                        }
                        combined += try decoder.decode([TestResult].self, from: Data(contentsOf: url))
                    }
                    return combined
                }.value
                var seen = Set<UUID>()
                results = Array((imported + results).filter { seen.insert($0.id).inserted }.prefix(100))
                persistHistory()
            } catch { message = "JSON読み込み失敗: \(error.localizedDescription)" }
            running = false
        }
    }

    private func persistHistory() {
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ReportExporter.json(results, includePaths: true).write(to: historyURL, options: .atomic)
        } catch { message = "履歴を保存できませんでした: \(error.localizedDescription)" }
    }

    func report(json: Bool) throws -> Data {
        if json { return try ReportExporter.json(results, includePaths: includePaths) }
        return Data(try ReportExporter.text(results, includePaths: includePaths).utf8)
    }

    func writeReportFiles(format: ReportFormat, in folder: URL) async throws -> [URL] {
        guard !busy else { throw CocoaError(.userCancelled) }
        exporting = true
        message = nil
        defer { exporting = false }
        let snapshot = results
        let paths = includePaths
        if format == .png || format == .pngSeparate {
            return try await ImageReportExporter.write(snapshot, includePaths: paths, to: folder,
                                                       layout: format == .png ? .combined : .separate)
        }
        let data = format == .json
            ? try ReportExporter.json(snapshot, includePaths: paths)
            : Data(try ReportExporter.text(snapshot, includePaths: paths).utf8)
        let url = folder.appendingPathComponent("case-sensitivity.\(format.fileExtension)")
        try data.write(to: url, options: .atomic)
        return [url]
    }

    deinit {
        for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
    }
}
