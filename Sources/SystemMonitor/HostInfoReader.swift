//
//  HostInfoReader.swift — model / chip / uptime / OS (slow-changing)
//

import Foundation
import Darwin
import IOKit

public final class HostInfoReader: @unchecked Sendable {
    private var cached: HostInfo?
    private var cachedAt: Date?
    private let cacheTTL: TimeInterval = 60

    public init() {}

    public func read(force: Bool = false) -> HostInfo {
        let now = Date()
        if !force, let cached, let cachedAt, now.timeIntervalSince(cachedAt) < cacheTTL {
            var copy = cached
            copy.uptimeSeconds = Self.uptimeSeconds()
            return copy
        }
        var info = HostInfo()
        info.model = Self.friendlyModel()
        info.chip = Self.sysctlString("machdep.cpu.brand_string")
        if info.chip?.isEmpty != false {
            info.chip = Self.sysctlString("hw.model")
        }
        let v = Foundation.ProcessInfo.processInfo.operatingSystemVersion
        info.osVersion = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        info.uptimeSeconds = Self.uptimeSeconds()
        info.logicalCPU = Self.sysctlInt("hw.logicalcpu")
        info.totalMemoryBytes = Foundation.ProcessInfo.processInfo.physicalMemory
        cached = info
        cachedAt = now
        return info
    }

    private static func uptimeSeconds() -> UInt64 {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return 0 }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
        return UInt64(max(0, Date().timeIntervalSince(bootDate)))
    }

    private static func friendlyModel() -> String {
        if let name = ioModelName(), !name.isEmpty {
            return name
        }
        return sysctlString("hw.model") ?? "Mac"
    }

    private static func ioModelName() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let data = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
              let raw = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value = 0
        var size = MemoryLayout<Int>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : 0
    }
}
