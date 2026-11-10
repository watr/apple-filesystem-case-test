import Foundation
import Darwin

public protocol FileProbing {
    func run(in directory: URL) -> ActualTest
}

public struct FileSystemTester {
    private let probe: any FileProbing
    public init(probe: any FileProbing = POSIXFileProbe()) { self.probe = probe }
    public func test(directory: URL, label: String) -> TestResult {
        let api = VolumeInspector.inspect(directory)
        return TestResult(directory: directory, label: label, api: api, actual: probe.run(in: directory))
    }
}

public struct POSIXFileProbe: FileProbing {
    public init() {}
    public func run(in directory: URL) -> ActualTest {
        var result = ActualTest()
        func error(_ operation: String, _ code: Int32 = errno) {
            result.errors.append("\(operation): errno=\(code) \(String(cString: strerror(code)))")
        }
        func closeFD(_ fd: Int32, _ name: String) {
            // Do not retry close(): the descriptor may already have been released.
            if Darwin.close(fd) != 0 { error("close \(name)") }
        }
        let parent = directory.withUnsafeFileSystemRepresentation {
            Darwin.open($0!, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard parent >= 0 else { error("open target directory"); return result }
        let name = "CaseSensitivityTester-\(UUID().uuidString)"
        result.temporaryDirectory = name
        guard mkdirat(parent, name, 0o700) == 0 else {
            error("mkdirat dedicated directory"); closeFD(parent, "parent"); return result
        }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            error("openat dedicated directory")
            // Leave it for manual inspection if its identity cannot be established.
            result.cleanupSucceeded = false
            closeFD(parent, "parent"); return result
        }
        var identity = stat()
        let hasIdentity = fstat(fd, &identity) == 0
        if !hasIdentity { error("fstat dedicated directory") }

        func create(_ filename: String, _ content: String) -> FileEvidence {
            let file = openat(fd, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard file >= 0 else {
                let code = errno
                if !(filename == "test.txt" && code == EEXIST) { error("openat \(filename)", code) }
                return FileEvidence(created: false, createErrno: code)
            }
            var evidence = FileEvidence(created: true, createErrno: 0)
            let data = Array(content.utf8)
            data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let n = Darwin.write(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { error("write \(filename)", n == 0 ? EIO : errno); break }
                    offset += n
                }
            }
            if fsync(file) != 0 { error("fsync \(filename)") }
            closeFD(file, filename)
            // Retain creation success even if write/close failed; errors invalidate the verdict.
            evidence.content = nil
            return evidence
        }
        result.first = create("Test.txt", "UPPER_FILE_CONTENT")
        result.second = create("test.txt", "lower_file_content")

        let copy = dup(fd)
        if copy < 0 { error("dup directory") }
        else if let stream = fdopendir(copy) {
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    if errno != 0 { error("readdir") }
                    break
                }
                let entryName = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if entryName != "." && entryName != ".." { result.entries.append(entryName) }
            }
            if closedir(stream) != 0 { error("closedir") }
            result.entries.sort()
        } else { error("fdopendir"); closeFD(copy, "directory copy") }

        func inspect(_ filename: String, _ initial: FileEvidence) -> FileEvidence {
            var evidence = initial
            var metadata = stat()
            guard fstatat(fd, filename, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else {
                error("stat \(filename)"); return evidence
            }
            guard metadata.st_mode & S_IFMT == S_IFREG else {
                result.errors.append("\(filename): unexpected non-regular file"); return evidence
            }
            evidence.inode = UInt64(metadata.st_ino)
            evidence.deviceID = Int64(metadata.st_dev)
            let file = openat(fd, filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard file >= 0 else { error("read open \(filename)"); return evidence }
            var opened = stat()
            if fstat(file, &opened) != 0 { error("fstat opened \(filename)") }
            else if opened.st_ino != metadata.st_ino || opened.st_dev != metadata.st_dev {
                result.errors.append("\(filename): identity changed during read")
            }
            var bytes = [UInt8](repeating: 0, count: 256)
            var data = Data()
            while true {
                let count = Darwin.read(file, &bytes, bytes.count)
                if count < 0 && errno == EINTR { continue }
                if count < 0 { error("read \(filename)"); break }
                if count == 0 { evidence.content = String(data: data, encoding: .utf8); break }
                data.append(contentsOf: bytes.prefix(count))
                if data.count > 4096 { result.errors.append("\(filename): unexpected content size"); break }
            }
            closeFD(file, filename)
            return evidence
        }
        result.first = inspect("Test.txt", result.first)
        result.second = inspect("test.txt", result.second)
        if let a = result.first.inode, let b = result.second.inode,
           let da = result.first.deviceID, let db = result.second.deviceID {
            result.differentInodes = a != b
            result.independentFiles = a != b || da != db
        }
        if let a = result.first.content, let b = result.second.content {
            result.contentsVerified = a == "UPPER_FILE_CONTENT" &&
                b == (result.second.created == true ? "lower_file_content" : "UPPER_FILE_CONTENT")
        }

        // Delete only known files we successfully created, relative to the directory descriptor.
        var cleaned = true
        if result.first.created == true && unlinkat(fd, "Test.txt", 0) != 0 {
            error("unlinkat Test.txt"); cleaned = false
        }
        if result.second.created == true && unlinkat(fd, "test.txt", 0) != 0 {
            error("unlinkat test.txt"); cleaned = false
        }
        var current = stat()
        if hasIdentity, fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
           current.st_ino == identity.st_ino, current.st_dev == identity.st_dev {
            // AT_REMOVEDIR fails on unexpected entries instead of recursively deleting them.
            if unlinkat(parent, name, AT_REMOVEDIR) != 0 { error("remove dedicated directory"); cleaned = false }
        } else {
            result.errors.append("Cleanup refused: dedicated directory identity unavailable or changed")
            cleaned = false
        }
        closeFD(fd, "dedicated directory"); closeFD(parent, "parent")
        result.cleanupSucceeded = cleaned
        return result
    }
}
