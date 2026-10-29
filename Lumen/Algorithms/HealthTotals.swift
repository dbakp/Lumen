import Foundation

public enum HealthTotals {
    /// HealthKit totals exclude samples written by Lumen, so local logs are counted exactly once.
    /// Imported daily totals can overlap local logs: use the larger until a live source exists.
    public static func nutrient(local: Double, external: Double?, imported: Double?, excludesLumen: Bool) -> Double {
        if excludesLumen, let external { return local + external }
        return max(local, external ?? imported ?? 0)
    }
    public static func water(local: Double, snapshot: Double, imported: Double?, excludesLumen: Bool) -> Double {
        max(excludesLumen ? local + snapshot : max(local, snapshot), imported ?? 0)
    }
}
