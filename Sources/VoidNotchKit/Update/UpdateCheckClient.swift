//
//  UpdateCheckClient.swift — 靜態版本資訊下載 client
//

import Foundation

/// 讀取靜態 version.json 的最小網路 client。
public struct UpdateCheckClient: Sendable {
    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// 下載並解碼最新版本資訊；所有錯誤交由呼叫端處理。
    public func fetchLatest() async throws -> AppUpdateInfo {
        let (data, response) = try await session.data(from: endpoint)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(AppUpdateInfo.self, from: data)
    }
}
