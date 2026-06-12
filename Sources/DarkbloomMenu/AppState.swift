import AppKit
import Combine
import Foundation
import IOKit

enum NodeStatus: Equatable {
    case serving      // running and trusted/online with the coordinator
    case running      // process up but not (yet) verified online
    case stopped

    var color: NSColor {
        switch self {
        case .serving: return .systemGreen
        case .running: return .systemOrange
        case .stopped: return .systemRed
        }
    }

    var label: String {
        switch self {
        case .serving: return "Online"
        case .running: return "Connecting…"
        case .stopped: return "Stopped"
        }
    }
}

/// A machine of yours that is currently connected to the coordinator.
/// Both provider_id and provider_key rotate across provider restarts, so
/// offline machines can't be enumerated from the public API — only machines
/// we can positively identify right now are listed: this Mac by hardware
/// serial, others by their current provider_id appearing in the account's
/// recent earnings.
struct HourBucket: Identifiable {
    var hour: Date
    var jobs: Int
    var microUSD: Int64
    var id: Date { hour }
}

struct FleetMachine: Identifiable {
    var live: CoordinatorAPI.AttestedProvider
    var isThisMac: Bool

    var id: String { live.providerID }

    var displayName: String {
        live.chipName.replacingOccurrences(of: "Apple ", with: "")
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: NodeStatus = .stopped
    @Published var daemon: DaemonState?
    @Published var earnings: CoordinatorAPI.AccountEarnings?
    @Published var fleet: [FleetMachine] = []
    @Published var last24hMicroUSD: Int64 = 0
    @Published var last7dMicroUSD: Int64 = 0
    @Published var last24hJobs: Int = 0
    @Published var hourlyJobs: [HourBucket] = []
    @Published var remoteError: String?
    @Published var controlBusy = false
    @Published var controlError: String?

    private var localTimer: Timer?
    private var remoteTimer: Timer?
    private let localSerial = AppState.machineSerialNumber()

    func start() {
        refreshLocal()
        Task { await refreshRemote() }
        localTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLocal() }
        }
        remoteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refreshRemote() }
        }
    }

    // MARK: - Local state (daemon-state.json)

    func refreshLocal() {
        let state = DarkbloomPaths.readDaemonState()
        daemon = state
        guard let state, state.isFresh, state.processAlive else {
            status = .stopped
            return
        }
        status = state.trust?.status == "online" ? .serving : .running
        controlError = nil
    }

    // MARK: - Coordinator data

    func refreshRemote() async {
        do {
            async let earningsTask = CoordinatorAPI.accountEarnings()
            async let connectedTask = CoordinatorAPI.connectedProviders()
            let acct = try await earningsTask
            let connected = (try? await connectedTask) ?? []
            earnings = acct
            remoteError = nil
            recomputeWindows(acct.earnings)
            rebuildFleet(acct.earnings, connected: connected)
        } catch {
            remoteError = error.localizedDescription
        }
    }

    private func recomputeWindows(_ entries: [CoordinatorAPI.Earning]) {
        let now = Date()
        let day = now.addingTimeInterval(-86_400)
        let week = now.addingTimeInterval(-7 * 86_400)
        var d: Int64 = 0, w: Int64 = 0, dj = 0
        for e in entries {
            if e.createdAt > week {
                w += e.amountMicroUSD
                if e.createdAt > day { d += e.amountMicroUSD; dj += 1 }
            }
        }
        last24hMicroUSD = d
        last7dMicroUSD = w
        last24hJobs = dj

        // 24 hourly buckets ending at the current hour, oldest first.
        let hourStart = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        var buckets: [Date: HourBucket] = [:]
        for i in 0..<24 {
            let h = hourStart.addingTimeInterval(Double(-i) * 3_600)
            buckets[h] = HourBucket(hour: h, jobs: 0, microUSD: 0)
        }
        for e in entries where e.createdAt > day {
            guard let h = Calendar.current.dateInterval(of: .hour, for: e.createdAt)?.start,
                  var b = buckets[h] else { continue }
            b.jobs += 1
            b.microUSD += e.amountMicroUSD
            buckets[h] = b
        }
        hourlyJobs = buckets.values.sorted { $0.hour < $1.hour }
    }

    private func rebuildFleet(_ entries: [CoordinatorAPI.Earning], connected: [CoordinatorAPI.AttestedProvider]) {
        let recentIDs = Set(entries.map(\.providerID))
        var seenSerials = Set<String>()
        fleet = connected
            .filter { $0.serialNumber == localSerial || recentIDs.contains($0.providerID) }
            .filter { seenSerials.insert($0.serialNumber).inserted }
            .map { FleetMachine(live: $0, isThisMac: $0.serialNumber == localSerial) }
            .sorted { a, b in
                if a.isThisMac != b.isThisMac { return a.isThisMac }
                return a.displayName < b.displayName
            }
    }

    // MARK: - Control (delegates to the darkbloom CLI / launchctl agent)

    func runControl(_ verb: String) {
        guard !controlBusy else { return }
        controlBusy = true
        controlError = nil
        Task {
            // `darkbloom start` with no --model flags blocks on an interactive
            // picker, so replay the models recorded in the LaunchAgent plist.
            let args = verb == "start" ? AppState.startArguments() : [verb]
            await AppState.runCLI(args)
            if verb == "stop" {
                try? await Task.sleep(for: .seconds(2))
            } else {
                // Wait for the daemon to boot and write fresh state; the
                // 3s poll timer takes over for the trust handshake.
                for _ in 0..<15 {
                    try? await Task.sleep(for: .seconds(2))
                    refreshLocal()
                    if status != .stopped { break }
                }
                if status == .stopped {
                    controlError = "Couldn't start — run `darkbloom start` in Terminal once."
                }
            }
            controlBusy = false
            refreshLocal()
        }
    }

    /// Models from the LaunchAgent plist written by the last `darkbloom start`;
    /// it survives `stop`, so a UI start serves the same models the user picked.
    nonisolated private static func startArguments() -> [String] {
        let plist = DarkbloomPaths.home
            .appendingPathComponent("Library/LaunchAgents/io.darkbloom.provider.plist")
        if let data = try? Data(contentsOf: plist),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let args = dict["ProgramArguments"] as? [String] {
            var models: [String] = []
            var i = 0
            while i < args.count - 1 {
                if args[i] == "--model" { models.append(args[i + 1]); i += 2 } else { i += 1 }
            }
            if !models.isEmpty {
                return ["start"] + models.flatMap { ["--model", $0] }
            }
        }
        return ["restart"]
    }

    nonisolated private static func runCLI(_ args: [String]) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let proc = Process()
            proc.executableURL = DarkbloomPaths.cli
            proc.arguments = args
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            proc.standardInput = FileHandle.nullDevice
            proc.terminationHandler = { _ in cont.resume() }
            do {
                try proc.run()
            } catch {
                cont.resume()
            }
        }
    }

    private static func machineSerialNumber() -> String? {
        let platform = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platform) }
        guard platform != 0,
              let serial = IORegistryEntryCreateCFProperty(
                  platform, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)?
                  .takeRetainedValue() as? String
        else { return nil }
        return serial
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func usd(_ micro: Int64) -> String {
        let dollars = Double(micro) / 1_000_000
        if dollars >= 100 { return String(format: "$%.2f", dollars) }
        if dollars >= 1 { return String(format: "$%.3f", dollars) }
        return String(format: "$%.4f", dollars)
    }

    static func count(_ n: UInt64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
