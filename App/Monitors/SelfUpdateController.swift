//
//  SelfUpdateController.swift — App 端更新流程編排
//

import AppKit
import Foundation
import Observation
import VoidNotchKit

enum SelfUpdateState: Equatable {
    case idle
    case downloading
    case extracting
    case verifying
    case installing
    case failed(SelfUpdateError)

    var isBusy: Bool {
        switch self {
        case .idle, .failed:
            return false
        case .downloading, .extracting, .verifying, .installing:
            return true
        }
    }
}

@Observable
@MainActor
final class SelfUpdateController {
    private static let maximumZipSize: Int64 = 300 * 1024 * 1024
    private static let updatesDirectoryName = "VoidNotch/updates"

    private(set) var state: SelfUpdateState = .idle

    private let session: URLSession
    private let fileManager: FileManager
    private let updater: SelfUpdater
    private let bundle: Bundle

    init(
        session: URLSession = .shared,
        runner: UpdateProcessRunning = ProcessUpdateRunner(),
        fileManager: FileManager = .default,
        bundle: Bundle = .main)
    {
        self.session = session
        self.fileManager = fileManager
        self.updater = SelfUpdater(runner: runner, fileManager: fileManager)
        self.bundle = bundle
        cleanupPreviousStaging()
    }

    func install(_ update: AppUpdateInfo) {
        guard !state.isBusy else { return }
        state = .downloading

        Task { [weak self] in
            guard let self else { return }
            await self.downloadAndInstall(update)
        }
    }

