import AppKit
import Combine
import Darwin
import DarkbloomCore
import DarkbloomMenuSupport
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
    @Published var fanControlStatus: FanControlStatus = .automatic
    @Published var fanHelperInstalled = FanHelper.isInstalled
    @Published var fanHelperInstallBusy = false
    @Published var fanHelperInstallError: String?
    @Published var externalFanControllerActive = false

    let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    private var localTimer: Timer?
    private var remoteTimer: Timer?
    private var preferencesCancellable: AnyCancellable?
    private let localSerial = AppState.machineSerialNumber()
    private var lastFreshDaemon: DaemonState?
    private var daemonReadMisses = 0
    private var hardwareRefreshInFlight = false
    private var fanControlInFlight = false
    private var fanControlSettings: FanControlSettings = .defaultValue

    private static let daemonReadMissTolerance = 2

    func bindPreferences(_ preferences: MenuPreferencesStore) {
        fanControlSettings = preferences.snapshot.fanControl
        preferencesCancellable = preferences.$snapshot
            .map(\.fanControl)
            .removeDuplicates()
            .sink { [weak self] settings in
                Task { @MainActor in
                    self?.fanControlSettings = settings
                    if !settings.enabled {
                        self?.restoreAutomaticFanControl()
                    }
                }
            }
    }

    func restoreAutomaticFanControl() {
        guard !fanControlInFlight else { return }
        fanControlInFlight = true
        Task {
            let status = await Task.detached(priority: .utility) {
                FanHelper.restoreAutomatic()
            }.value
            fanControlStatus = status
            fanControlInFlight = false
        }
    }

    func installFanHelper() {
        guard !fanHelperInstallBusy else { return }
        fanHelperInstallBusy = true
        fanHelperInstallError = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FanHelper.install() }
            }.value
            switch result {
            case .success:
                fanHelperInstalled = FanHelper.isInstalled
                fanHelperInstallError = nil
            case .failure(let error):
                fanHelperInstalled = FanHelper.isInstalled
                fanHelperInstallError = error.localizedDescription
            }
            fanHelperInstallBusy = false
        }
    }

    func start() {
        refreshLocal()
        refreshHardwareMetrics()
        Task { await refreshRemote() }
        Task { await refreshCatalog() }
        localTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocal()
                self?.refreshHardwareMetrics()
            }
        }
        localTimer?.tolerance = 1
        remoteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refreshRemote() }
        }
        remoteTimer?.tolerance = 5
    }

    // MARK: - Local state (daemon-state.json)

    func refreshLocal() {
        let readState = DarkbloomPaths.readDaemonState()
        let state = freshRunningState(from: readState)
        daemon = state ?? readState
        guard let state else {
            status = .stopped
            return
        }
        status = state.trust?.status == "online" ? .serving : .running
    }

    func refreshModelSelection() {
        currentModels = LaunchAgentPlist.currentModels()
        downloadedModels = LocalModels.downloadedIDs()
    }

    private func refreshHardwareMetrics() {
        guard !hardwareRefreshInFlight else { return }
        hardwareRefreshInFlight = true
        Task {
            let metrics = await Task.detached(priority: .utility) {
                HardwareMetricsReader.snapshot()
            }.value
            hardwareMetrics = metrics
            hardwareRefreshInFlight = false
            externalFanControllerActive = Self.isExternalFanControllerActive()
            applyFanControl(metrics: metrics)
        }
    }

    private func applyFanControl(metrics: HardwareMetrics) {
        let settings = fanControlSettings
        guard settings.enabled else {
            fanControlStatus = .automatic
            return
        }
        guard !externalFanControllerActive else {
            fanControlStatus = .unavailable("external fan controller active")
            return
        }
        guard !fanControlInFlight else { return }
        fanControlInFlight = true
        Task {
            let configuration = FanControlConfiguration(
                enabled: settings.enabled,
                sensor: settings.sensor.coreSelection,
                startTemperatureC: settings.startTemperatureC,
                fullSpeedTemperatureC: settings.fullSpeedTemperatureC
            )
            let status = await Task.detached(priority: .utility) {
                FanHelper.apply(configuration: configuration)
            }.value
            fanControlStatus = status
            fanHelperInstalled = FanHelper.isInstalled
            fanControlInFlight = false
        }
    }

    private static func isExternalFanControllerActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.crystalidea.macsfancontrol"
        }
    }

    private func freshRunningState(from readState: DaemonState?) -> DaemonState? {
        if let readState {
            daemonReadMisses = 0
            guard readState.isFresh(), readState.processAlive else {
                lastFreshDaemon = nil
                return nil
            }
            lastFreshDaemon = readState
            return readState
        }

        guard daemonReadMisses < Self.daemonReadMissTolerance,
              let lastFreshDaemon,
              lastFreshDaemon.isFresh(),
              lastFreshDaemon.processAlive else {
            self.lastFreshDaemon = nil
            return nil
        }
        daemonReadMisses += 1
        return lastFreshDaemon
    }

    // MARK: - Coordinator data

    func refreshRemote() async {
        do {
            async let earningsTask = CoordinatorAPI.accountEarnings()
            async let connectedTask = CoordinatorAPI.connectedProviders()
            let acct = try await earningsTask
            let connected: [CoordinatorAPI.AttestedProvider]
            do {
                connected = try await connectedTask
                remoteError = nil
            } catch {
                connected = []
                remoteError = "Fleet unavailable — \(error.localizedDescription)"
            }
            earnings = acct
            windows = EarningsMath.windows(acct.earnings)
            hourlyJobs = EarningsMath.hourlyBuckets(acct.earnings)
            fleet = Fleet.machines(connected: connected, earnings: acct.earnings, localSerial: localSerial)
        } catch {
            remoteError = error.localizedDescription
            earnings = nil
            windows = EarningsWindows()
            hourlyJobs = []
            fleet = []
        }
    }

    /// Catalog + local download inventory + current selection, for the
    /// restart model picker. Refreshed at launch and whenever the picker opens.
    func refreshCatalog() async {
        refreshModelSelection()
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
            requestedModels: models,
            prewarmModels: prewarm ? models : [])
    }

    private func run(
        _ args: [String],
        expectRunning: Bool,
        requestedModels: [String] = [],
        prewarmModels: [String] = []
    ) {
        guard !controlBusy else { return }
        controlBusy = true
        controlError = nil
        Task {
            let result = await AppState.runCLI(args)
            guard result.succeeded else {
                controlError = result.displayMessage(for: args)
                controlBusy = false
                refreshLocal()
                currentModels = LaunchAgentPlist.currentModels()
                return
            }

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
                }

                currentModels = LaunchAgentPlist.currentModels()
                if controlError == nil,
                   !requestedModels.isEmpty,
                   Set(currentModels) != Set(requestedModels) {
                    controlError = "Couldn't update served models — check `darkbloom start` in Terminal."
                }

                if controlError == nil, !prewarmModels.isEmpty {
                    await prewarm(models: prewarmModels)
                }
            } else {
                try? await Task.sleep(for: .seconds(2))
                refreshLocal()
                if status != .stopped {
                    controlError = "Couldn't stop — check `darkbloom stop` in Terminal."
                }
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

    nonisolated private static func runCLI(_ args: [String]) async -> CLIResult {
        await withCheckedContinuation { (cont: CheckedContinuation<CLIResult, Never>) in
            let execution = CLIExecution(continuation: cont)
            let proc = Process()
            let stderr = Pipe()
            proc.executableURL = DarkbloomPaths.cli
            proc.arguments = args
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = stderr
            proc.standardInput = FileHandle.nullDevice
            stderr.fileHandleForReading.readabilityHandler = { handle in
                execution.append(handle.availableData)
            }
            proc.terminationHandler = { process in
                execution.finish(
                    exitCode: process.terminationStatus,
                    pipe: stderr,
                    drainPipe: true
                )
            }
            do {
                try proc.run()
                execution.startTimeout(for: proc, args: args, pipe: stderr)
            } catch {
                execution.finish(exitCode: -1, message: error.localizedDescription, pipe: stderr)
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

private extension FanControlSensor {
    var coreSelection: FanControlSensorSelection {
        switch self {
        case .hottest: return .hottest
        case .cpu: return .cpu
        case .gpu: return .gpu
        }
    }
}

private struct CLIResult {
    var exitCode: Int32
    var message: String?

    var succeeded: Bool {
        exitCode == 0
    }

    func displayMessage(for args: [String]) -> String {
        let command = (["darkbloom"] + args).joined(separator: " ")
        if let message, !message.isEmpty {
            return "\(command) failed — \(message)"
        }
        return "\(command) failed with exit code \(exitCode)."
    }
}

private final class CLIExecution: @unchecked Sendable {
    private static let timeout: TimeInterval = 60
    private static let terminationGrace: TimeInterval = 3

    private let continuation: CheckedContinuation<CLIResult, Never>
    private let lock = NSLock()
    private var stderrData = Data()
    private var finished = false

    init(continuation: CheckedContinuation<CLIResult, Never>) {
        self.continuation = continuation
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        if !finished {
            stderrData.append(data)
        }
        lock.unlock()
    }

    func startTimeout(for process: Process, args: [String], pipe: Pipe) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            guard let self else { return }
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.terminationGrace) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }

            let command = (["darkbloom"] + args).joined(separator: " ")
            self.finish(
                exitCode: -2,
                message: "\(command) timed out after \(Int(Self.timeout)) seconds.",
                pipe: pipe
            )
        }
    }

    func finish(
        exitCode: Int32,
        message: String? = nil,
        pipe: Pipe,
        drainPipe: Bool = false
    ) {
        pipe.fileHandleForReading.readabilityHandler = nil
        if drainPipe {
            append(pipe.fileHandleForReading.readDataToEndOfFile())
        }
        resume(exitCode: exitCode, message: message ?? stderrMessage())
    }

    private func stderrMessage() -> String? {
        lock.lock()
        let data = stderrData
        lock.unlock()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resume(exitCode: Int32, message: String?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        continuation.resume(returning: CLIResult(exitCode: exitCode, message: message))
    }
}
