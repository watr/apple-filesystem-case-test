import Foundation

public enum ReportExporter {
    public static func json(_ results: [TestResult], includePaths: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(results.map { includePaths ? $0 : redacted($0) })
    }
    public static func text(_ results: [TestResult], includePaths: Bool = false) throws -> String {
        // The full structured evidence is included so text exports do not lose diagnostics.
        let summary = results.map {
            "\($0.test.label): API=\($0.api.caseSensitivityDescription), actual=\($0.actualTest.verdict.rawValue), final=\($0.finalVerdict.rawValue)"
        }.joined(separator: "\n")
        return "Apple File System Case Sensitivity Tester\n\(summary)\n\n" +
            String(decoding: try json(results, includePaths: includePaths), as: UTF8.self)
    }
    private static func redacted(_ source: TestResult) -> TestResult {
        var result = source
        result.test.directory = "[redacted directory]"
        result.test.volumeName = source.test.volumeName == nil ? nil : "[redacted volume]"
        result.api.volumeURL = source.api.volumeURL == nil ? nil : "[redacted volume URL]"
        result.api.volumeName = source.api.volumeName == nil ? nil : "[redacted volume]"
        // Foundation's localized errors can embed full paths and volume names.
        result.api.errors = source.api.errors.enumerated().map { "API diagnostic \($0.offset + 1) omitted for privacy" }
        result.actualTest.errors = source.actualTest.errors.enumerated().map {
            "Actual diagnostic \($0.offset + 1) omitted for privacy"
        }
        result.api.fileSystemAttributes = source.api.fileSystemAttributes.filter {
            [FileAttributeKey.systemNumber.rawValue, FileAttributeKey.systemSize.rawValue,
             FileAttributeKey.systemFreeSize.rawValue, FileAttributeKey.systemNodes.rawValue,
             FileAttributeKey.systemFreeNodes.rawValue].contains($0.key)
        }
        return result
    }
}
