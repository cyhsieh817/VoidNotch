#if canImport(CodexBarCore)
import AppKit
import CodexBarCore
import CryptoKit
import Foundation
import Network
import Security

final class AntigravityOAuthLoginController {
    enum Outcome {
        case success(String)
        case cancelled
        case timedOut
        case failed(String)
    }

    struct Result {
        let outcome: Outcome
    }

    // Keep this controller-specific list complete even though the current Core
    // config exposes only the two scopes needed by its usage fetcher.
    static let authorizationScopes = [
        "openid",
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs",
    ]

    private let accountManager: CodexBarTokenAccountManager

    init(accountManager: CodexBarTokenAccountManager = CodexBarTokenAccountManager()) {
        self.accountManager = accountManager
    }

    @MainActor
    func run(timeout: TimeInterval = 5 * 60) async -> Result {
        guard let oauthClient = AntigravityOAuthConfig.resolvedClient() else {
            return Result(outcome: .failed(AntigravityOAuthConfig.missingCredentialsMessage))
        }
        guard timeout > 0 else {
            return Result(outcome: .timedOut)
        }

        do {
            let codeVerifier = try Self.makeCodeVerifier()
            let codeChallenge = Self.codeChallenge(for: codeVerifier)
            let state = try Self.makeState()
            let loopbackServer = AntigravityLoopbackServer(expectedState: state)
            defer { loopbackServer.stop() }

            let redirectURI = try await loopbackServer.start()
            let authURL = try Self.makeAuthorizationURL(
                redirectURI: redirectURI,
                state: state,
                codeChallenge: codeChallenge,
                oauthClient: oauthClient)

            guard NSWorkspace.shared.open(authURL) else {
                return Result(outcome: .failed("無法開啟 Google 登入頁面。"))
            }

            let callback = try await Self.waitForCallback(
                from: loopbackServer,
                timeout: timeout)
            loopbackServer.stop()
            guard callback.returnedState == state else {
                return Result(outcome: .failed("Google 登入 state 不符，請重試。"))
            }

            if let callbackError = callback.error,
               !callbackError.isEmpty
            {
                if callbackError == "access_denied" {
                    return Result(outcome: .cancelled)
                }
                return Result(outcome: .failed("Google 登入失敗：\(callbackError)"))
            }

            guard let code = callback.code?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !code.isEmpty
            else {
                return Result(outcome: .failed("Google 未回傳授權碼，請重試。"))
            }

            let tokenResponse = try await Self.exchangeCodeForTokens(
                code: code,
                codeVerifier: codeVerifier,
                redirectURI: redirectURI,
                oauthClient: oauthClient)
            let email = try await Self.fetchUserEmail(accessToken: tokenResponse.accessToken)
            let credentials = AntigravityOAuthCredentials(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                expiryDate: tokenResponse.expiresIn.map {
                    Date().addingTimeInterval(TimeInterval($0))
                },
                idToken: tokenResponse.idToken,
                email: email,
                projectID: nil,
                clientID: oauthClient.clientID,
                clientSecret: oauthClient.clientSecret)

            _ = try accountManager.upsertAntigravityOAuthAccount(
                credentials,
                labelOverride: email)
            return Result(outcome: .success(email))
        } catch is CancellationError {
            return Result(outcome: .cancelled)
        } catch AntigravityOAuthLoginError.timedOut {
            return Result(outcome: .timedOut)
        } catch let error as AntigravityOAuthLoginError {
            return Result(outcome: .failed(error.localizedDescription))
        } catch {
            return Result(outcome: .failed(error.localizedDescription))
        }
    }

    // Internal pure helpers are intentionally kept on the controller so the
    // PKCE and authorization URL contract can be tested without networking.
    internal static func makeCodeVerifier() throws -> String {
        try makeRandomBase64URL(byteCount: 48)
    }

    internal static func makeState() throws -> String {
        try makeRandomBase64URL(byteCount: 32)
    }

    internal static func codeChallenge(for codeVerifier: String) -> String {
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    internal static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/oauth/callback"
    }

