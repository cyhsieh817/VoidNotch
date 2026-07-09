//
//  DiskIOReader.swift — aggregate disk read/write rate via IOKit IOBlockStorageDriver
//

import Foundation
import IOKit

public final class DiskIOReader: @unchecked Sendable {
    private var prevRead: UInt64?
    private var prevWrite: UInt64?
    private var prevAt: Date?

    public init() {}

    public func read() -> DiskIO {
        let now = Date()
        let (readBytes, writeBytes) = Self.totalBytes()
        defer {
            prevRead = readBytes
            prevWrite = writeBytes
            prevAt = now
        }

        guard let prevRead, let prevWrite, let prevAt else {
            return DiskIO()
        }
        let dt = now.timeIntervalSince(prevAt)
        guard dt > 0.05 else { return DiskIO() }

        let readDelta = Double(readBytes &- prevRead)
        let writeDelta = Double(writeBytes &- prevWrite)
        let readMBps = max(0, readDelta / dt / 1_048_576)
        let writeMBps = max(0, writeDelta / dt / 1_048_576)
        return DiskIO(readMBps: readMBps, writeMBps: writeMBps)
    }

    /// Inject counters for tests (same differential path).
    public func read(currentRead: UInt64, currentWrite: UInt64, now: Date) -> DiskIO {
        defer {
            prevRead = currentRead
            prevWrite = currentWrite
            prevAt = now
        }
        guard let prevRead, let prevWrite, let prevAt else {
            return DiskIO()
        }
        let dt = now.timeIntervalSince(prevAt)
        guard dt > 0 else { return DiskIO() }
        let readMBps = Double(currentRead &- prevRead) / dt / 1_048_576
        let writeMBps = Double(currentWrite &- prevWrite) / dt / 1_048_576
        return DiskIO(readMBps: max(0, readMBps), writeMBps: max(0, writeMBps))
    }

    private static func totalBytes() -> (UInt64, UInt64) {
        var readTotal: UInt64 = 0
        var writeTotal: UInt64 = 0

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any]
            else {
                continue
            }
            if let r = stats["Bytes (Read)"] as? UInt64 {
                readTotal &+= r
            } else if let r = stats["BytesRead"] as? UInt64 {
                readTotal &+= r
            } else if let n = stats["Bytes (Read)"] as? NSNumber {
                readTotal &+= n.uint64Value
            }
            if let w = stats["Bytes (Write)"] as? UInt64 {
                writeTotal &+= w
            } else if let w = stats["BytesWritten"] as? UInt64 {
                writeTotal &+= w
            } else if let n = stats["Bytes (Write)"] as? NSNumber {
                writeTotal &+= n.uint64Value
            }
        }
        return (readTotal, writeTotal)
    }
}
