import Foundation

public enum Fmt {
    public static func usd(_ micro: Int64) -> String {
        let dollars = Double(micro) / 1_000_000
        if dollars >= 100 { return String(format: "$%.2f", dollars) }
        if dollars >= 1 { return String(format: "$%.3f", dollars) }
        return String(format: "$%.4f", dollars)
    }

    public static func count(_ n: UInt64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    public static func uptime(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    public static func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