    internal static func makeAuthorizationURL(
        redirectURI: String,
        state: String,
        codeChallenge: String,
        oauthClient: AntigravityOAuthClient) throws -> URL
    {
        guard var components = URLComponents(
            url: AntigravityOAuthConfig.authURL,
            resolvingAgainstBaseURL: false)
        else {
            throw AntigravityOAuthLoginError.invalidAuthorizationURL
        }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: oauthClient.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: authorizationScopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else {
            throw AntigravityOAuthLoginError.invalidAuthorizationURL
        }
        return url
    }

    private static func waitForCallback(
        from server: AntigravityLoopbackServer,
        timeout: TimeInterval) async throws -> OAuthCallback
    {
        try await withThrowingTaskGroup(of: OAuthCallback.self) { group in
            group.addTask {
                try await server.waitForCallback()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                server.cancelCallbackWait(with: AntigravityOAuthLoginError.timedOut)
                throw AntigravityOAuthLoginError.timedOut
            }
            defer { group.cancelAll() }
            guard let callback = try await group.next() else {
                throw AntigravityOAuthLoginError.failed("Google 登入未收到 callback。")
            }
            return callback
        }
    }

    private static func exchangeCodeForTokens(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        oauthClient: AntigravityOAuthClient) async throws -> TokenResponse
    {
        var request = URLRequest(url: AntigravityOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "code": code,
            "client_id": oauthClient.clientID,
            "client_secret": oauthClient.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ])

        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AntigravityOAuthLoginError.failed("Google token response 無效。")
        }
        guard httpResponse.statusCode == 200 else {
            if (400..<500).contains(httpResponse.statusCode) {
                throw AntigravityOAuthLoginError.failed(
                    "Google token exchange 失敗（HTTP \(httpResponse.statusCode)）。")
            }
            throw AntigravityOAuthLoginError.failed("Google token exchange 失敗，請稍後重試。")
        }

        do {
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard !tokenResponse.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AntigravityOAuthLoginError.failed("Google 未回傳 access token。")
            }
            return tokenResponse
        } catch let error as AntigravityOAuthLoginError {
            throw error
        } catch {
            throw AntigravityOAuthLoginError.failed("Google token response 無法解析。")
        }
    }

    private static func fetchUserEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: AntigravityOAuthConfig.userInfoURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw AntigravityOAuthLoginError.failed("Google 帳號資訊取得失敗。")
        }

        guard let userInfo = try? JSONDecoder().decode(UserInfoResponse.self, from: data),
              let email = userInfo.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else {
            throw AntigravityOAuthLoginError.failed("Google 未回傳帳號 email。")
        }
        return email
    }

    private static func formBody(_ values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.map { key, value in
            URLQueryItem(name: key, value: value)
        }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func makeRandomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AntigravityOAuthLoginError.randomGenerationFailed
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

private enum AntigravityOAuthLoginError: LocalizedError {
    case invalidAuthorizationURL
    case randomGenerationFailed
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationURL:
            "無法建立 Google 授權網址。"
        case .randomGenerationFailed:
            "無法建立安全的 OAuth 隨機值。"
        case .timedOut:
            "Google 登入逾時，請重試。"
        case let .failed(message):
            message
        }
    }
}

private struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let idToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
}

private struct UserInfoResponse: Decodable, Sendable {
    let email: String?
}

private struct OAuthCallback: Sendable {
    let code: String?
    let returnedState: String?
    let error: String?
}

private enum ParsedOAuthCallback {
    case valid(OAuthCallback)
    case invalid(status: String)
}

