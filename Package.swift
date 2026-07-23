// swift-tools-version: 6.0
import PackageDescription

// VoidNotch — macOS Notch 系統監控 + AI Token 追蹤
//
// 本 Package 拆兩種 target：
//  - 純資料層（SystemMonitor / CSensors / VoidNotchKit）：零 SwiftUI，CommandLineTools 即可 `swift build` / `swift test`
//  - App 層（executable target `VoidNotch`，源碼在 App/）：依賴 DynamicNotchKit（SwiftUI `@Entry` 巨集），
//    須裝有完整 Xcode 工具鏈（xcode-select 指向 Xcode.app），但不需開 Xcode GUI：
//     swift build --product VoidNotch          # CLI 編譯 app
//     scripts/make_app.sh [--install]          # 免 Xcode 打包成 VoidNotch.app 並掛載
//
// 在僅有 CommandLineTools 的機器上，只建可驗證的資料層與自測：
//     swift build --target SystemMonitor
//     swift run vn-selftest
//     swift run vn-probe

let package = Package(
    name: "VoidNotch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SystemMonitor", targets: ["SystemMonitor"]),
        .library(name: "VoidNotchSpeechKit", targets: ["VoidNotchSpeechKit"]),
        .library(name: "VoidNotchKit", targets: ["VoidNotchKit"]),
        .executable(name: "vn-probe", targets: ["vn-probe"]),
        .executable(name: "VoidNotch", targets: ["VoidNotch"]),
        .executable(name: "VoidNotchDebug", targets: ["VoidNotchDebug"]),
    ],
    dependencies: [
        // revision 對齊 VoidNotch.xcodeproj 的 Package.resolved，兩條建置路徑用同一組依賴。
        .package(url: "https://github.com/MrKai77/DynamicNotchKit.git", revision: "cd0b3e52d537db115ad3a9d89601f20e0bee8d27"),
        .package(url: "https://github.com/steipete/CodexBar", revision: "ef8007fc16cefaddb7afdc05725a127f76538e0c"),
    ],
    targets: [
        // Apple Silicon IOHID 溫度感測器橋接（Obj-C，私有 IOKit 符號）— 移植自 Stats reader.m
        .target(
            name: "CSensors",
            path: "Sources/CSensors"
        ),
        // 純資料層：CPU / RAM / 溫度。零 SwiftUI，零外部依賴。
        .target(
            name: "SystemMonitor",
            dependencies: ["CSensors"],
            path: "Sources/SystemMonitor"
        ),
        // 題目選項語音辨識的窄化依賴；不得依賴 production kit 或其他專案 target。
        .target(
            name: "VoidNotchSpeechKit",
            path: "Sources/VoidNotchSpeechKit"
        ),
        // UI-free 純邏輯層:token 模型/格式化、agent JSONL 解析、佈局與並行 helper。
        // 與 SystemMonitor 同樣零 SwiftUI,CommandLineTools 可 `swift test`。
        .target(
            name: "VoidNotchKit",
            dependencies: ["SystemMonitor", "VoidNotchSpeechKit"],
            path: "Sources/VoidNotchKit"
        ),
        .testTarget(
            name: "VoidNotchKitTests",
            dependencies: ["VoidNotchKit"],
            path: "Tests/VoidNotchKitTests"
        ),
        // 驗證探針：印出即時指標，供與 Activity Monitor 對核。
        .executableTarget(
            name: "vn-probe",
            dependencies: ["SystemMonitor"],
            path: "Sources/vn-probe"
        ),
        // 單元測試（XCTest）：須完整 Xcode toolchain 才能 `swift test`。
        // 目前 CommandLineTools 環境缺 XCTest；安裝 Xcode 後見 docs/guides/2026-06-21-xcode-testing-guide.md。
        .testTarget(
            name: "SystemMonitorTests",
            dependencies: ["SystemMonitor"],
            path: "Tests/SystemMonitorTests"
        ),
        // 自帶斷言的自測：等價檢查，但 CommandLineTools 下 `swift run vn-selftest` 即可當場驗證。
        .executableTarget(
            name: "vn-selftest",
            dependencies: ["SystemMonitor"],
            path: "Sources/vn-selftest"
        ),
        // App 層：SwiftUI + DynamicNotchKit 外殼。需完整 Xcode 工具鏈（@Entry 巨集），
        // 但可純 CLI 建置；打包成 .app 見 scripts/make_app.sh。
        .executableTarget(
            name: "VoidNotch",
            dependencies: [
                "SystemMonitor",
                "VoidNotchKit",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
                .product(name: "CodexBarCore", package: "CodexBar"),
            ],
            path: "App",
            exclude: ["README.md", "VoidNotch.entitlements"]
        ),
        .executableTarget(
            name: "VoidNotchDebug",
            dependencies: ["VoidNotchSpeechKit"],
            path: "DebugApp"
        ),
    ]
)
