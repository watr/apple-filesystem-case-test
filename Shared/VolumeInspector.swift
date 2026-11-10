import Foundation
import Darwin

public enum VolumeInspector {
    public static func inspect(_ url: URL) -> VolumeInfo {
        var result = VolumeInfo()
        // Fetch independently: one unavailable property must not discard the others.
        func value(_ key: URLResourceKey) -> URLResourceValues? {
            do { return try url.resourceValues(forKeys: [key]) }
            catch { result.errors.append("\(key.rawValue): \(error)"); return nil }
        }
        result.caseSensitive = value(.volumeSupportsCaseSensitiveNamesKey)?.volumeSupportsCaseSensitiveNames
        // Apple's public API spells this “Preserved”, not “Preserving”.
        result.casePreserving = value(.volumeSupportsCasePreservedNamesKey)?.volumeSupportsCasePreservedNames
        result.volumeName = value(.volumeNameKey)?.volumeName
        result.volumeURL = value(.volumeURLKey)?.volume?.path
        do {
            result.fileSystemAttributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
                .reduce(into: [:]) { $0[$1.key.rawValue] = String(describing: $1.value) }
        } catch { result.errors.append("fileSystemAttributes: \(error)") }
        var info = statfs()
        let descriptor = url.withUnsafeFileSystemRepresentation { Darwin.open($0!, O_RDONLY | O_CLOEXEC) }
        if descriptor >= 0, fstatfs(descriptor, &info) == 0 {
            result.fileSystemID = "\(info.f_fsid.val.0):\(info.f_fsid.val.1)"
        } else { result.errors.append("fstatfs: errno=\(errno) \(String(cString: strerror(errno)))") }
        if descriptor >= 0, Darwin.close(descriptor) != 0 {
            let code = errno
            result.errors.append("close volume descriptor: errno=\(code) \(String(cString: strerror(code)))")
        }
        return result
    }
}
