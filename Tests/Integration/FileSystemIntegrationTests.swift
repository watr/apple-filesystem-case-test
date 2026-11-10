import XCTest
import Darwin
@testable import CaseSensitivityCore

final class FileSystemIntegrationTests: XCTestCase {
    func testRealVolumeAndCleanupPreserveExistingFiles() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let sentinel = parent.appendingPathComponent("Test.txt")
        try Data("existing user data".utf8).write(to: sentinel)
        let result = FileSystemTester().test(directory: parent, label: "Integration")
        XCTAssertTrue(result.actualTest.errors.isEmpty, "\(result.actualTest.errors)")
        XCTAssertNotEqual(result.actualTest.verdict, .inconclusive)
        XCTAssertEqual(result.actualTest.cleanupSucceeded, true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), ["Test.txt"])
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "existing user data")
        if result.api.caseSensitive != nil { XCTAssertEqual(result.api.verdict, result.actualTest.verdict) }
    }
    func testReadOnlyDirectoryIsInconclusiveWithoutArtifacts() throws {
        guard geteuid() != 0 else { throw XCTSkip("Root bypasses ordinary directory permissions") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            chmod(directory.path, 0o700)
            try? FileManager.default.removeItem(at: directory)
        }
        XCTAssertEqual(chmod(directory.path, 0o500), 0)
        let result = POSIXFileProbe().run(in: directory)
        XCTAssertEqual(result.verdict, .inconclusive)
        XCTAssertTrue(result.errors.contains { $0.contains("errno=\(EACCES)") }, "\(result.errors)")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testMissingTargetIsInconclusiveAndNotCreated() {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = POSIXFileProbe().run(in: target)
        XCTAssertEqual(result.verdict, .inconclusive)
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
    func testNonDirectoryTarget() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("sentinel".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let result = POSIXFileProbe().run(in: file)
        XCTAssertEqual(result.verdict, .inconclusive)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "sentinel")
    }
}
