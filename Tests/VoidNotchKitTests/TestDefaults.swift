import Foundation
import XCTest

extension XCTestCase {
    /// 建立隔離的測試用 UserDefaults。
    ///
    /// suite 名為「用途 + 當前測試方法」，**刻意不帶 `UUID()`**。三件事同時要成立：
    ///
    /// 1. **不能無限長檔案**：`removePersistentDomain(forName:)` 只清空內容，
    ///    **不刪除** `~/Library/Preferences/<suite>.plist`。過去每跑一次測試就留下
    ///    數百個 42 bytes 空殼，實測累積到 4884 個。
    /// 2. **刪檔救不了**：cfprefsd 會在**測試程序死掉之後**才把 domain 回寫。
    ///    實測 `swift test` 回傳當下殘留 26 個，t+10s 漲到 38 並穩定——
    ///    teardown 與 `atexit` 都在程序內，贏不了這場競速。
    /// 3. **不能共用固定名**：`swift test --parallel` 會把**每個測試方法**丟進獨立程序。
    ///    若 label 只到類別層級（例如 10 個方法共用 `DisplaySelectionStore`），
    ///    那些程序會互相覆寫彼此的值，實測 4 個測試類別失敗；序列模式看不出來。
    ///
    /// 把測試方法名納入 suite 名同時解掉三者：名稱集合有界（每個「用途×測試」一個檔，
    /// 重複執行沿用同一檔，不再成長），而平行執行時各程序跑不同方法、名稱天然不撞。
    /// `XCTestCase.name` 在 `setUp` 執行前就已設定，故 setUp 內呼叫也拿得到正確方法名。
    func makeTestDefaults(_ label: String) -> UserDefaults {
        let name = "VoidNotch.Tests.\(label).\(Self.testScopeToken(from: self.name))"
        let defaults = UserDefaults(suiteName: name)!
        // 取得當下即清空：隔離性由此保證，不靠每次換新名字。
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            // 內容清掉即可；plist 空殼會被下次同名執行沿用，不需（也無法）刪除。
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        return defaults
    }

    /// 把 `XCTestCase.name`（形如 `-[FooTests test_bar]`）縮成適合當 suite 名一段的 token。
    private static func testScopeToken(from rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let token = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: ".")
        return token.isEmpty ? "unscoped" : token
    }
}
