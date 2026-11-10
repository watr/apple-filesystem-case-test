import Foundation
import Darwin

public enum Verdict: String, Codable, Sendable {
    case sensitive = "Case-sensitive"
    case insensitive = "Case-insensitive"
    case inconclusive = "Inconclusive"
}

public struct DeviceInfo: Codable, Sendable {
    public let platform: String
    public let model: String
    public let osVersion: String
    public let appVersion: String
    public let buildNumber: String
    public let testVersion: String

    public static func current() -> Self {
        #if os(iOS)
        var platform = "iOS / iPadOS"
        let modelKey = "hw.machine"
        #else
        let platform = "macOS"
        let modelKey = "hw.model"
        #endif
        var size = 0
        var model = "Unknown"
        if sysctlbyname(modelKey, nil, &size, nil, 0) == 0, size > 0 {
            var bytes = [CChar](repeating: 0, count: size)
            if sysctlbyname(modelKey, &bytes, &size, nil, 0) == 0 {
                model = String(cString: bytes)
            }
        }
        #if os(iOS)
        if model.hasPrefix("iPad") { platform = "iPadOS" }
        else if model.hasPrefix("iPhone") { platform = "iOS" }
        #endif
        #if targetEnvironment(simulator)
        platform = "iOS / iPadOS Simulator"
        #endif
        return Self(platform: platform, model: model,
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
                    buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
                    testVersion: "1")
    }
}

public struct VolumeInfo: Codable, Sendable {
    public var caseSensitive: Bool?
    public var casePreserving: Bool?
    public var volumeName: String?
    public var volumeURL: String?
    public var fileSystemAttributes: [String: String] = [:]
    public var fileSystemID: String?
    public var errors: [String] = []
    public init(caseSensitive: Bool? = nil) { self.caseSensitive = caseSensitive }
    enum CodingKeys: String, CodingKey {
        case caseSensitive, casePreserving, volumeName, volumeURL, fileSystemAttributes, fileSystemID, errors
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(caseSensitive, forKey: .caseSensitive)
        try c.encode(casePreserving, forKey: .casePreserving)
        try c.encode(volumeName, forKey: .volumeName)
        try c.encode(volumeURL, forKey: .volumeURL)
        try c.encode(fileSystemAttributes, forKey: .fileSystemAttributes)
        try c.encode(fileSystemID, forKey: .fileSystemID)
        try c.encode(errors, forKey: .errors)
    }
    public var caseSensitivityDescription: String { caseSensitive == nil ? "Unknown" : verdict.rawValue }
    public var verdict: Verdict {
        caseSensitive.map { $0 ? .sensitive : .insensitive } ?? .inconclusive
    }
}

public struct FileEvidence: Codable, Sendable {
    public var created: Bool?
    public var createErrno: Int32?
    public var content: String?
    public var inode: UInt64?
    public var deviceID: Int64?
    public init(created: Bool? = nil, createErrno: Int32? = nil, content: String? = nil,
                inode: UInt64? = nil, deviceID: Int64? = nil) {
        self.created = created; self.createErrno = createErrno; self.content = content
        self.inode = inode; self.deviceID = deviceID
    }
}

public struct ActualTest: Codable, Sendable {
    public var first = FileEvidence()
    public var second = FileEvidence()
    public var entries: [String] = []
    public var contentsVerified: Bool?
    public var differentInodes: Bool?
    public var independentFiles: Bool?
    public var cleanupSucceeded: Bool?
    public var temporaryDirectory: String?
    public var errors: [String] = []
    public init() {}
    public var firstFileCreated: Bool? { first.created }
    public var secondFileCreated: Bool? { second.created }
    public var verdict: Verdict { VerdictResolver.actual(self) }

