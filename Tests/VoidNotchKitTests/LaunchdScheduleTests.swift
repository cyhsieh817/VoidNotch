import XCTest
@testable import VoidNotchKit

/// Launchd 純邏輯層的 plist、launchctl、分類、格式化與掃描測試。
final class LaunchdScheduleTests: XCTestCase {
    private func plist(_ body: String) -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>
        """
        return xml.data(using: .utf8)!
    }

    private func labeledPlist(_ label: String, body: String = "") -> Data {
        plist("<key>Label</key><string>\(label)</string>\(body)")
    }

    private func parsedJob(
        _ data: Data,
        path: String = "/Library/LaunchAgents/com.example.job.plist"
    ) -> LaunchdJob {
        guard let job = LaunchdPlistParser.job(fromPlistData: data, plistPath: path) else {
            XCTFail("expected valid launchd plist")
            fatalError("test fixture unexpectedly failed to parse")
        }
        return job
    }

    func test_startCalendarIntervalSupportsSingleDictionary() {
        let data = labeledPlist(
            "com.example.calendar",
            body: """
            <key>StartCalendarInterval</key>
            <dict>
              <key>Hour</key><integer>9</integer>
              <key>Minute</key><integer>5</integer>
            </dict>
            """
        )

        XCTAssertEqual(
            parsedJob(data).schedule,
            .calendar([LaunchdCalendarSpec(minute: 5, hour: 9)])
        )
    }

    func test_startCalendarIntervalPreservesDictionaryArrayOrder() {
        let data = labeledPlist(
            "com.example.calendar-array",
            body: """
            <key>StartCalendarInterval</key>
            <array>
              <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>8</integer></dict>
              <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>17</integer><key>Minute</key><integer>30</integer></dict>
            </array>
            """
        )

        XCTAssertEqual(
            parsedJob(data).schedule,
            .calendar([
                LaunchdCalendarSpec(hour: 8, weekday: 1),
                LaunchdCalendarSpec(minute: 30, hour: 17, weekday: 5)
            ])
        )
    }

    func test_startIntervalAndProgramSummary() {
        let data = labeledPlist(
            "com.openai.codex.interval",
            body: """
            <key>StartInterval</key><integer>300</integer>
            <key>ProgramArguments</key>
            <array><string>/usr/bin/env</string><string>codex</string><string>--check</string></array>
            """
        )
        let job = parsedJob(data)

        XCTAssertEqual(job.schedule, .interval(seconds: 300))
        XCTAssertEqual(job.programSummary, "/usr/bin/env codex --check")
    }

    func test_programIsUsedWhenProgramArgumentsIsMissingAndEmptyProgramIsAllowed() {
        let withProgram = parsedJob(labeledPlist(
            "com.example.program",
            body: "<key>Program</key><string>/usr/local/bin/example</string>"
        ))
        let withoutProgram = parsedJob(labeledPlist("com.example.empty"))

        XCTAssertEqual(withProgram.programSummary, "/usr/local/bin/example")
        XCTAssertEqual(withoutProgram.programSummary, "")
    }

    func test_keepAliveTrueOrNonEmptyDictionaryWinsWhenNoEarlierScheduleExists() {
        let trueJob = parsedJob(labeledPlist(
            "com.example.keepalive-true",
            body: "<key>KeepAlive</key><true/>"
        ))
        let dictionaryJob = parsedJob(labeledPlist(
            "com.example.keepalive-dictionary",
            body: "<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>"
        ))

        XCTAssertEqual(trueJob.schedule, .keepAlive)
        XCTAssertEqual(dictionaryJob.schedule, .keepAlive)
    }

    func test_runAtLoadOnlyAndOnDemand() {
        let runAtLoad = parsedJob(labeledPlist(
            "com.example.login",
            body: "<key>RunAtLoad</key><true/>"
        ))
        let onDemand = parsedJob(labeledPlist("com.example.on-demand"))

        XCTAssertEqual(runAtLoad.schedule, .runAtLoadOnly)
        XCTAssertEqual(onDemand.schedule, .onDemand)
    }

    func test_watchPathsAndQueueDirectoriesMapToWatchPaths() {
        let watchPaths = parsedJob(labeledPlist(
            "com.example.watch",
            body: """
            <key>WatchPaths</key>
            <array><string>/tmp/inbox</string><string>/tmp/queue</string></array>
            """
        ))
        let queueDirectories = parsedJob(labeledPlist(
            "com.example.queue",
            body: "<key>QueueDirectories</key><array><string>/tmp/jobs</string></array>"
        ))

        XCTAssertEqual(watchPaths.schedule, .watchPaths(["/tmp/inbox", "/tmp/queue"]))
        XCTAssertEqual(queueDirectories.schedule, .watchPaths(["/tmp/jobs"]))
    }

    func test_missingLabelAndMalformedPlistReturnNil() {
        XCTAssertNil(LaunchdPlistParser.job(
            fromPlistData: plist("<key>Program</key><string>missing-label</string>"),
            plistPath: "/Library/LaunchAgents/missing.plist"
        ))
        XCTAssertNil(LaunchdPlistParser.job(
            fromPlistData: Data([0x00, 0xFF, 0x01]),
            plistPath: "/Library/LaunchAgents/bad.plist"
        ))
    }

    func test_launchctlListParserHandlesHeaderRunningPidStoppedPidAndExitStatus() {
        let output = """
        PID\tStatus\tLabel
        123\t0\tcom.example.running
        -\t7\tcom.example.stopped
        456\t-9\tcom.example.failed
        """

        let states = LaunchctlListParser.parse(output)

        XCTAssertEqual(states["com.example.running"], LaunchdRuntimeState(pid: 123, lastExitStatus: 0))
        XCTAssertEqual(states["com.example.stopped"], LaunchdRuntimeState(pid: nil, lastExitStatus: 7))
        XCTAssertEqual(states["com.example.failed"], LaunchdRuntimeState(pid: 456, lastExitStatus: -9))
    }

    func test_launchctlListParserIgnoresEmptyOutputAndMalformedRows() {
        XCTAssertTrue(LaunchctlListParser.parse("").isEmpty)
        XCTAssertTrue(LaunchctlListParser.parse("PID\tStatus\tLabel\n").isEmpty)
        XCTAssertTrue(LaunchctlListParser.parse("not-a-pid\t0\tcom.example.bad\n").isEmpty)
    }

    func test_harnessClassifierFollowsDeclaredPriorityAndCaseInsensitiveRules() {
        let cases: [(String, AgentHarnessKind)] = [
            ("com.anthropic.claude.helper", .claude),
            ("com.openai.codex.runner", .codex),
            ("com.google.gemini.worker", .gemini),
            ("com.example.AGY.scheduler", .gemini),
            ("com.antigravity.worker", .gemini),
            ("com.xai.grok.gateway", .grok),
            ("ai.hermes.gateway", .hermes),
            ("com.voidweaver.agent", .voidweaver),
            ("com.voidnotch.agent", .voidweaver),
            ("com.lgd.runner", .voidweaver),
            ("com.labgrimoire.runner", .voidweaver),
            ("com.osaurus.worker", .omlx),
            ("com.mlx.worker", .omlx),
            ("com.google.keystone", .other),
            ("com.example.unrelated", .other)
        ]

        for (label, expected) in cases {
            XCTAssertEqual(LaunchdHarnessClassifier.classify(label: label), expected, label)
        }
        XCTAssertEqual(AgentHarnessKind.omlx.displayName, "oMLX")
    }

    /// Token 化比對：子字串不得誤判；完整 token 仍正常命中。
    func test_harnessClassifierUsesTokenMatchNotSubstring() {
        // 誤判防護：label 內含 mlx/lgd 子字串但非獨立 token
        XCTAssertEqual(
            LaunchdHarnessClassifier.classify(label: "com.example.htmlxform"),
            .other,
            "htmlxform 不應因含 mlx 子字串而判為 omlx"
        )
        XCTAssertEqual(
            LaunchdHarnessClassifier.classify(label: "com.example.pilgdrive"),
            .other,
            "pilgdrive 不應因含 lgd 子字串而判為 voidweaver"
        )

        // 正常命中：關鍵字為完整 token
        XCTAssertEqual(
            LaunchdHarnessClassifier.classify(label: "com.voidweaver.x"),
            .voidweaver
        )
        XCTAssertEqual(
            LaunchdHarnessClassifier.classify(label: "homebrew.mxcl.omlx"),
            .omlx
        )
        XCTAssertEqual(
            LaunchdHarnessClassifier.classify(label: "ai.hermes.gateway"),
            .hermes
        )
    }

    func test_scheduleFormatterSupportsBothLanguagesPaddingWeekdaysAndMultipleCalendarEntries() {
        XCTAssertEqual(
            LaunchdScheduleFormatter.text(for: .interval(seconds: 300), zhHant: true),
            "每 300 秒"
        )
        XCTAssertEqual(
            LaunchdScheduleFormatter.text(for: .interval(seconds: 300), zhHant: false),
            "Every 300s"
        )

        let daily = LaunchdScheduleKind.calendar([LaunchdCalendarSpec(minute: 5, hour: 9)])
        XCTAssertEqual(LaunchdScheduleFormatter.text(for: daily, zhHant: true), "每日 09:05")
        XCTAssertEqual(LaunchdScheduleFormatter.text(for: daily, zhHant: false), "Daily 09:05")

        let sundayZero = LaunchdScheduleKind.calendar([
            LaunchdCalendarSpec(minute: 5, hour: 9, weekday: 0)
        ])
        let sundaySeven = LaunchdScheduleKind.calendar([
            LaunchdCalendarSpec(minute: 5, hour: 9, weekday: 7)
        ])
        XCTAssertEqual(LaunchdScheduleFormatter.text(for: sundayZero, zhHant: true), "週日 09:05")
        XCTAssertEqual(LaunchdScheduleFormatter.text(for: sundaySeven, zhHant: false), "Sun 09:05")

        let multiple = LaunchdScheduleKind.calendar([
            LaunchdCalendarSpec(minute: 5, hour: 9),
            LaunchdCalendarSpec(hour: 8, weekday: 1)
        ])
        XCTAssertEqual(
            LaunchdScheduleFormatter.text(for: multiple, zhHant: true),
            "每日 09:05、週一 08:00"
        )
        XCTAssertEqual(
            LaunchdScheduleFormatter.text(for: multiple, zhHant: false),
            "Daily 09:05, Mon 08:00"
        )

        let hourly = LaunchdScheduleKind.calendar([LaunchdCalendarSpec(minute: 5)])
        XCTAssertEqual(LaunchdScheduleFormatter.text(for: hourly, zhHant: true), "每小時 :05")
        XCTAssertEqual(LaunchdScheduleFormatter.text(for: hourly, zhHant: false), "Hourly :05")

        XCTAssertEqual(
            LaunchdScheduleFormatter.text(for: .watchPaths([]), zhHant: true),
            "監看路徑"
        )
        XCTAssertEqual(
            LaunchdScheduleFormatter.text(for: .keepAlive, zhHant: false),
            "Always on (KeepAlive)"
        )
        XCTAssertEqual(
            LaunchdScheduleFormatter.text(for: .runAtLoadOnly, zhHant: true),
            "登入時執行"
        )
        XCTAssertEqual(
            LaunchdScheduleFormatter.text(for: .onDemand, zhHant: false),
            "On demand"
        )
    }

    func test_scannerSkipsMalformedPlistsAndSortsByHarnessThenLabel() {
        let firstDirectory = URL(fileURLWithPath: "/launchd/first", isDirectory: true)
        let secondDirectory = URL(fileURLWithPath: "/launchd/second", isDirectory: true)
        let firstCodex = firstDirectory.appendingPathComponent("com.openai.codex.plist")
        let secondCodex = secondDirectory.appendingPathComponent("com.openai.codex.plist")
        let reader = FixtureReader(entriesByDirectory: [
            firstDirectory.path: [
                FixtureEntry(url: firstCodex, data: labeledPlist(
                    "com.openai.codex",
                    body: "<key>Program</key><string>first</string>"
                )),
                FixtureEntry(
                    url: firstDirectory.appendingPathComponent("broken.plist"),
                    data: Data([0xFF, 0x00])
                )
            ],
            secondDirectory.path: [
                FixtureEntry(url: secondCodex, data: labeledPlist(
                    "com.openai.codex",
                    body: "<key>Program</key><string>second</string>"
                )),
                FixtureEntry(url: secondDirectory.appendingPathComponent("gemini.plist"), data: labeledPlist("com.gemini.job")),
                FixtureEntry(url: secondDirectory.appendingPathComponent("voidnotch.plist"), data: labeledPlist("com.voidnotch.job")),
                FixtureEntry(url: secondDirectory.appendingPathComponent("other.plist"), data: labeledPlist("com.unrelated.job"))
            ]
        ])

        let jobs = LaunchdScheduleScanner(fs: reader).scan(
            directories: [firstDirectory, secondDirectory],
            runtime: [:]
        )

        XCTAssertEqual(jobs.map(\.harness), [.codex, .gemini, .voidweaver, .other])
        XCTAssertEqual(jobs.first?.programSummary, "first")
        XCTAssertEqual(jobs.filter { $0.label == "com.openai.codex" }.count, 1)
        XCTAssertFalse(jobs.contains { $0.plistPath == secondCodex.path })
    }

    func test_scannerDeduplicatesDifferentNamedActivePlistsWithSameLabelInOneDirectory() {
        let directory = URL(fileURLWithPath: "/launchd/duplicates/same-directory", isDirectory: true)
        let firstURL = directory.appendingPathComponent("first.plist")
        let secondURL = directory.appendingPathComponent("second.plist")
        let reader = FixtureReader(entriesByDirectory: [
            directory.path: [
                FixtureEntry(url: firstURL, data: labeledPlist("com.example.same-label")),
                FixtureEntry(url: secondURL, data: labeledPlist("com.example.same-label"))
            ]
        ])

        let jobs = LaunchdScheduleScanner(fs: reader).scan(
            directories: [directory],
            runtime: [:]
        )

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.id, firstURL.path)
    }

    func test_scannerMergesRuntimeAndAssignsAllThreePhases() {
        let directory = URL(fileURLWithPath: "/launchd/phases", isDirectory: true)
        let runURL = directory.appendingPathComponent("run.plist")
        let absentURL = directory.appendingPathComponent("absent.plist")
        let disabledURL = directory.appendingPathComponent("disabled.plist")
        let archivedURL = directory.appendingPathComponent("_DELETE_com.example.archived.plist")
        let reader = FixtureReader(entriesByDirectory: [
            directory.path: [
                FixtureEntry(url: runURL, data: labeledPlist("com.example.run")),
                FixtureEntry(url: absentURL, data: labeledPlist("com.example.absent")),
                FixtureEntry(url: disabledURL, data: labeledPlist(
                    "com.example.disabled",
                    body: "<key>Disabled</key><true/>"
                )),
                FixtureEntry(url: archivedURL, data: labeledPlist("com.example.archived"))
            ]
        ])
        let runtime = [
            "com.example.run": LaunchdRuntimeState(pid: 42, lastExitStatus: 0),
            "com.example.disabled": LaunchdRuntimeState(pid: 43, lastExitStatus: 9),
            "com.example.archived": LaunchdRuntimeState(pid: 44, lastExitStatus: 1)
        ]

        let jobs = LaunchdScheduleScanner(fs: reader).scan(
            directories: [directory],
            runtime: runtime
        )

        let run = jobs.first { $0.label == "com.example.run" }
        let absent = jobs.first { $0.label == "com.example.absent" }
        let disabled = jobs.first { $0.label == "com.example.disabled" }
        let archived = jobs.first { $0.label == "com.example.archived" }
        XCTAssertEqual(run?.isLoaded, true)
        XCTAssertEqual(run?.pid, 42)
        XCTAssertEqual(run?.lastExitStatus, 0)
        XCTAssertEqual(run?.phase, .run)
        XCTAssertEqual(absent?.isLoaded, false)
        XCTAssertNil(absent?.pid)
        XCTAssertEqual(absent?.phase, .paused)
        XCTAssertEqual(disabled?.isDisabled, true)
        XCTAssertEqual(disabled?.isLoaded, true)
        XCTAssertEqual(disabled?.lastExitStatus, 9)
        XCTAssertEqual(disabled?.phase, .paused)
        XCTAssertEqual(archived?.isLoaded, true)
        XCTAssertEqual(archived?.phase, .archived)
    }

    func test_scannerKeepsArchivedAndDifferentNamedActiveJobsButDeduplicatesSameNamedActiveJob() {
        let firstDirectory = URL(fileURLWithPath: "/launchd/duplicates/first", isDirectory: true)
        let secondDirectory = URL(fileURLWithPath: "/launchd/duplicates/second", isDirectory: true)
        let firstActive = firstDirectory.appendingPathComponent("com.example.job.plist")
        let secondActiveSameName = secondDirectory.appendingPathComponent("com.example.job.plist")
        let differentNamedActive = secondDirectory.appendingPathComponent("backup-com.example.job.plist")
        let archived = secondDirectory.appendingPathComponent("_DELETE_com.example.job.plist")
        let reader = FixtureReader(entriesByDirectory: [
            firstDirectory.path: [
                FixtureEntry(url: firstActive, data: labeledPlist("com.example.job"))
            ],
            secondDirectory.path: [
                FixtureEntry(url: secondActiveSameName, data: labeledPlist("com.example.job")),
                FixtureEntry(url: differentNamedActive, data: labeledPlist("com.example.job")),
                FixtureEntry(url: archived, data: labeledPlist("com.example.job"))
            ]
        ])

        let jobs = LaunchdScheduleScanner(fs: reader).scan(
            directories: [firstDirectory, secondDirectory],
            runtime: ["com.example.job": LaunchdRuntimeState(pid: 99, lastExitStatus: 0)]
        )

        XCTAssertEqual(jobs.count, 2)
        XCTAssertTrue(jobs.contains { $0.id == firstActive.path })
        XCTAssertFalse(jobs.contains { $0.id == secondActiveSameName.path })
        XCTAssertFalse(jobs.contains { $0.id == differentNamedActive.path })
        XCTAssertTrue(jobs.contains { $0.id == archived.path && $0.phase == .archived })
        XCTAssertEqual(Set(jobs.map(\.id)).count, 2)
    }

    func test_isLoadableByLaunchdUsesPlistExtensionRegardlessOfPrefixAndCase() {
        let cases: [(String, Bool)] = [
            ("a.plist", true),
            ("_DELETE_20260101_000000_a.plist", true),
            ("_DELETE_20260101_000000_a.plist.retired", false),
            ("a.PLIST", true)
        ]

        for (fileName, expected) in cases {
            XCTAssertEqual(
                LaunchdJobRetirement.isLoadableByLaunchd(fileName: fileName),
                expected,
                fileName)
        }
    }

    func test_scannerMarksLoadableArchivedPlistAsZombieButRetiredFileAsSafe() {
        let directory = URL(fileURLWithPath: "/launchd/zombies", isDirectory: true)
        let zombieURL = directory.appendingPathComponent(
            "_DELETE_20260101_000000_zombie.plist")
        let retiredURL = directory.appendingPathComponent(
            "_DELETE_20260101_000000_retired.plist.retired")
        let reader = FixtureReader(entriesByDirectory: [
            directory.path: [
                FixtureEntry(url: zombieURL, data: labeledPlist("com.example.zombie")),
                FixtureEntry(url: retiredURL, data: labeledPlist("com.example.retired"))
            ]
        ])

        let jobs = LaunchdScheduleScanner(fs: reader).scan(
            directories: [directory],
            runtime: [:])

        let zombie = jobs.first { $0.label == "com.example.zombie" }
        let retired = jobs.first { $0.label == "com.example.retired" }
        XCTAssertEqual(zombie?.phase, .archived)
        XCTAssertEqual(retired?.phase, .archived)
        XCTAssertEqual(zombie?.isZombie, true)
        XCTAssertEqual(retired?.isZombie, false)
    }

    func test_scannerMarksActiveJobAsNotZombie() {
        let directory = URL(fileURLWithPath: "/launchd/active", isDirectory: true)
        let activeURL = directory.appendingPathComponent("active.plist")
        let reader = FixtureReader(entriesByDirectory: [
            directory.path: [
                FixtureEntry(url: activeURL, data: labeledPlist("com.example.active"))
            ]
        ])

        let jobs = LaunchdScheduleScanner(fs: reader).scan(
            directories: [directory],
            runtime: ["com.example.active": LaunchdRuntimeState(pid: 10, lastExitStatus: 0)])

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.phase, .run)
        XCTAssertEqual(jobs.first?.isZombie, false)
    }

    func test_scannerTreatsRetiredSuffixAsArchivedRegardlessOfCase() {
        let directory = URL(fileURLWithPath: "/launchd/retired-case", isDirectory: true)
        let retiredURL = directory.appendingPathComponent(
            "_DELETE_20260101_000000_a.plist.RETIRED")
        let reader = FixtureReader(entriesByDirectory: [
            directory.path: [
                FixtureEntry(url: retiredURL, data: labeledPlist("com.example.retired-case"))
            ]
        ])

        let jobs = LaunchdScheduleScanner(fs: reader).scan(
            directories: [directory],
            runtime: [:])

        XCTAssertEqual(jobs.first?.phase, .archived)
        XCTAssertEqual(jobs.first?.isZombie, false)
    }

    func test_archivedFileNameUsesDeletePrefixTimestampAndRetiredSuffix() {
        let fileName = LaunchdJobRetirement.archivedFileName(
            for: "com.example.schedule.plist",
            at: Date(timeIntervalSince1970: 0))

        XCTAssertNotNil(
            fileName.range(
                of: #"^_DELETE_[0-9]{8}_[0-9]{6}_com\.example\.schedule\.plist\.retired$"#,
                options: .regularExpression))
    }

    func test_archivedFileNameCollisionSuffixProvidesReentrantCandidate() {
        let date = Date(timeIntervalSince1970: 0)
        let first = LaunchdJobRetirement.archivedFileName(
            for: "com.example.schedule.plist",
            at: date,
            collisionIndex: 0)
        let second = LaunchdJobRetirement.availableArchivedFileName(
            for: "com.example.schedule.plist",
            at: date,
            occupiedFileNames: [first])

        guard let second else {
            XCTFail("expected a collision-suffixed archived filename")
            return
        }
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.hasSuffix("com.example.schedule.plist.1.retired"))
    }

    func test_isRemovableAllowsOnlyUserLaunchAgentsAndNonArchivedPhases() {
        let homeLaunchAgents = URL(
            fileURLWithPath: "/Users/example/Library/LaunchAgents",
            isDirectory: true)
        let userPlistPath = homeLaunchAgents
            .appendingPathComponent("com.example.user.plist")
            .path

        XCTAssertTrue(
            LaunchdJobRetirement.isRemovable(
                plistPath: userPlistPath,
                phase: .run,
                homeLaunchAgents: homeLaunchAgents))
        XCTAssertFalse(
            LaunchdJobRetirement.isRemovable(
                plistPath: "/Library/LaunchAgents/com.example.system.plist",
                phase: .run,
                homeLaunchAgents: homeLaunchAgents))
        XCTAssertFalse(
            LaunchdJobRetirement.isRemovable(
                plistPath: userPlistPath,
                phase: .archived,
                homeLaunchAgents: homeLaunchAgents))
        XCTAssertTrue(
            LaunchdJobRetirement.isRemovable(
                plistPath: userPlistPath,
                phase: .paused,
                homeLaunchAgents: homeLaunchAgents))
    }

    func test_isRemovableAllowsOnlyZombieArchivedJobsAndKeepsLocationRestriction() {
        let homeLaunchAgents = URL(
            fileURLWithPath: "/Users/example/Library/LaunchAgents",
            isDirectory: true)
        let userPlistPath = homeLaunchAgents
            .appendingPathComponent("_DELETE_20260101_000000_user.plist")
            .path

        XCTAssertTrue(
            LaunchdJobRetirement.isRemovable(
                plistPath: userPlistPath,
                phase: .archived,
                homeLaunchAgents: homeLaunchAgents,
                isZombie: true))
        XCTAssertFalse(
            LaunchdJobRetirement.isRemovable(
                plistPath: userPlistPath,
                phase: .archived,
                homeLaunchAgents: homeLaunchAgents,
                isZombie: false))
        XCTAssertTrue(
            LaunchdJobRetirement.isRemovable(
                plistPath: userPlistPath,
                phase: .run,
                homeLaunchAgents: homeLaunchAgents,
                isZombie: false))
        XCTAssertFalse(
            LaunchdJobRetirement.isRemovable(
                plistPath: "/Library/LaunchAgents/_DELETE_20260101_000000_system.plist",
                phase: .archived,
                homeLaunchAgents: homeLaunchAgents,
                isZombie: true))
    }
}

private struct FixtureEntry: Sendable {
    let url: URL
    let data: Data
}

private struct FixtureReader: LaunchdDirectoryReading {
    let entriesByDirectory: [String: [FixtureEntry]]

    func plistURLs(in directory: URL) -> [URL] {
        entriesByDirectory[directory.path, default: []].map(\.url)
    }

    func readData(_ url: URL) -> Data? {
        for entries in entriesByDirectory.values {
            if let entry = entries.first(where: { $0.url.path == url.path }) {
                return entry.data
            }
        }
        return nil
    }
}
