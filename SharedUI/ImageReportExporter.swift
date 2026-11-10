import SwiftUI
import Foundation
#if SWIFT_PACKAGE
import CaseSensitivityCore
#endif
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Formats shared by the platform-specific export controls.
enum ReportFormat {
    case json, text, png
    var fileExtension: String {
        switch self { case .json: return "json"; case .text: return "txt"; case .png: return "png" }
    }
}

enum ImageReportError: LocalizedError {
    case renderingFailed
    var errorDescription: String? { "結果画像を作成できませんでした。" }
}

@MainActor
enum ImageReportExporter {
    static func write(_ results: [TestResult], includePaths: Bool, to folder: URL) async throws -> [URL] {
        var urls: [URL] = []
        for (index, result) in results.enumerated() {
            try Task.checkCancellation()
            let data = try autoreleasepool {
                let view = ResultReportImage(result: result, includePaths: includePaths,
                                             page: index + 1, total: results.count)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                #if os(iOS)
                guard let data = renderer.uiImage?.pngData() else { throw ImageReportError.renderingFailed }
                #else
                guard let cgImage = renderer.cgImage,
                      let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
                else { throw ImageReportError.renderingFailed }
                #endif
                return data
            }
            let name = String(format: "case-sensitivity-%03d.png", index + 1)
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            urls.append(url)
            // Release each renderer before proceeding and let progress/UI updates run.
            await Task.yield()
        }
        return urls
    }
}

/// A fully laid out document, independent of the on-screen List and its scroll position.
private struct ResultReportImage: View {
    let result: TestResult
    let includePaths: Bool
    let page: Int
    let total: Int
    private let ink = Color(red: 0.09, green: 0.14, blue: 0.22)
    private let muted = Color(red: 0.32, green: 0.38, blue: 0.45)
    private let panel = Color(red: 0.95, green: 0.96, blue: 0.98)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FILE SYSTEM REPORT").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(muted)
                Text("Case Sensitivity Tester").font(.system(size: 30, weight: .bold))
                Text(result.test.label).font(.system(size: 24, weight: .semibold))
                Text(result.test.timestamp.formatted(date: .numeric, time: .standard)).foregroundStyle(muted)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("最終判定 / Final verdict").font(.system(size: 16, weight: .semibold))
                Text(result.finalVerdict.rawValue).font(.system(size: 32, weight: .bold))
                    .foregroundStyle(result.finalVerdict == .inconclusive ? Color(red: 0.58, green: 0.28, blue: 0.02) : ink)
                row("API", result.api.caseSensitivityDescription)
                row("実測 / Actual", result.actualTest.verdict.rawValue)
                row("Case-preserving", result.api.casePreserving.map { String($0) } ?? "Unknown")
                if result.api.verdict != .inconclusive, result.actualTest.verdict != .inconclusive,
                   result.api.verdict != result.actualTest.verdict {
                    Text("APIと実測が矛盾しています / API and actual test disagree")
                        .font(.system(size: 16, weight: .semibold))
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(panel).clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 10) {
                row("OS / Device", "\(result.device.platform) · \(result.device.model)")
                row("OS version", result.device.osVersion)
                if includePaths {
                    row("保存先 / Directory", result.test.directory)
                    row("Volume", result.api.volumeName ?? "Unknown")
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("ファイル作成テスト / File creation test").font(.system(size: 20, weight: .semibold))
                file("Test.txt", result.actualTest.first)
                file("test.txt", result.actualTest.second)
                row("内容一致 / Contents", flag(result.actualTest.contentsVerified))
                row("独立したファイル", flag(result.actualTest.independentFiles))
                row("後片付け / Cleanup", flag(result.actualTest.cleanupSucceeded))
                row("エラー / Errors", String(result.errors.count))
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("App \(result.device.appVersion) (\(result.device.buildNumber)) · Test v\(result.device.testVersion)")
                Text(includePaths ? "保存先情報を含みます / Includes directory information" : "絶対パス・ボリューム名は省略 / Paths and volume names omitted")
                Text("要約画像です。詳細ログはJSON・テキストで確認できます。")
                Text("\(page) / \(total) · \(result.id.uuidString)").font(.system(size: 12, design: .monospaced))
            }.font(.system(size: 14)).foregroundStyle(muted)
        }
        .font(.system(size: 18))
        .foregroundStyle(ink)
        .padding(32)
        .frame(width: 720, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title).foregroundStyle(muted).frame(width: 190, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func flag(_ value: Bool?) -> String {
        value.map { $0 ? "Yes" : "No" } ?? "Unknown / 未完了"
    }
    private func file(_ name: String, _ evidence: FileEvidence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            row(name, "作成 / Created: \(flag(evidence.created)) · errno: \(evidence.createErrno.map { String($0) } ?? "Unknown")")
            row("inode / device", "\(evidence.inode.map { String($0) } ?? "Unknown") / \(evidence.deviceID.map { String($0) } ?? "Unknown")")
        }
    }
}
