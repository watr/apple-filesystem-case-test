import XCTest
import ImageIO
import Darwin
import CaseSensitivityCore
@testable import CaseSensitivityRendering

final class ImageReportExporterTests: XCTestCase {
    private func sample(_ label: String = "Documents") -> TestResult {
        var evidence = ActualTest()
        evidence.first = .init(created: true, createErrno: 0, content: "UPPER_FILE_CONTENT", inode: 10, deviceID: 1)
        evidence.second = .init(created: false, createErrno: EEXIST, content: "UPPER_FILE_CONTENT", inode: 10, deviceID: 1)
        evidence.entries = ["Test.txt"]
        evidence.contentsVerified = true; evidence.differentInodes = false
        evidence.independentFiles = false; evidence.cleanupSucceeded = true
        return TestResult(directory: URL(fileURLWithPath: "/Users/person/private"), label: label,
                          api: VolumeInfo(caseSensitive: false), actual: evidence)
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func image(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    @MainActor
    func testEveryResultIsExportedAsASeparatePNG() async throws {
        let destination = try folder()
        defer { try? FileManager.default.removeItem(at: destination) }
        let urls = try await ImageReportExporter.write([sample(), sample(), sample()], includePaths: false, to: destination, layout: .separate)
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)).count, 3)
        for url in urls {
            let bitmap = try image(url)
            XCTAssertEqual(bitmap.width, 1440)
            XCTAssertGreaterThan(bitmap.height, 1400)
            XCTAssertLessThan(bitmap.height, 6000)
        }
    }
    @MainActor
    func testDefaultCombinesAllThreeTargetsInOnePNG() async throws {
        let a = try folder(); let b = try folder()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let results = [sample("Documents"), sample("Application Support"), sample("Temporary Directory")]
        let single = try await ImageReportExporter.write([results[0]], includePaths: false, to: a)
        let combined = try await ImageReportExporter.write(results, includePaths: false, to: b)
        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(combined[0].lastPathComponent, "case-sensitivity.png")
        XCTAssertEqual(try image(combined[0]).width, 1440)
        XCTAssertGreaterThan(try image(combined[0]).height, try image(single[0]).height * 2)
    }
    @MainActor
    func testOversizedCombinedImageFailsWithoutTruncatingOrSplitting() async throws {
        let destination = try folder()
        defer { try? FileManager.default.removeItem(at: destination) }
        do {
            _ = try await ImageReportExporter.write((0..<100).map { sample("Target \($0)") },
                                                     includePaths: false, to: destination)
            XCTFail("Oversized images must fail before allocating or writing a bitmap")
        } catch ImageReportError.tooLarge {
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        }
    }
    @MainActor
    func testPrivateLocationsAndErrorMessagesDoNotAffectDefaultImage() async throws {
        let a = try folder(); let b = try folder()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        var first = sample()
        first.api.volumeName = "Private volume A"
        first.api.errors = ["Cannot access /Users/person/private"]
        var second = first
        second.test.directory = "/Users/another-person/secret"
        second.api.volumeName = "Private volume B"
        second.api.errors = ["Cannot access /Users/another-person/secret"]
        for layout in [ImageReportLayout.combined, .separate] {
            let firstURLs = try await ImageReportExporter.write([first], includePaths: false, to: a, layout: layout)
            let secondURLs = try await ImageReportExporter.write([second], includePaths: false, to: b, layout: layout)
            XCTAssertEqual(try Data(contentsOf: firstURLs[0]), try Data(contentsOf: secondURLs[0]))
        }
    }
    @MainActor
    func testLongIncludedPathsExpandTheImageInsteadOfClipping() async throws {
        let a = try folder(); let b = try folder()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let short = sample()
        var long = short
        long.test.directory = "/" + Array(repeating: "long-folder-name", count: 70).joined(separator: "/")
        let shortURLs = try await ImageReportExporter.write([short], includePaths: true, to: a)
        let longURLs = try await ImageReportExporter.write([long], includePaths: true, to: b)
        XCTAssertGreaterThan(try image(longURLs[0]).height, try image(shortURLs[0]).height)
    }
    @MainActor
    func testWriteFailureIsReported() async throws {
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await ImageReportExporter.write([sample()], includePaths: false, to: absent)
            XCTFail("Writing to a missing destination must fail")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
        }
    }
}
