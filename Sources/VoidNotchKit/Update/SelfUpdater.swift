//
//  SelfUpdater.swift — 更新候選 bundle 的驗證與解壓邏輯
//

import CryptoKit
import Foundation

public protocol UpdateProcessRunning: Sendable {
    func run(_ launchPath: String, _ args: [String]) throws -> (Int32, String)
}

/// 供實際 App 使用的 Process 包裝；測試以 stub runner 取代，不碰系統簽章工具。
public struct ProcessUpdateRunner: UpdateProcessRunning, Sendable {
    public init() {}

    public func run(_ launchPath: String, _ args: [String]) throws -> (Int32, String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

public enum SelfUpdateError: Error, Equatable, Sendable, LocalizedError {
    case preflight(String)
    case download(String)
    case hashMismatch(expected: String, actual: String)
    case extract(String)
    case verify(step: String)
    case staging(String)
    case helper(String)

    public var errorDescription: String? {
        switch self {
        case let .preflight(reason):
            return "更新前置檢查失敗：\(reason)"
        case let .download(reason):
            return "更新下載失敗：\(reason)"
        case let .hashMismatch(expected, actual):
            return "更新檔案雜湊不符（預期 \(expected)，實際 \(actual)）"
        case let .extract(reason):
            return "更新壓縮檔解開失敗：\(reason)"
        case let .verify(step):
            return "更新候選版本驗證失敗：\(step)"
        case let .staging(reason):
            return "更新暫存失敗：\(reason)"
        case let .helper(reason):
            return "更新 helper 失敗：\(reason)"
        }
    }
}

public struct SelfUpdater {
    private static let codesignPath = "/usr/bin/codesign"
    private static let staplerPath = "/usr/bin/xcrun"
    private static let spctlPath = "/usr/bin/spctl"
    private static let xattrPath = "/usr/bin/xattr"

    private let runner: UpdateProcessRunning
    private let fileManager: FileManager

    public init(runner: UpdateProcessRunning, fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func preflight(bundleURL: URL) -> SelfUpdateError? {
        if bundleURL.path.contains("/AppTranslocation/") {
            return .preflight("translocation")
        }

        let parent = bundleURL.deletingLastPathComponent()
        let attributes = try? fileManager.attributesOfItem(atPath: parent.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard fileManager.fileExists(atPath: parent.path),
              permissions & 0o222 != 0,
              fileManager.isWritableFile(atPath: parent.path)
        else {
            return .preflight("parent-not-writable")
        }
        return nil
    }

    public func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var digest = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func extractZip(_ zip: URL, to dir: URL) throws {
        do {
            let result = try runner.run("/usr/bin/ditto", ["-xk", zip.path, dir.path])
            guard result.0 == 0 else {
                throw SelfUpdateError.extract(result.1.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch let error as SelfUpdateError {
            throw error
        } catch {
            throw SelfUpdateError.extract(error.localizedDescription)
        }
    }

    public func verifyCandidate(_ appURL: URL, againstRunning current: URL) throws {
        try requireSuccess(
            SelfUpdater.codesignPath,
            ["--verify", "--deep", "--strict", appURL.path],
            step: "codesign")

        let requirementOutput: String
        do {
            let result = try runner.run(SelfUpdater.codesignPath, ["-d", "-r-", current.path])
            guard result.0 == 0 else {
                throw SelfUpdateError.verify(step: "designated-requirement")
            }
            requirementOutput = result.1
        } catch let error as SelfUpdateError {
            throw error
        } catch {
            throw SelfUpdateError.verify(step: "designated-requirement")
        }

        // codesign -R= 只接受裸 requirement 運算式：實測「designated => 」前綴（含 ad-hoc
        // 輸出的「# designated => 」註解形）一併傳入必然 parse error，故取前綴之後的內容。
        guard let requirementRange = requirementOutput.range(of: "designated => ") else {
            throw SelfUpdateError.verify(step: "designated-requirement")
        }
        let requirement = requirementOutput[requirementRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requirement.isEmpty else {
            throw SelfUpdateError.verify(step: "designated-requirement")
        }

        try requireSuccess(
            SelfUpdater.codesignPath,
            ["--verify", "-R=\(requirement)", appURL.path],
            step: "designated-requirement")

        try requireSuccess(
            SelfUpdater.staplerPath,
            ["stapler", "validate", appURL.path],
            step: "stapler")

        do {
            let result = try runner.run(SelfUpdater.spctlPath, ["-a", "--type", "exec", appURL.path])
            guard result.0 == 0, result.1.localizedCaseInsensitiveContains("accepted") else {
                throw SelfUpdateError.verify(step: "spctl")
            }
        } catch let error as SelfUpdateError {
            throw error
        } catch {
            throw SelfUpdateError.verify(step: "spctl")
        }
    }

    public func removeQuarantine(_ appURL: URL) throws {
        do {
            let result = try runner.run(SelfUpdater.xattrPath, ["-dr", "com.apple.quarantine", appURL.path])
            guard result.0 == 0 else {
                throw SelfUpdateError.helper("quarantine")
            }
        } catch let error as SelfUpdateError {
            throw error
        } catch {
            throw SelfUpdateError.helper("quarantine")
        }
    }

    private func requireSuccess(_ launchPath: String, _ args: [String], step: String) throws {
        do {
            let result = try runner.run(launchPath, args)
            guard result.0 == 0 else {
                throw SelfUpdateError.verify(step: step)
            }
        } catch let error as SelfUpdateError {
            throw error
        } catch {
            throw SelfUpdateError.verify(step: step)
        }
    }
}