    private func downloadAndInstall(_ update: AppUpdateInfo) async {
        do {
            let currentApp = bundle.bundleURL
            if let preflightError = updater.preflight(bundleURL: currentApp) {
                throw preflightError
            }

            guard let downloadURL = URL(string: update.url), isAllowedDownloadURL(downloadURL) else {
                throw SelfUpdateError.download("download host")
            }

            let staging = try makeStagingDirectory()
            let downloaded: URL
            let response: URLResponse
            do {
                (downloaded, response) = try await session.download(from: downloadURL)
            } catch {
                throw SelfUpdateError.download(error.localizedDescription)
            }

            guard let finalURL = response.url, isAllowedDownloadURL(finalURL) else {
                throw SelfUpdateError.download("redirected download host")
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode)
            {
                throw SelfUpdateError.download("HTTP \(httpResponse.statusCode)")
            }

            if response.expectedContentLength > SelfUpdateController.maximumZipSize {
                throw SelfUpdateError.download("archive too large")
            }

            let zipURL = staging.appendingPathComponent("update.zip")
            do {
                try fileManager.moveItem(at: downloaded, to: zipURL)
                let size = try fileManager.attributesOfItem(atPath: zipURL.path)[.size] as? NSNumber
                guard let size, size.int64Value <= SelfUpdateController.maximumZipSize else {
                    throw SelfUpdateError.download("archive too large")
                }
            } catch let error as SelfUpdateError {
                throw error
            } catch {
                throw SelfUpdateError.staging("download archive")
            }

            guard let rawExpectedHash = update.sha256 else {
                throw SelfUpdateError.download("sha256 missing or malformed")
            }
            let expectedHash = rawExpectedHash
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard expectedHash.utf8.count == 64,
                  expectedHash.utf8.allSatisfy({ byte in
                      (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
                  })
            else {
                throw SelfUpdateError.download("sha256 missing or malformed")
            }
            let actualHash: String
            do {
                actualHash = try updater.sha256Hex(of: zipURL)
            } catch {
                throw SelfUpdateError.download("hash read")
            }
            guard actualHash == expectedHash else {
                throw SelfUpdateError.hashMismatch(expected: expectedHash, actual: actualHash)
            }

            state = .extracting
            let extracted = staging.appendingPathComponent("extracted", isDirectory: true)
            do {
                try fileManager.createDirectory(
                    at: extracted,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                try updater.extractZip(zipURL, to: extracted)
            } catch let error as SelfUpdateError {
                throw error
            } catch {
                throw SelfUpdateError.extract(error.localizedDescription)
            }

            guard let candidate = findCandidateApp(in: extracted) else {
                throw SelfUpdateError.staging("candidate app missing")
            }

            state = .verifying
            try updater.verifyCandidate(candidate, againstRunning: currentApp)
            guard let candidateVersion = Bundle(url: candidate)?.infoDictionary?["CFBundleShortVersionString"] as? String,
                  let currentVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            else {
                throw SelfUpdateError.verify(step: "version")
            }
            let normalizedCandidateVersion = normalizeVersion(candidateVersion)
            let normalizedUpdateVersion = normalizeVersion(update.version)
            let normalizedCurrentVersion = normalizeVersion(currentVersion)
            guard normalizedCandidateVersion == normalizedUpdateVersion,
                  SemverCompare.isNewer(
                      remote: normalizedCandidateVersion,
                      than: normalizedCurrentVersion)
            else {
                throw SelfUpdateError.verify(step: "version")
            }
            try updater.removeQuarantine(candidate)

            state = .installing
            let helper = try stageHelper(in: staging)
            let backupDirectory = staging.appendingPathComponent("backup", isDirectory: true)
            try fileManager.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let logFile = staging.appendingPathComponent("update.log")
            guard fileManager.createFile(atPath: logFile.path, contents: nil) else {
                throw SelfUpdateError.staging("update log")
            }

            terminateOtherInstances()
            try spawnHelper(
                helper,
                parentPID: ProcessInfo.processInfo.processIdentifier,
                currentApp: currentApp,
                candidate: candidate,
                backupDirectory: backupDirectory,
                logFile: logFile)
            NSApp.terminate(nil)
        } catch let error as SelfUpdateError {
            state = .failed(error)
        } catch {
            state = .failed(.helper(error.localizedDescription))
        }
    }

    private func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else { return false }
        let suffix = VoidNotchLinks.downloadHostSuffix
        return host == suffix || host.hasSuffix("." + suffix)
    }

    private func normalizeVersion(_ raw: String) -> String {
        var version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.hasPrefix("v") {
            version.removeFirst()
        }
        return version
    }

    private func makeStagingDirectory() throws -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let updates = applicationSupport.appendingPathComponent(SelfUpdateController.updatesDirectoryName, isDirectory: true)
        let staging = updates.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: staging,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
            return staging
        } catch {
            throw SelfUpdateError.staging("create staging directory")
        }
    }

    private func findCandidateApp(in extracted: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: extracted,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return nil }

        for case let url as URL in enumerator where url.lastPathComponent == "VoidNotch.app" {
            return url
        }
        return nil
    }

    private func stageHelper(in staging: URL) throws -> URL {
        guard let bundledHelper = bundle.url(
            forResource: "voidnotch-update-helper",
            withExtension: "sh",
            subdirectory: "update")
        else {
            throw SelfUpdateError.helper("bundle helper missing")
        }

        let stagedHelper = staging.appendingPathComponent("voidnotch-update-helper.sh")
        do {
            try fileManager.copyItem(at: bundledHelper, to: stagedHelper)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stagedHelper.path)
            return stagedHelper
        } catch {
            throw SelfUpdateError.staging("copy helper")
        }
    }

    private func spawnHelper(
        _ helper: URL,
        parentPID: pid_t,
        currentApp: URL,
        candidate: URL,
        backupDirectory: URL,
        logFile: URL) throws
    {
        let process = Process()
        process.executableURL = helper
        process.arguments = [
            String(parentPID),
            currentApp.path,
            candidate.path,
            backupDirectory.path,
            logFile.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw SelfUpdateError.helper(error.localizedDescription)
        }
    }

    private func terminateOtherInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleIdentifier = bundle.bundleIdentifier
        for application in NSWorkspace.shared.runningApplications where
            application.processIdentifier != currentPID &&
            application.bundleIdentifier == bundleIdentifier
        {
            application.terminate()
        }
    }

    private func cleanupPreviousStaging() {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let updates = applicationSupport.appendingPathComponent(SelfUpdateController.updatesDirectoryName, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: updates,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return }

        let stagingDirectories = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        var backups: [(staging: URL, modifiedAt: Date)] = []
        for staging in stagingDirectories {
            let backupDirectory = staging.appendingPathComponent("backup", isDirectory: true)
            guard let backupEntries = try? fileManager.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]),
                !backupEntries.isEmpty
            else { continue }

            let newest = backupEntries.compactMap { entry -> Date? in
                try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }.max() ?? .distantPast
            backups.append((staging, newest))
        }

        let retainedStaging = backups.max { $0.modifiedAt < $1.modifiedAt }?.staging
        for staging in stagingDirectories where staging != retainedStaging {
            moveToDeletePrefixAndRemove(staging)
        }
    }

    private func moveToDeletePrefixAndRemove(_ staging: URL) {
        let parent = staging.deletingLastPathComponent()
        var deleted = parent.appendingPathComponent("_DELETE_\(staging.lastPathComponent)")
        if fileManager.fileExists(atPath: deleted.path) {
            deleted = parent.appendingPathComponent("_DELETE_\(UUID().uuidString)-\(staging.lastPathComponent)")
        }
        do {
            try fileManager.moveItem(at: staging, to: deleted)
            try fileManager.removeItem(at: deleted)
        } catch {
            // 更新暫存只影響清理，不應阻擋 App 啟動或下次更新。
        }
    }
}