private final class AntigravityLoopbackServer: @unchecked Sendable {
    private let expectedState: String
    private let queue = DispatchQueue(label: "voidnotch.antigravity.oauth")
    private let lock = NSLock()
    private var listener: NWListener?
    private var readyContinuation: CheckedContinuation<String, Error>?
    private var callbackContinuation: CheckedContinuation<OAuthCallback, Error>?
    private var pendingCallbackResult: Result<OAuthCallback, Error>?
    private var callbackCompleted = false

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func start() async throws -> String {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.readyContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue,
                          port != 0
                    else {
                        self.finishReady(with: .failure(AntigravityOAuthLoginError.failed("無法取得本機 OAuth port。")))
                        return
                    }
                    self.finishReady(with: .success(AntigravityOAuthLoginController.redirectURI(port: port)))
                case .failed:
                    self.finishReady(with: .failure(AntigravityOAuthLoginError.failed("無法啟動本機 OAuth callback。")))
                default:
                    break
                }
            }
            listener.start(queue: self.queue)
        }
    }

    func waitForCallback() async throws -> OAuthCallback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.lock.lock()
                defer { self.lock.unlock() }
                if let pending = self.pendingCallbackResult {
                    self.pendingCallbackResult = nil
                    switch pending {
                    case let .success(callback):
                        continuation.resume(returning: callback)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                    return
                }
                self.callbackContinuation = continuation
            }
        } onCancel: {
            self.cancelCallbackWait(with: CancellationError())
        }
    }

    func stop() {
        self.listener?.cancel()
        self.listener = nil
    }

    func cancelCallbackWait(with error: Error) {
        stop()
        finishCallback(with: .failure(error))
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: self.queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data {
                buffer.append(data)
            }
            let headerMarker = Data("\r\n\r\n".utf8)
            if buffer.range(of: headerMarker) == nil, !isComplete {
                if buffer.count >= 64 * 1024 {
                    connection.cancel()
                } else {
                    self.receive(on: connection, accumulated: buffer)
                }
                return
            }

            let callback = self.parseCallback(from: buffer)
            switch callback {
            case let .valid(callback):
                let response = self.httpResponse(for: callback)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                self.finishCallback(with: .success(callback))
            case let .invalid(status):
                let response = self.httpErrorResponse(status: status)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func parseCallback(from data: Data) -> ParsedOAuthCallback {
        guard let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first
        else {
            return .invalid(status: "400 Bad Request")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2,
              let url = URL(string: "http://127.0.0.1\(parts[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return .invalid(status: "400 Bad Request")
        }
        guard parts[0] == "GET" else {
            return .invalid(status: "400 Bad Request")
        }

        let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        let callbackError = components.queryItems?.first(where: { $0.name == "error" })?.value
        guard components.path == "/oauth/callback" else {
            return .invalid(status: "404 Not Found")
        }
        guard returnedState == expectedState else {
            return .invalid(status: "400 Bad Request")
        }
        return .valid(OAuthCallback(code: code, returnedState: returnedState, error: callbackError))
    }

    private func httpResponse(for callback: OAuthCallback) -> Data {
        let success = callback.error == nil && callback.code?.isEmpty == false
        let status = success ? "200 OK" : "400 Bad Request"
        let title = success ? "Google 登入完成" : "Google 登入失敗"
        let detail = success
            ? "請關閉此視窗並返回 VoidNotch。"
            : "請關閉此視窗並返回 VoidNotch。"
        let body = Data(
            "<html><body style=\"font-family:-apple-system;padding:32px;text-align:center\"><h1>\(title)</h1><p>\(detail)</p></body></html>".utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func httpErrorResponse(status: String) -> Data {
        let body = Data(
            "<html><body style=\"font-family:-apple-system;padding:32px;text-align:center\"><h1>OAuth callback unavailable</h1><p>Please close this window and return to VoidNotch.</p></body></html>".utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func finishReady(with result: Result<String, Error>) {
        self.lock.lock()
        let continuation = self.readyContinuation
        self.readyContinuation = nil
        self.lock.unlock()
        guard let continuation else { return }
        switch result {
        case let .success(uri):
            continuation.resume(returning: uri)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func finishCallback(with result: Result<OAuthCallback, Error>) {
        self.lock.lock()
        guard !self.callbackCompleted else {
            self.lock.unlock()
            return
        }
        self.callbackCompleted = true
        let continuation = self.callbackContinuation
        self.callbackContinuation = nil
        if continuation == nil {
            self.pendingCallbackResult = result
        }
        self.lock.unlock()
        guard let continuation else { return }
        switch result {
        case let .success(callback):
            continuation.resume(returning: callback)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
#endif