    enum CodingKeys: String, CodingKey {
        case first, second, entries, contentsVerified, differentInodes, independentFiles
        case cleanupSucceeded, temporaryDirectory, errors, firstFileCreated, secondFileCreated, verdict
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        first = try c.decode(FileEvidence.self, forKey: .first)
        second = try c.decode(FileEvidence.self, forKey: .second)
        entries = try c.decode([String].self, forKey: .entries)
        contentsVerified = try c.decodeIfPresent(Bool.self, forKey: .contentsVerified)
        differentInodes = try c.decodeIfPresent(Bool.self, forKey: .differentInodes)
        independentFiles = try c.decodeIfPresent(Bool.self, forKey: .independentFiles)
        cleanupSucceeded = try c.decodeIfPresent(Bool.self, forKey: .cleanupSucceeded)
        temporaryDirectory = try c.decodeIfPresent(String.self, forKey: .temporaryDirectory)
        errors = try c.decode([String].self, forKey: .errors)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(first, forKey: .first); try c.encode(second, forKey: .second)
        try c.encode(entries, forKey: .entries)
        try c.encode(contentsVerified, forKey: .contentsVerified)
        try c.encode(differentInodes, forKey: .differentInodes)
        try c.encode(independentFiles, forKey: .independentFiles)
        try c.encode(cleanupSucceeded, forKey: .cleanupSucceeded)
        try c.encode(temporaryDirectory, forKey: .temporaryDirectory)
        try c.encode(errors, forKey: .errors)
        try c.encode(first.created, forKey: .firstFileCreated)
        try c.encode(second.created, forKey: .secondFileCreated)
        try c.encode(verdict, forKey: .verdict)
    }
}

public enum VerdictResolver {
    public static func actual(_ e: ActualTest) -> Verdict {
        guard e.errors.isEmpty, e.cleanupSucceeded == true, e.first.created == true,
              e.first.createErrno == 0, e.first.content == "UPPER_FILE_CONTENT",
              let inodeA = e.first.inode, let inodeB = e.second.inode,
              let devA = e.first.deviceID, let devB = e.second.deviceID,
              devA == devB else { return .inconclusive }
        if e.second.created == true, e.second.createErrno == 0,
           Set(e.entries) == ["Test.txt", "test.txt"],
           e.second.content == "lower_file_content", inodeA != inodeB {
            return .sensitive
        }
        if e.second.created == false, e.second.createErrno == EEXIST,
           e.entries == ["Test.txt"], e.second.content == "UPPER_FILE_CONTENT", inodeA == inodeB {
            return .insensitive
        }
        return .inconclusive
    }
    public static func final(api: Verdict, actual: Verdict) -> Verdict {
        guard actual != .inconclusive else { return .inconclusive }
        return api == .inconclusive || api == actual ? actual : .inconclusive
    }
}

public struct TestLocation: Codable, Sendable {
    public let timestamp: Date
    public var directory: String
    public let label: String
    public var volumeName: String?
}

public struct TestResult: Codable, Identifiable, Sendable {
    public let id: UUID
    public let device: DeviceInfo
    public var test: TestLocation
    public var api: VolumeInfo
    public var actualTest: ActualTest
    public var finalVerdict: Verdict { VerdictResolver.final(api: api.verdict, actual: actualTest.verdict) }
    public var errors: [String] {
        let conflict = api.verdict != .inconclusive && actualTest.verdict != .inconclusive && api.verdict != actualTest.verdict
        return api.errors + actualTest.errors + (conflict ? ["API and actual test disagree"] : [])
    }
    public init(directory: URL, label: String, api: VolumeInfo, actual: ActualTest) {
        id = UUID(); device = .current()
        test = TestLocation(timestamp: Date(), directory: directory.path, label: label, volumeName: api.volumeName)
        self.api = api; actualTest = actual
    }
    enum CodingKeys: String, CodingKey { case id, device, test, api, actualTest, finalVerdict, errors }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); device = try c.decode(DeviceInfo.self, forKey: .device)
        test = try c.decode(TestLocation.self, forKey: .test); api = try c.decode(VolumeInfo.self, forKey: .api)
        actualTest = try c.decode(ActualTest.self, forKey: .actualTest)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(device, forKey: .device)
        try c.encode(test, forKey: .test); try c.encode(api, forKey: .api)
        try c.encode(actualTest, forKey: .actualTest); try c.encode(finalVerdict, forKey: .finalVerdict)
        try c.encode(errors, forKey: .errors)
    }
}
