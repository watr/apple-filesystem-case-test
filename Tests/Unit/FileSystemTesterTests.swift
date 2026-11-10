import XCTest
import Darwin
@testable import CaseSensitivityCore

final class FileSystemTesterTests: XCTestCase {
    func sensitive() -> ActualTest {
        var e = ActualTest()
        e.first = .init(created: true, createErrno: 0, content: "UPPER_FILE_CONTENT", inode: 10, deviceID: 1)
        e.second = .init(created: true, createErrno: 0, content: "lower_file_content", inode: 11, deviceID: 1)
        e.entries = ["Test.txt", "test.txt"]; e.cleanupSucceeded = true
        return e
    }
    func insensitive() -> ActualTest {
        var e = sensitive()
        e.second = .init(created: false, createErrno: EEXIST, content: "UPPER_FILE_CONTENT", inode: 10, deviceID: 1)
        e.entries = ["Test.txt"]
        return e
    }
    func testUnknownAPILabel() {
        XCTAssertEqual(VolumeInfo().caseSensitivityDescription, "Unknown")
        XCTAssertEqual(VolumeInfo(caseSensitive: true).caseSensitivityDescription, "Case-sensitive")
        XCTAssertEqual(VolumeInfo(caseSensitive: false).caseSensitivityDescription, "Case-insensitive")
    }
    func testCaseSensitive() { XCTAssertEqual(sensitive().verdict, .sensitive) }
    func testCaseInsensitiveAndEEXIST() { XCTAssertEqual(insensitive().verdict, .insensitive) }
    func testEEXISTAloneIsInsufficient() {
        var e = insensitive(); e.second.inode = 99
        XCTAssertEqual(e.verdict, .inconclusive)
        e = insensitive(); e.second.content = nil
        XCTAssertEqual(e.verdict, .inconclusive)
    }
    func testPermissionAndIOErrors() {
        for code in [EACCES, EPERM, EROFS, EIO, ENOSPC] {
            var e = sensitive(); e.second.created = false; e.second.createErrno = code
            e.errors = ["open: errno=\(code)"]
            XCTAssertEqual(e.verdict, .inconclusive)
        }
    }
    func testInvalidEvidence() {
        var e = sensitive(); e.second.content = "wrong"
        XCTAssertEqual(e.verdict, .inconclusive)
        e = sensitive(); e.second.inode = e.first.inode
        XCTAssertEqual(e.verdict, .inconclusive)
        e = sensitive(); e.second.deviceID = 2
        XCTAssertEqual(e.verdict, .inconclusive)
        e = sensitive(); e.entries.append("unexpected")
        XCTAssertEqual(e.verdict, .inconclusive)
        e = sensitive(); e.cleanupSucceeded = false
        XCTAssertEqual(e.verdict, .inconclusive)
    }
    func testAPIContradictionAndUnknown() {
        XCTAssertEqual(VerdictResolver.final(api: .sensitive, actual: .insensitive), .inconclusive)
        XCTAssertEqual(VerdictResolver.final(api: .insensitive, actual: .sensitive), .inconclusive)
        XCTAssertEqual(VerdictResolver.final(api: .inconclusive, actual: .sensitive), .sensitive)
        XCTAssertEqual(VerdictResolver.final(api: .sensitive, actual: .inconclusive), .inconclusive)
    }
    func testJSONRoundTripAndNull() throws {
        let r = TestResult(directory: URL(fileURLWithPath: "/private/secret"), label: "Documents",
                           api: VolumeInfo(), actual: sensitive())
        let data = try ReportExporter.json([r], includePaths: true)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TestResult].self, from: data)
        XCTAssertEqual(decoded.first?.finalVerdict, .sensitive)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let api = try XCTUnwrap(json[0]["api"] as? [String: Any])
        XCTAssertTrue(api["caseSensitive"] is NSNull)
        XCTAssertTrue(api["casePreserving"] is NSNull)
        let actual = try XCTUnwrap(json[0]["actualTest"] as? [String: Any])
        XCTAssertEqual(actual["firstFileCreated"] as? Bool, true)
        XCTAssertEqual(actual["verdict"] as? String, "Case-sensitive")
        XCTAssertTrue(actual["contentsVerified"] is NSNull)
    }
    func testPrivacyDefaultAndOptIn() throws {
        var api = VolumeInfo(); api.volumeURL = "/Volumes/Private"; api.volumeName = "Private"
        api.errors = ["Failed /Users/person/private"]
        let r = TestResult(directory: URL(fileURLWithPath: "/Users/person/private"), label: "Selected folder 1",
                           api: api, actual: {
                               var e = sensitive(); e.errors = ["Prepare /Users/person/private"]
                               return e
                           }())
        let safe = String(decoding: try ReportExporter.json([r]), as: UTF8.self)
        XCTAssertFalse(safe.contains("/Users/person")); XCTAssertFalse(safe.contains("/Volumes/Private"))
        XCTAssertTrue(try ReportExporter.text([r], includePaths: true).contains("/Users/person/private"))
    }
    func testInjectedProbe() {
        struct Stub: FileProbing {
            let evidence: ActualTest
            func run(in directory: URL) -> ActualTest { evidence }
        }
        let actual = FileSystemTester(probe: Stub(evidence: insensitive()))
            .test(directory: URL(fileURLWithPath: "/"), label: "Mock").actualTest
        XCTAssertEqual(actual.verdict, .insensitive)
    }
}
