//
//  GPUReader.swift — best-effort identity; utilization optional via IOReport (no sudo)
//
//  On Apple Silicon, utilization often requires private IOReport channels (as in Stats MIT).
//  We surface name/cores when known; usagePercent stays nil unless a simple IOKit property works.
//  Never invent 0% as "idle".
//

import Foundation
import IOKit

public final class GPUReader: @unchecked Sendable {
    private var cachedName: String?
    private var cachedCores: Int?
    private var cachedAt: Date?
    private let cacheTTL: TimeInterval = 120

    public init() {}

    public func read() -> GPUUsage {
        var usage = GPUUsage()
        let now = Date()
        if let cachedAt, now.timeIntervalSince(cachedAt) < cacheTTL, let name = cachedName {
            usage.name = name
            usage.coreCount = cachedCores
        } else {
            let identity = Self.readIdentity()
            usage.name = identity.name
            usage.coreCount = identity.cores
            cachedName = identity.name
            cachedCores = identity.cores
            cachedAt = now
        }

        // Attempt non-root utilization from IOAccelerator stats (often nil on modern AS).
        if let pct = Self.readUtilizationPercent() {
            usage.usagePercent = pct
            usage.isSupported = true
        } else {
            usage.usagePercent = nil
            usage.isSupported = false
        }
        return usage
    }

    private static func readIdentity() -> (name: String?, cores: Int?) {
        // Prefer brand string style name from GPU registry.
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (sysctlChipFallback(), nil)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any]
            else { continue }

            let model = (props["model"] as? String)
                ?? (props["CFBundleIdentifier"] as? String)
            let cores = (props["gpu-core-count"] as? Int)
                ?? (props["GPUCoreCount"] as? Int)
                ?? (props["cores"] as? Int)
            if let model, !model.isEmpty {
                return (model, cores)
            }
        }
        return (sysctlChipFallback(), nil)
    }

    private static func sysctlChipFallback() -> String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return "Apple GPU"
        }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0) == 0 else {
            return "Apple GPU"
        }
        let brand = String(cString: buf)
        // "Apple M4 Pro" → treat as GPU name family.
        return brand.isEmpty ? "Apple GPU" : brand
    }

    private static func readUtilizationPercent() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any]
            else { continue }

            if let stats = props["PerformanceStatistics"] as? [String: Any] {
                if let u = stats["Device Utilization %"] as? Int {
                    return Double(min(100, max(0, u)))
                }
                if let u = stats["Device Utilization %"] as? Double {
                    return min(100, max(0, u))
                }
                if let u = stats["GPU Activity(%)"] as? Int {
                    return Double(min(100, max(0, u)))
                }
                if let n = stats["Device Utilization %"] as? NSNumber {
                    return min(100, max(0, n.doubleValue))
                }
            }
        }
        return nil
    }
}
