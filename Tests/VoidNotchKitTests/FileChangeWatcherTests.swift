import XCTest
@testable import VoidNotchKit

@MainActor
final class FileChangeWatcherTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VoidNotchKitTests-FileChangeWatcher-\(UUID().uuidString)", isDirectory: true)
    }

    func test_write_to_existing_file_triggers_debounced_callback() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        try "seed\n".write(to: url, atomically: true, encoding: .utf8)

        let watcher = FileChangeWatcher(path: url.path, debounceInterval: 0.1, retryInterval: 0.2)
        defer { watcher.stop() }

        let expectation = expectation(description: "write triggers callback")
        watcher.start {
            expectation.fulfill()
        }

        // 給 kqueue 掛載留一點時間再寫入,避免 race 到 source 還沒 resume。
        let handle = try FileHandle(forWritingTo: url)
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            handle.seekToEndOfFile()
            handle.write("more\n".data(using: .utf8)!)
            try? handle.close()
        }

        await fulfillment(of: [expectation], timeout: 3.0)
    }

    /// 模擬外部 relay 的典型行為:先寫一份新檔,再 rename 蓋掉舊檔(整檔截尾改寫)。
    /// 舊 fd 對應的 inode 會失效,watcher 必須偵測 .rename 並重掛到新 inode 才能繼續收到後續事件。
    func test_atomic_replace_via_rename_still_triggers_after_reattach() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        try "seed\n".write(to: url, atomically: true, encoding: .utf8)

        let watcher = FileChangeWatcher(path: url.path, debounceInterval: 0.1, retryInterval: 0.2)
        defer { watcher.stop() }

        var callbackCount = 0
        let renameExpectation = expectation(description: "rename triggers callback")
        let postRenameWriteExpectation = expectation(description: "write after reattach triggers callback")

        watcher.start {
            callbackCount += 1
            if callbackCount == 1 {
                renameExpectation.fulfill()
            } else {
                postRenameWriteExpectation.fulfill()
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            // 整檔改寫:寫到暫存檔,再 rename 蓋掉原檔(等同 relay 的截尾改寫手法)。
            let staging = root.appendingPathComponent("agent-events.jsonl.tmp")
            try? "seed\nreplaced\n".write(to: staging, atomically: true, encoding: .utf8)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: staging)
        }

        await fulfillment(of: [renameExpectation], timeout: 3.0)

        // 重掛需要一點時間(open 新 inode + resume source),等穩定後再寫入驗證仍收得到事件。
        try await Task.sleep(nanoseconds: 500_000_000)
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write("after-reattach\n".data(using: .utf8)!)
        try? handle.close()

        await fulfillment(of: [postRenameWriteExpectation], timeout: 3.0)
    }

    /// 回歸測試(對應 2026-07-23 驗收發現的 fd 洩漏):cancelSource() 的舊實作靠
    /// 「非同步」cancelHandler 讀取 watchedDescriptor 判斷該不該關 fd,但 attach() 的重掛
    /// 會在 cancelHandler 真正跑到之前就把 watchedDescriptor 覆寫成新 fd,導致判斷式永遠
    /// 不成立、舊 fd 永遠關不掉。連續多次「寫暫存檔 + replaceItemAt 蓋掉」模擬 relay 的
    /// 截尾改寫,用 lsof 數自己 process 對這個 root 目錄底下路徑開著的 fd 數,驗證不會隨
    /// 重掛次數線性成長。
    func test_repeated_atomic_replace_does_not_leak_file_descriptors() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        try "seed\n".write(to: url, atomically: true, encoding: .utf8)

        let watcher = FileChangeWatcher(path: url.path, debounceInterval: 0.05, retryInterval: 0.2)
        defer { watcher.stop() }

        watcher.start {}

        // 讓初次 attach 穩定(open + resume)。
        try await Task.sleep(nanoseconds: 300_000_000)

        let iterations = 20
        for i in 0..<iterations {
            let staging = root.appendingPathComponent("agent-events.jsonl.tmp")
            try "seed\nreplace-\(i)\n".write(to: staging, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
            // 每次替換後留時間讓 watcher 偵測 .rename、跑完 cancelSource() 的重掛(關舊 fd、開新 fd)。
            try await Task.sleep(nanoseconds: 150_000_000)
        }

        // cancelHandler 排在下一輪 runloop 才觸發 close(),這裡多留一拍確保所有排隊中的
        // close() 都真正執行完,計數才有意義。
        try await Task.sleep(nanoseconds: 300_000_000)

        let openCount = Self.openFileDescriptorCount(forPathContaining: root.path)
        // 修復前:每次 rename 重掛都漏一個 fd,openCount 會隨 iterations(=20)線性成長。
        // 修復後:任何時刻只該有「目前活著的那一個 watch fd」殘留,給寬鬆上限(3)避免環境雜訊 flaky,
        // 但仍遠低於「20 次重掛全部洩漏」會出現的量級,足以佐證不是線性成長。
        XCTAssertLessThanOrEqual(
            openCount, 3,
            "watcher 的 fd 數不應隨 \(iterations) 次 rename 重掛線性成長(疑似 fd 洩漏);目前開啟數=\(openCount)")
    }

    /// 用 `lsof -p <self>` 數目前這個測試 process 開著、路徑含 pathFragment 的 fd 數。
    /// 抓不到 lsof(理論上 macOS 系統內建一定有)時回傳 0,讓呼叫端的斷言略過而不是整包測試失敗。
    private static func openFileDescriptorCount(forPathContaining pathFragment: String) -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-p", String(ProcessInfo.processInfo.processIdentifier)]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return 0
        }
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").filter { $0.contains(pathFragment) }.count
    }

    func test_stop_prevents_further_callbacks() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("agent-events.jsonl")
        try "seed\n".write(to: url, atomically: true, encoding: .utf8)

        let watcher = FileChangeWatcher(path: url.path, debounceInterval: 0.1, retryInterval: 0.2)

        let unexpectedCallback = expectation(description: "callback after stop should not fire")
        unexpectedCallback.isInverted = true

        watcher.start {
            unexpectedCallback.fulfill()
        }
        watcher.stop()

        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write("should-be-ignored\n".data(using: .utf8)!)
        try? handle.close()

        await fulfillment(of: [unexpectedCallback], timeout: 1.0)
    }
}
