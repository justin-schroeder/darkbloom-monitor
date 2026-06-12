import AppKit
import Combine
import DarkbloomCore
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

@MainActor
final class AppState: ObservableObject {
    @Published var status: NodeStatus = .stopped
    @Published var daemon: DaemonState?
    @Published var earnings: CoordinatorAPI.AccountEarnings?
    @Published var fleet: [FleetMachine] = []
    @Published var windows = EarningsWindows()
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
        localTimer?.tolerance = 1
        remoteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refreshRemote() }
        }
        remoteTimer?.tolerance = 5
    }

    // MARK: - Local state (daemon-state.json)

    func refreshLocal() {
        let state = DarkbloomPaths.readDaemonState()
        daemon = state
        guard let state, state.isFresh(), state.processAlive else {
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
            windows = EarningsMath.windows(acct.earnings)
            hourlyJobs = EarningsMath.hourlyBuckets(acct.earnings)
            fleet = Fleet.machines(connected: connected, earnings: acct.earnings, localSerial: localSerial)
        } catch {
            remoteError = error.localizedDescription
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
        if let data = try? Data(contentsOf: DarkbloomPaths.launchAgentPlist),
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
