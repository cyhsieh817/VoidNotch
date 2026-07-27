//
//  FileChangeWatcher.swift — kqueue/DispatchSource 檔案異動監看器
//
//  監看單一檔案路徑，寫入/延展/刪除/改名皆觸發 debounce 過的回呼。
//  外部 relay 常見行為是「整檔截尾改寫」：先寫新檔再 rename 蓋掉舊檔，
//  或直接刪除重建——這類操作在 BSD 語意下會讓舊 fd 的 vnode 失效，
//  必須收到 .delete/.rename 後關掉舊 fd、對新 inode 重新掛載監看，
//  否則之後的寫入事件會靜默消失。零 SwiftUI 依賴，供 PollingDriver 兜底之外的
//  近即時觸發使用。
//

import Foundation

@MainActor
public final class FileChangeWatcher {
    private let path: String
    private let debounceInterval: TimeInterval
    private let retryInterval: TimeInterval
    private let fileManager: FileManager

    // 這四個只在 MainActor 隔離的方法或 MainActor.assumeIsolated 區塊內變動(main queue 同步),
    // 標 nonisolated(unsafe) 純粹是為了讓 deinit(必為 nonisolated)能同步清 GCD 資源避免 fd 洩漏;
    // 不代表真的有跨執行緒併發存取。
    private nonisolated(unsafe) var source: DispatchSourceFileSystemObject?
    private nonisolated(unsafe) var watchedDescriptor: Int32 = -1
    private nonisolated(unsafe) var retryTimer: DispatchSourceTimer?
    private nonisolated(unsafe) var debounceWorkItem: DispatchWorkItem?
    private var onChange: (@MainActor () -> Void)?
    private var isRunning = false

    /// - Parameters:
    ///   - path: 要監看的檔案絕對路徑。
    ///   - debounceInterval: 連續事件合併視窗，預設 150ms（落在 100–200ms 要求區間）。
    ///   - retryInterval: 檔案暫時不存在時的重掛間隔，預設 1 秒。
    public init(
        path: String,
        debounceInterval: TimeInterval = 0.15,
        retryInterval: TimeInterval = 1.0,
        fileManager: FileManager = .default)
    {
        self.path = path
        self.debounceInterval = debounceInterval
        self.retryInterval = retryInterval
        self.fileManager = fileManager
    }

    deinit {
        source?.setEventHandler {}
        source?.setCancelHandler {}
        source?.cancel()
        retryTimer?.setEventHandler {}
        retryTimer?.cancel()
        debounceWorkItem?.cancel()
        // cancelHandler 上面已清空,這裡兜底避免任何殘留路徑忘了關 fd。
        if watchedDescriptor >= 0 {
            close(watchedDescriptor)
            watchedDescriptor = -1
        }
    }

    /// 啟動監看；重覆呼叫會先 stop() 再重掛。回呼固定跑在 MainActor。
    public func start(onChange: @escaping @MainActor () -> Void) {
        stop()
        isRunning = true
        self.onChange = onChange
        attach()
    }

    /// 停止監看並釋放所有資源（source、fd、計時器）。
    public func stop() {
        isRunning = false
        cancelSource()
        cancelRetryTimer()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        onChange = nil
    }

    /// 供 PollingDriver tick 之類的既有輪詢路徑順便呼叫，檔案暫時不存在時可用它補一次重掛嘗試。
    public func retryAttachIfNeeded() {
        guard isRunning, source == nil else { return }
        attach()
    }

    // MARK: - 掛載 / 重掛

    private func attach() {
        cancelSource()

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRetry()
            return
        }
        watchedDescriptor = fd

        let mask: DispatchSource.FileSystemEvent = [.write, .extend, .delete, .rename]
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: mask,
            queue: .main)

        newSource.setEventHandler { [weak self] in
            // DispatchSource 的 event handler 固定跑在建立時指定的 queue(.main)上，
            // 與 MainActor 的執行緒身分一致,用 assumeIsolated 同步進入避免多餘一跳。
            MainActor.assumeIsolated {
                self?.handleEvent(from: newSource)
            }
        }
        // 這個 fd 的關閉責任交給「未來取代它的 cancelSource() 呼叫」或 deinit,
        // 這裡不設 cancelHandler——理由見 cancelSource()。

        source = newSource
        cancelRetryTimer()
        newSource.resume()
    }

    private func handleEvent(from firedSource: DispatchSourceFileSystemObject) {
        guard isRunning else { return }
        let flags = firedSource.data

        if flags.contains(.delete) || flags.contains(.rename) {
            // 舊 inode 已經失效(截尾改寫/改名蓋檔常見手法):關掉舊 fd,對新內容重掛。
            // 先通知一次(截尾當下的內容值得反映),再嘗試重新開檔;開不到就交給重試計時器。
            debounceNotify()
            attach()
            return
        }

        debounceNotify()
    }

    /// 取消目前的 source 並關閉它對應的 fd。
    ///
    /// 陷阱(已修過一次):cancelHandler 是「非同步」在下一輪 runloop 才觸發。若在這裡
    /// 只是 nil 掉 `source` 就呼叫 `cancel()`,而關 fd 的邏輯留到之後才跑、又用
    /// `watchedDescriptor == fd` 這種「當下讀取」去判斷該不該關——那麼一旦呼叫端
    /// (attach() 的重掛路徑)在 cancelHandler 真正觸發前就把 `watchedDescriptor`
    /// 覆寫成新 fd,判斷式永遠不成立,舊 fd 就再也關不掉(重掛一次漏一個 fd)。
    /// 修法:在「同步」的當下就把要關的 fd 從 `watchedDescriptor` 捕捉出來並立刻
    /// 清空欄位,cancelHandler 只認捕捉到的區域變數、無條件 close——不依賴之後任何
    /// 欄位狀態,自然不怕被後續 attach() 覆寫搶跑。fd 號碼在自己被 close 前不會被
    /// 系統重新分配給新的 open(),所以「無條件關閉捕捉到的舊 fd」是安全的。
    private func cancelSource() {
        guard let current = source else { return }
        source = nil
        let fdToClose = watchedDescriptor
        watchedDescriptor = -1
        current.setEventHandler {}
        current.setCancelHandler {
            // 純 C 呼叫,不碰 self/任何 actor 隔離狀態,故不需要 MainActor.assumeIsolated。
            if fdToClose >= 0 {
                close(fdToClose)
            }
        }
        current.cancel()
    }

    // MARK: - 重試(檔案暫時不存在)

    private func scheduleRetry() {
        guard isRunning else { return }
        cancelRetryTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + retryInterval, repeating: retryInterval)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.source == nil else { return }
                self.attach()
            }
        }
        retryTimer = timer
        timer.resume()
    }

    private func cancelRetryTimer() {
        retryTimer?.setEventHandler {}
        retryTimer?.cancel()
        retryTimer = nil
    }

    // MARK: - Debounce

    private func debounceNotify() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.onChange?()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
