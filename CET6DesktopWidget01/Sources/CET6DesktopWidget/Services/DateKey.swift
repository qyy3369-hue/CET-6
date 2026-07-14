import Foundation

enum DateKey {
    static func today(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func from(_ date: Date, calendar: Calendar = .current) -> String {
        key(from: date, calendar: calendar)
    }

    static func from(month: Int, day: Int, calendar: Calendar = .current) -> String? {
        from(month: month, day: day, relativeTo: today(calendar: calendar), calendar: calendar)
    }

    static func from(month: Int, day: Int, relativeTo anchorKey: String, calendar: Calendar = .current) -> String? {
        guard let anchorDate = date(from: normalized(anchorKey) ?? anchorKey, calendar: calendar) else { return nil }
        let year = calendar.component(.year, from: anchorDate)
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else { return nil }
        return key(from: date, calendar: calendar)
    }

    static func displayLabel(for key: String, calendar: Calendar = .current) -> String {
        let normalizedKey = normalized(key) ?? key
        guard let date = date(from: normalizedKey, calendar: calendar) else { return key }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"

        let label = formatter.string(from: date)
        return normalizedKey == today(calendar: calendar) ? "\(label)（今天）" : label
    }

    static func normalized(_ key: String) -> String? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2])
    }

    static func isBeforeToday(_ key: String, calendar: Calendar = .current) -> Bool {
        guard let targetDate = date(from: normalized(key) ?? key, calendar: calendar),
              let todayDate = date(from: today(calendar: calendar), calendar: calendar) else {
            return false
        }

        return calendar.startOfDay(for: targetDate) < calendar.startOfDay(for: todayDate)
    }

    static func dayAfter(_ key: String, calendar: Calendar = .current) -> String? {
        guard let date = date(from: normalized(key) ?? key, calendar: calendar),
              let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
            return nil
        }

        return self.key(from: nextDate, calendar: calendar)
    }

    static func addingDays(_ days: Int, to key: String, calendar: Calendar = .current) -> String? {
        guard let date = date(from: normalized(key) ?? key, calendar: calendar),
              let targetDate = calendar.date(byAdding: .day, value: days, to: date) else {
            return nil
        }

        return self.key(from: targetDate, calendar: calendar)
    }

    private static func key(from date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
