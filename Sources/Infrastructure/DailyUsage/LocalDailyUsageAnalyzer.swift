import Foundation
import Domain

/// Analyzes Claude Code session JSONL files to produce daily usage reports.
/// Reads from ~/.claude/projects/*/*.jsonl
public struct LocalDailyUsageAnalyzer: DailyUsageAnalyzing, Sendable {
    private let claudeDir: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        claudeDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude"),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.claudeDir = claudeDir
        self.calendar = calendar
        self.now = now
    }

    public func analyzeToday() async throws -> DailyUsageReport {
        let currentDate = now()
        let todayStart = calendar.startOfDay(for: currentDate)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        // Collect all JSONL files from projects directory
        let projectsDir = claudeDir.appendingPathComponent("projects")
        let jsonlFiles = findJSONLFiles(in: projectsDir)

        // Parse all files and collect records
        let parser = SessionJSONLParser()
        var allRecords: [TokenUsageRecord] = []
        for fileURL in jsonlFiles {
            if let records = try? parser.parse(fileURL: fileURL) {
                allRecords.append(contentsOf: records)
            }
        }

        // Partition into today and yesterday
        let todayRecords = allRecords.filter { record in
            record.timestamp >= todayStart && record.timestamp < todayStart.addingTimeInterval(86400)
        }
        let yesterdayRecords = allRecords.filter { record in
            record.timestamp >= yesterdayStart && record.timestamp < todayStart
        }

        // Aggregate stats
        let todayStat = aggregate(records: todayRecords, date: todayStart)
        let yesterdayStat = aggregate(records: yesterdayRecords, date: yesterdayStart)

        return DailyUsageReport(today: todayStat, previous: yesterdayStat)
    }

    // MARK: - Private

    private func findJSONLFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                files.append(fileURL)
            }
        }
        return files
    }

    private func aggregate(records: [TokenUsageRecord], date: Date) -> DailyUsageStat {
        guard !records.isEmpty else { return .empty(for: date) }

        var totalCost: Decimal = 0
        var totalTokens = 0

        for record in records {
            totalCost += ModelPricing.cost(for: record)
            totalTokens += record.totalTokens
        }

        // Estimate working time from session timestamps (first to last message per session)
        // Group records by approximate sessions (gaps > 30 min = new session)
        let sortedRecords = records.sorted { $0.timestamp < $1.timestamp }
        var workingTime: TimeInterval = 0
        var sessionCount = 1
        var sessionStart = sortedRecords[0].timestamp
        var lastTimestamp = sortedRecords[0].timestamp

        for record in sortedRecords.dropFirst() {
            let gap = record.timestamp.timeIntervalSince(lastTimestamp)
            if gap > 1800 { // 30 minute gap = new session
                workingTime += lastTimestamp.timeIntervalSince(sessionStart)
                sessionStart = record.timestamp
                sessionCount += 1
            }
            lastTimestamp = record.timestamp
        }
        workingTime += lastTimestamp.timeIntervalSince(sessionStart)

        return DailyUsageStat(
            date: date,
            totalCost: totalCost,
            totalTokens: totalTokens,
            workingTime: workingTime,
            sessionCount: sessionCount
        )
    }
}
