import Foundation

public enum ReminderPolicy {
    public static func isQuiet(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return true }
        return start > end ? hour >= start || hour < end : hour >= start && hour < end
    }
}

