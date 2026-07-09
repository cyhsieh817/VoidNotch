//
//  NetworkReader.swift — primary interface rx/tx rate via getifaddrs AF_LINK
//

import Foundation
import Darwin

public final class NetworkReader: @unchecked Sendable {
    private struct Counters {
        var rx: UInt64
        var tx: UInt64
        var name: String
    }

    private var prev: Counters?
    private var prevAt: Date?

    public init() {}

    public func read() -> NetworkUsage {
        let now = Date()
        guard let current = Self.primaryCounters() else {
            return NetworkUsage()
        }
        defer {
            prev = current
            prevAt = now
        }
        guard let prev, let prevAt, prev.name == current.name else {
            return NetworkUsage(interface: current.name, rxMBps: 0, txMBps: 0)
        }
        let dt = now.timeIntervalSince(prevAt)
        guard dt > 0.05 else {
            return NetworkUsage(interface: current.name, rxMBps: 0, txMBps: 0)
        }
        let rxMBps = Double(current.rx &- prev.rx) / dt / 1_048_576
        let txMBps = Double(current.tx &- prev.tx) / dt / 1_048_576
        return NetworkUsage(interface: current.name, rxMBps: max(0, rxMBps), txMBps: max(0, txMBps))
    }

    /// Test injection path.
    public func read(name: String, rx: UInt64, tx: UInt64, now: Date) -> NetworkUsage {
        let current = Counters(rx: rx, tx: tx, name: name)
        defer {
            prev = current
            prevAt = now
        }
        guard let prev, let prevAt, prev.name == name else {
            return NetworkUsage(interface: name, rxMBps: 0, txMBps: 0)
        }
        let dt = now.timeIntervalSince(prevAt)
        guard dt > 0 else { return NetworkUsage(interface: name, rxMBps: 0, txMBps: 0) }
        return NetworkUsage(
            interface: name,
            rxMBps: max(0, Double(rx &- prev.rx) / dt / 1_048_576),
            txMBps: max(0, Double(tx &- prev.tx) / dt / 1_048_576))
    }

    private static func primaryCounters() -> Counters? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }

        var best: Counters?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            // Prefer en* (Wi-Fi/Ethernet); skip utun/awdl/llw/bridge noise when possible.
            if name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("utun")
                || name.hasPrefix("bridge") || name.hasPrefix("ap") || name.hasPrefix("stf")
            {
                continue
            }
            let data = unsafeBitCast(ptr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>?.self)
            guard let data else { continue }
            let counters = Counters(
                rx: UInt64(data.pointee.ifi_ibytes),
                tx: UInt64(data.pointee.ifi_obytes),
                name: name)
            if name.hasPrefix("en") {
                if best == nil || (best?.name.hasPrefix("en") != true) || counters.rx + counters.tx > (best!.rx + best!.tx) {
                    best = counters
                }
            } else if best == nil {
                best = counters
            }
        }
        return best
    }
}
