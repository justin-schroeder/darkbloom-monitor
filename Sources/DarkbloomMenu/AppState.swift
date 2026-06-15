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
    @Published var catalog: [CoordinatorAPI.CatalogModel] = []
    @Published var currentModels: [String] = []
    @Published var downloadedModels: Set<String> = []
    @Published var hardwareMetrics: HardwareMetrics = .empty

    let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    private var localTimer: Timer?
    private var remoteTimer: Timer?
    private let localSerial = AppState.machineSerialNumber()

    func start() {
        refreshLocal()
        Task { await refreshRemote() }
        Task { await refreshCatalog() }
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
        hardwareMetrics = HardwareMetricsReader.snapshot()
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

    /// Catalog + local download inventory + current selection, for the
    /// restart model picker. Refreshed at launch and whenever the picker opens.
    func refreshCatalog() async {
        currentModels = LaunchAgentPlist.currentModels()
        downloadedModels = LocalModels.downloadedIDs()
        if let models = try? await CoordinatorAPI.modelCatalog() {
            catalog = models
        }
    }

    // MARK: - Control (delegates to the darkbloom CLI / launchctl agent)

    func runControl(_ verb: String) {
        // `darkbloom start` with no --model flags blocks on an interactive
        // picker, so replay the models recorded in the LaunchAgent plist.
        let args = verb == "start" ? AppState.startArguments() : [verb]
        run(args, expectRunning: verb != "stop")
    }

    /// Start serving exactly `models` — `darkbloom start --model …`
    /// rewrites the LaunchAgent plist and relaunches the provider in place
    /// when already running.
    func startServing(models: [String], prewarm: Bool) {
        guard !models.isEmpty else { return }
        run(["start"] + models.flatMap { ["--model", $0] },
            expectRunning: true,
            prewarmModels: prewarm ? models : [])
    }

    private func run(_ args: [String], expectRunning: Bool, prewarmModels: [String] = []) {
        guard !controlBusy else { return }
        controlBusy = true
        controlError = nil
        Task {
            await AppState.runCLI(args)
            if expectRunning {
                // Wait for the daemon to boot and write fresh state; the
                // 3s poll timer takes over after the startup/warmup window.
                for _ in 0..<15 {
                    try? await Task.sleep(for: .seconds(2))
                    refreshLocal()
                    if prewarmModels.isEmpty {
                        if status != .stopped { break }
                    } else if status == .serving {
                        break
                    }
                }
                if status == .stopped {
                    controlError = "Couldn't start — run `darkbloom start` in Terminal once."
                } else if !prewarmModels.isEmpty {
                    await prewarm(models: prewarmModels)
                }
            } else {
                try? await Task.sleep(for: .seconds(2))
            }
            controlBusy = false
            refreshLocal()
            currentModels = LaunchAgentPlist.currentModels()
        }
    }

    private func prewarm(models: [String]) async {
        guard let localSerial else {
            controlError = "Couldn't pre-warm — machine serial unavailable."
            return
        }
        do {
            try await CoordinatorAPI.warmupMachine(serialNumber: localSerial, models: models)
        } catch {
            controlError = "Pre-warm failed — \(error.localizedDescription)"
        }
    }

    nonisolated private static func startArguments() -> [String] {
        let models = LaunchAgentPlist.currentModels()
        guard !models.isEmpty else { return ["restart"] }
        return ["start"] + models.flatMap { ["--model", $0] }
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
