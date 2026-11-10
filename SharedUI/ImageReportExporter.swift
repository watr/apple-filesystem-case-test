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
    case json, text, png, pngSeparate
    var fileExtension: String {
        switch self { case .json: return "json"; case .text: return "txt"; case .png, .pngSeparate: return "png" }
    }
}

enum ImageReportLayout { case combined, separate }

enum ImageReportError: LocalizedError {
    case renderingFailed, tooLarge
    var errorDescription: String? {
        switch self {
        case .renderingFailed: return "結果画像を作成できませんでした。"
        case .tooLarge: return "画像が大きすぎます。検証先ごとに分けるか、パスを省略して共有してください。"
        }
    }
}

@MainActor
enum ImageReportExporter {
    static func write(_ results: [TestResult], includePaths: Bool, to folder: URL,
                      layout: ImageReportLayout = .combined) async throws -> [URL] {
        guard !results.isEmpty else { return [] }
        try Task.checkCancellation()
        if layout == .combined {
            let data = try png(CombinedResultReportImage(results: results, includePaths: includePaths))
            let url = folder.appendingPathComponent("case-sensitivity.png")
            try data.write(to: url, options: .atomic)
            return [url]
        }
        var urls: [URL] = []
        for (index, result) in results.enumerated() {
            try Task.checkCancellation()
            let data = try png(ResultReportImage(result: result, includePaths: includePaths,
                                                 page: index + 1, total: results.count))
            let name = String(format: "case-sensitivity-%03d.png", index + 1)
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            urls.append(url)
            await Task.yield()
        }
        return urls
    }

    private static func png<Content: View>(_ content: Content) throws -> Data {
        try autoreleasepool {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            var size = CGSize.zero
            // Measure before allocating a bitmap; never truncate or silently split a combined image.
            renderer.render { measured, _ in size = measured }
            guard size.width > 0, size.height > 0 else { throw ImageReportError.renderingFailed }
            guard size.height * renderer.scale <= 12_000 else { throw ImageReportError.tooLarge }
            #if os(iOS)
            guard let data = renderer.uiImage?.pngData() else { throw ImageReportError.renderingFailed }
            #else
            guard let cgImage = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
            else { throw ImageReportError.renderingFailed }
            #endif
            return data
        }
    }
}

/// Compact cards keep all targets in one image while retaining each result's evidence.
private struct CombinedResultReportImage: View {
    let results: [TestResult]
    let includePaths: Bool
    private let ink = Color(red: 0.09, green: 0.14, blue: 0.22)
    private let muted = Color(red: 0.32, green: 0.38, blue: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("FILE SYSTEM REPORT").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(muted)
            Text("Case Sensitivity Tester").font(.system(size: 28, weight: .bold))
            Text("検証結果 / Results: \(results.count)").foregroundStyle(muted)
            ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                card(result, index: index)
            }
            Text(includePaths ? "保存先情報を含みます / Includes directory information" : "絶対パス・ボリューム名は省略 / Paths and volume names omitted")
                .font(.system(size: 12)).foregroundStyle(muted)
            Text("詳細ログはJSON・テキストで確認できます。")
                .font(.system(size: 12)).foregroundStyle(muted)
        }
        .font(.system(size: 15))
        .foregroundStyle(ink)
        .padding(28)
        .frame(width: 720, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    private func card(_ result: TestResult, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\(index + 1). \(result.test.label)").font(.system(size: 20, weight: .bold))
                Spacer(minLength: 12)
                Text(result.finalVerdict.rawValue).font(.system(size: 19, weight: .bold))
                    .foregroundStyle(result.finalVerdict == .inconclusive ? Color(red: 0.58, green: 0.28, blue: 0.02) : ink)
            }
            Text("\(result.device.platform) · \(result.device.model) · \(result.device.osVersion)").foregroundStyle(muted)
            Text(result.test.timestamp.formatted(date: .numeric, time: .standard)).foregroundStyle(muted)
            Divider()
            row("API / 実測", "\(result.api.caseSensitivityDescription) / \(result.actualTest.verdict.rawValue)")
            row("Case-preserving", result.api.casePreserving.map { String($0) } ?? "Unknown")
            row("Test.txt", creation(result.actualTest.first))
            row("test.txt", creation(result.actualTest.second))
            row("inode (Test / test)", "\(number(result.actualTest.first.inode)) / \(number(result.actualTest.second.inode))")
            row("device (Test / test)", "\(number(result.actualTest.first.deviceID)) / \(number(result.actualTest.second.deviceID))")
            row("内容 / 独立 / Cleanup", "\(flag(result.actualTest.contentsVerified)) / \(flag(result.actualTest.independentFiles)) / \(flag(result.actualTest.cleanupSucceeded))")
            row("エラー / Errors", String(result.errors.count))
            if result.api.verdict != .inconclusive, result.actualTest.verdict != .inconclusive,
               result.api.verdict != result.actualTest.verdict {
                Text("APIと実測が矛盾しています / API and actual test disagree").bold()
            }
            if includePaths {
                row("保存先 / Directory", result.test.directory)
                row("Volume", result.api.volumeName ?? "Unknown")
            }
            Text("App \(result.device.appVersion) (\(result.device.buildNumber)) · Test v\(result.device.testVersion)")
                .font(.system(size: 12)).foregroundStyle(muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.95, green: 0.96, blue: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).foregroundStyle(muted).frame(width: 175, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func flag(_ value: Bool?) -> String { value.map { $0 ? "Yes" : "No" } ?? "Unknown" }
    private func number<T>(_ value: T?) -> String { value.map { String(describing: $0) } ?? "Unknown" }
    private func creation(_ file: FileEvidence) -> String {
        "作成 / Created: \(flag(file.created)) · errno: \(number(file.createErrno))"
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
