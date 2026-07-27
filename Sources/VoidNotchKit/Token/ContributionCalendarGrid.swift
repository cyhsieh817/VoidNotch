// Adapted from tokens (https://github.com/junhoyeo/tokens), MIT License,
// Copyright (c) 2025 Junho Yeo.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

public enum ContributionCalendarGrid {
    /// Computes an adaptive display window (in days subtracted from `endDate` to form cutoff).
    ///
    /// - Returns a value clamped to `[minimum, maximum]`, then rounded **up** so
    ///   `result % 7 == 6` (cutoff→endDate spans whole weeks plus the current week).
    ///   When rounding would exceed `maximum`, `maximum` is kept.
    /// - If `earliestDate` is `nil` or either date fails `"yyyy-MM-dd"` UTC parse, returns `minimum`.
    public static func adaptiveWindowDays(
        earliestDate: String?,
        endDate: String,
        minimum: Int = 90,
        maximum: Int = 364
    ) -> Int {
        guard let earliestDate else { return minimum }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        guard let earliest = formatter.date(from: earliestDate),
            let end = formatter.date(from: endDate)
        else { return minimum }

        let span = calendar.dateComponents([.day], from: earliest, to: end).day ?? 0
        var days = min(max(span, minimum), maximum)

        // Round up so days ≡ 6 (mod 7), without exceeding maximum.
        let remainder = days % 7
        if remainder != 6 {
            let roundedUp = days + (6 - remainder + 7) % 7
            days = min(roundedUp, maximum)
        }
        return days
    }

    public static func build(
        days: [(date: String, costUsd: Double)],
        endDate: String,
        windowDays: Int = 364
    ) -> [[Int]] {
        guard windowDays > 0 else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        guard let end = formatter.date(from: endDate),
            let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: end)
        else { return [] }

        var byDate: [String: Double] = [:]
        for day in days {
            guard let date = formatter.date(from: day.date), date >= cutoff, date <= end else {
                continue
            }
            byDate[day.date] = max(byDate[day.date] ?? 0, day.costUsd)
        }
        let sortedCosts = byDate.values.filter { $0 > 0 }.sorted()
        func bucket(_ cost: Double) -> Int {
            guard cost > 0 else { return 0 }
            guard !sortedCosts.isEmpty else { return 1 }
            func threshold(_ percentile: Double) -> Double {
                let index = Int((Double(sortedCosts.count) - 1) * percentile)
                return sortedCosts[min(sortedCosts.count - 1, index)]
            }
            if cost <= threshold(0.25) { return 1 }
            if cost <= threshold(0.50) { return 2 }
            if cost <= threshold(0.75) { return 3 }
            return 4
        }

        let leadingDays = calendar.component(.weekday, from: cutoff) - 1
        let trailingDays = 7 - calendar.component(.weekday, from: end)
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: cutoff),
            let gridEnd = calendar.date(byAdding: .day, value: trailingDays, to: end)
        else { return [] }

        var columns: [[Int]] = []
        var current: [Int] = []
        var date = gridStart
        while date <= gridEnd {
            if date < cutoff || date > end {
                current.append(-1)
            } else {
                current.append(bucket(byDate[formatter.string(from: date)] ?? 0))
            }
            if current.count == 7 {
                columns.append(current)
                current = []
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else {
                return []
            }
            date = next
        }
        return columns
    }
}
