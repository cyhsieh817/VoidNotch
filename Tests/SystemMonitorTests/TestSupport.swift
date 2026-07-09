//
//  TestSupport.swift — 測試輔助：讀 sysctl 地面真值
//

import Foundation

enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    /// 邏輯核心數（地面真值，比對 CPUReader.perCore.count）。
    static var logicalCPU: Int { int("hw.logicalcpu") ?? 0 }
    /// 實體記憶體位元組（地面真值，比對 RAMReader.total）。
    static var memSize: Int { int("hw.memsize") ?? 0 }
    static var pCores: Int { int("hw.perflevel0.logicalcpu") ?? 0 }
    static var eCores: Int { int("hw.perflevel1.logicalcpu") ?? 0 }
}
