//
//  DiskReader.swift — root volume capacity via statfs (MIT-style, inspired by Stats)
//

import Foundation

public final class DiskReader: @unchecked Sendable {
    private let path: String

    public init(path: String = "/") {
        self.path = path
    }

    public func read() -> DiskUsage {
        var s = statfs()
        guard statfs(path, &s) == 0 else {
            return DiskUsage(mount: path, totalBytes: 0, freeBytes: 0)
        }
        let blockSize = UInt64(s.f_bsize)
        let total = UInt64(s.f_blocks) * blockSize
        // Prefer non-privileged free (f_bavail) for "user usable" space.
        let free = UInt64(s.f_bavail) * blockSize
        return DiskUsage(mount: path, totalBytes: total, freeBytes: free)
    }
}
