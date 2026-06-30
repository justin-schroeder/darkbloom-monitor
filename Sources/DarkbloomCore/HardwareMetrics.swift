import Darwin
import Foundation
import IOKit

public struct HardwareMetrics: Equatable, Sendable {
    public var memoryUsedFraction: Double?
    public var fanRPMs: [Double]
    public var averageCPUTempC: Double?
    public var averageGPUTempC: Double?

    public init(
        memoryUsedFraction: Double?,
        fanRPMs: [Double],
        averageCPUTempC: Double?,
        averageGPUTempC: Double?
    ) {
        self.memoryUsedFraction = memoryUsedFraction
        self.fanRPMs = fanRPMs
        self.averageCPUTempC = averageCPUTempC
        self.averageGPUTempC = averageGPUTempC
    }

    public static let empty = HardwareMetrics(
        memoryUsedFraction: nil,
        fanRPMs: [],
        averageCPUTempC: nil,
        averageGPUTempC: nil
    )
}

public enum FanControlSensorSelection: String, Equatable, Sendable {
    case hottest
    case cpu
    case gpu
}

public struct FanControlConfiguration: Equatable, Sendable {
    public var enabled: Bool
    public var sensor: FanControlSensorSelection
    public var startTemperatureC: Double
    public var fullSpeedTemperatureC: Double

    public init(
        enabled: Bool,
        sensor: FanControlSensorSelection,
        startTemperatureC: Double,
        fullSpeedTemperatureC: Double
    ) {
        self.enabled = enabled
        self.sensor = sensor
        self.startTemperatureC = startTemperatureC
        self.fullSpeedTemperatureC = max(fullSpeedTemperatureC, startTemperatureC + 1)
    }
}

public enum FanControlStatus: Equatable, Sendable {
    case automatic
    case manual(percent: Double, temperatureC: Double)
    case unavailable(String)
    case failed(String)

    public var displayText: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .manual(let percent, let temperatureC):
            return String(format: "Cooling assist %.0f%% at %.0f°", percent * 100, temperatureC)
        case .unavailable(let reason):
            if reason == "manual fan control denied" {
                return "Automatic - manual fan control unavailable"
            }
            if reason == "install fan helper" {
                return "Install fan helper to enable cooling assist"
            }
            if reason == "external fan controller active" {
                return "Paused - another fan controller is running"
            }
            if reason == "fan target not confirmed" {
                return "Cooling not confirmed"
            }
            return "Unavailable - \(reason)"
        case .failed(let reason):
            return "Failed - \(reason)"
        }
    }

    public var commandOutput: String {
        switch self {
        case .automatic:
            return "automatic"
        case .manual(let percent, let temperatureC):
            return String(format: "manual %.6f %.6f", percent, temperatureC)
        case .unavailable(let reason):
            return "unavailable \(reason)"
        case .failed(let reason):
            return "failed \(reason)"
        }
    }

    public static func commandOutput(_ output: String) -> FanControlStatus? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "automatic" {
            return .automatic
        }
        if trimmed.hasPrefix("manual ") {
            let parts = trimmed.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count == 3,
                  let percent = Double(parts[1]),
                  let temperatureC = Double(parts[2])
            else { return nil }
            return .manual(percent: percent, temperatureC: temperatureC)
        }
        if trimmed.hasPrefix("unavailable ") {
            return .unavailable(String(trimmed.dropFirst("unavailable ".count)))
        }
        if trimmed.hasPrefix("failed ") {
            return .failed(String(trimmed.dropFirst("failed ".count)))
        }
        return nil
    }
}

public enum FanControl {
    private static let supportLock = NSLock()
    private static var manualControlRejected = false

    public static func apply(
        configuration: FanControlConfiguration,
        metrics: HardwareMetrics
    ) -> FanControlStatus {
        guard configuration.enabled else {
            return restoreAutomatic()
        }
        guard !hasRejectedManualControl else {
            return .unavailable("manual fan control denied")
        }
        guard let temperature = selectedTemperature(configuration.sensor, metrics: metrics) else {
            let status = restoreAutomatic()
            if case .failed = status { return status }
            return .unavailable("no temperature sensor")
        }
        guard let smc = SMCReader() else {
            return .unavailable("SMC unavailable")
        }
        let fans = smc.fans()
        guard !fans.isEmpty else {
            return .unavailable("no fans")
        }
        guard temperature >= configuration.startTemperatureC else {
            return smc.setAutomatic(fans: fans)
        }

        let span = max(configuration.fullSpeedTemperatureC - configuration.startTemperatureC, 1)
        let percent = min(max((temperature - configuration.startTemperatureC) / span, 0), 1)
        var failed = false
        var requestedTargets: [Int: Double] = [:]

        for fan in fans {
            let minRPM = fan.minimumRPM ?? 1_200
            let maxRPM = max(fan.maximumRPM ?? max(minRPM, 6_000), minRPM + 1)
            let rampRPM = minRPM + (maxRPM - minRPM) * percent
            let targetRPM = percent >= 1
                ? maxRPM
                : max(rampRPM, fan.currentRPM ?? rampRPM)
            requestedTargets[fan.index] = targetRPM
            if fan.supportsManualMode, !smc.setFanManual(index: fan.index, manual: true) {
                failed = true
            }
            if !smc.setFanTargetRPM(index: fan.index, rpm: targetRPM) {
                failed = true
            }
        }

        if failed {
            _ = smc.setAutomatic(fans: fans)
            markManualControlRejected()
            return .unavailable("manual fan control denied")
        }
        let confirmedFans = Dictionary(uniqueKeysWithValues: smc.fans().map { ($0.index, $0) })
        let targetConfirmed = requestedTargets.allSatisfy { index, targetRPM in
            guard let targetReadback = confirmedFans[index]?.targetRPM else { return false }
            return abs(targetReadback - targetRPM) <= 250 || targetReadback >= targetRPM * 0.9
        }
        guard targetConfirmed else {
            return .unavailable("fan target not confirmed")
        }
        return .manual(percent: percent, temperatureC: temperature)
    }

    @discardableResult
    public static func restoreAutomatic() -> FanControlStatus {
        guard let smc = SMCReader() else {
            return .unavailable("SMC unavailable")
        }
        let fans = smc.fans()
        guard !fans.isEmpty else {
            return .unavailable("no fans")
        }
        return smc.setAutomatic(fans: fans)
    }

    private static func selectedTemperature(
        _ sensor: FanControlSensorSelection,
        metrics: HardwareMetrics
    ) -> Double? {
        switch sensor {
        case .hottest:
            return [metrics.averageCPUTempC, metrics.averageGPUTempC].compactMap(\.self).max()
        case .cpu:
            return metrics.averageCPUTempC
        case .gpu:
            return metrics.averageGPUTempC
        }
    }

    private static var hasRejectedManualControl: Bool {
        supportLock.lock()
        defer { supportLock.unlock() }
        return manualControlRejected
    }

    private static func markManualControlRejected() {
        supportLock.lock()
        manualControlRejected = true
        supportLock.unlock()
    }
}

public enum HardwareMetricsReader {
    private static let sensorKeyLock = NSLock()
    private static var cachedCPUTemperatureKeys: [String]?
    private static var cachedGPUTemperatureKeys: [String]?

    public static func snapshot() -> HardwareMetrics {
        let smc = SMCReader()
        let temperatureKeys = smc.map(discoveredTemperatureKeys)
        let cpuTemp = smc.flatMap { reader in
            if let keys = temperatureKeys?.cpu, !keys.isEmpty {
                return reader.averageTemperature(keys: keys)
            }
            return reader.averageTemperature(keys: SMCReader.cpuTemperatureKeys)
        }
        let gpuTemp = smc.flatMap { reader in
            if let keys = temperatureKeys?.gpu, !keys.isEmpty {
                return reader.averageTemperature(keys: keys)
            }
            return reader.averageTemperature(keys: SMCReader.gpuTemperatureKeys)
        }
        return HardwareMetrics(
            memoryUsedFraction: memoryUsedFraction(),
            fanRPMs: smc?.fanRPMs() ?? [],
            averageCPUTempC: cpuTemp,
            averageGPUTempC: gpuTemp
        )
    }

    private static func discoveredTemperatureKeys(_ reader: SMCReader) -> (cpu: [String], gpu: [String]) {
        sensorKeyLock.lock()
        if let cpu = cachedCPUTemperatureKeys, let gpu = cachedGPUTemperatureKeys {
            sensorKeyLock.unlock()
            return (cpu, gpu)
        }
        sensorKeyLock.unlock()

        let keys = reader.readAllKeys()
        let cpu = keys.filter { key in
            key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("Ts")
                || key.hasPrefix("TP") || key.hasPrefix("TS")
        }
        let gpu = keys.filter { key in
            key.hasPrefix("Tg") || key.hasPrefix("TG")
        }

        sensorKeyLock.lock()
        cachedCPUTemperatureKeys = cpu
        cachedGPUTemperatureKeys = gpu
        sensorKeyLock.unlock()

        return (cpu, gpu)
    }

    private static func memoryUsedFraction() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let totalPages = ProcessInfo.processInfo.physicalMemory / pageSize
        guard totalPages > 0 else { return nil }

        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return min(max(Double(usedPages) / Double(totalPages), 0), 1)
    }
}

private final class SMCReader {
    struct Fan {
        var index: Int
        var currentRPM: Double?
        var targetRPM: Double?
        var minimumRPM: Double?
        var maximumRPM: Double?
        var supportsManualMode: Bool
    }

    static let cpuTemperatureKeys = [
        "TC0P", "TC0E", "TC0F", "TC0H", "TC0D",
        "TC0C", "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C", "TC8C",
    ]
    static let gpuTemperatureKeys = [
        "TG0P", "TG0D", "TG0H", "TG0T",
        "TG1D", "TG2D", "TG3D", "TG4D",
    ]

    private struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct KeyData {
        var key: UInt32 = 0
        var version = Version()
        var versionPadding: UInt16 = 0
        var pLimitData = PLimitData()
        var keyInfo = KeyInfo()
        var keyInfoPadding: (UInt8, UInt8, UInt8) = (0, 0, 0)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private struct Value {
        var dataType: String
        var bytes: [UInt8]
    }

    private let connection: io_connect_t

    init?() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC"),
            &iterator
        ) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var matchedService: io_service_t = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }

            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(service, &className)
            if String(cString: className) == "AppleSMCKeysEndpoint" {
                matchedService = service
                break
            }
            IOObjectRelease(service)
        }
        guard matchedService != 0 else { return nil }
        defer { IOObjectRelease(matchedService) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(matchedService, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func fanRPMs() -> [Double] {
        fans().compactMap { $0.currentRPM?.rounded() }
    }

    func fans() -> [Fan] {
        let count = Int(readNumeric("FNum") ?? 0)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            Fan(
                index: index,
                currentRPM: readNumeric("F\(index)Ac"),
                targetRPM: readNumeric("F\(index)Tg"),
                minimumRPM: readNumeric("F\(index)Mn"),
                maximumRPM: readNumeric("F\(index)Mx"),
                supportsManualMode: hasKey("F\(index)Md")
            )
        }
    }

    func setAutomatic(fans: [Fan]) -> FanControlStatus {
        var failed = false
        for fan in fans {
            if fan.supportsManualMode, !setFanManual(index: fan.index, manual: false) {
                failed = true
            }
        }
        return failed ? .failed("SMC rejected automatic fan mode") : .automatic
    }

    func setFanManual(index: Int, manual: Bool) -> Bool {
        writeNumeric("F\(index)Md", value: manual ? 1 : 0)
    }

    func setFanTargetRPM(index: Int, rpm: Double) -> Bool {
        writeNumeric("F\(index)Tg", value: rpm)
    }

    func averageTemperature(keys: [String]) -> Double? {
        let temps = keys.compactMap(readNumeric).filter { $0 > 0 && $0 < 130 }
        guard !temps.isEmpty else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
    }

    private func readNumeric(_ key: String) -> Double? {
        guard let value = readValue(key) else { return nil }
        switch value.dataType {
        case "sp78":
            guard value.bytes.count >= 2 else { return nil }
            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(Int16(bitPattern: raw)) / 256
        case "fpe2":
            guard value.bytes.count >= 2 else { return nil }
            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(raw) / 4
        case "flt ":
            guard value.bytes.count >= 4 else { return nil }
            let raw = UInt32(value.bytes[0])
                | UInt32(value.bytes[1]) << 8
                | UInt32(value.bytes[2]) << 16
                | UInt32(value.bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "ui8 ":
            guard let first = value.bytes.first else { return nil }
            return Double(first)
        case "ui16":
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
        case "ui32":
            guard value.bytes.count >= 4 else { return nil }
            return Double(
                UInt32(value.bytes[0]) << 24
                    | UInt32(value.bytes[1]) << 16
                    | UInt32(value.bytes[2]) << 8
                    | UInt32(value.bytes[3])
            )
        default:
            return nil
        }
    }

    func readAllKeys() -> [String] {
        guard let count = readNumeric("#KEY").map(UInt32.init) else { return [] }
        return (0..<count).compactMap(keyByIndex)
    }

    private func keyByIndex(_ index: UInt32) -> String? {
        var input = KeyData()
        var output = KeyData()
        input.data8 = 8
        input.data32 = index
        guard call(input: &input, output: &output) == kIOReturnSuccess,
              output.result == 0
        else { return nil }
        return Self.string(output.key)
    }

    private func readValue(_ key: String) -> Value? {
        let keyCode = Self.fourCharCode(key)
        var infoInput = KeyData()
        var infoOutput = KeyData()
        infoInput.key = keyCode
        infoInput.data8 = 9
        guard call(input: &infoInput, output: &infoOutput) == kIOReturnSuccess,
              infoOutput.result == 0
        else { return nil }

        var readInput = KeyData()
        var readOutput = KeyData()
        readInput.key = keyCode
        readInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        readInput.keyInfo.dataType = infoOutput.keyInfo.dataType
        readInput.data8 = 5
        guard call(input: &readInput, output: &readOutput) == kIOReturnSuccess,
              readOutput.result == 0
        else { return nil }

        let size = min(Int(infoOutput.keyInfo.dataSize), 32)
        let bytes = Array(Self.bytesArray(readOutput.bytes).prefix(size))
        return Value(dataType: Self.string(infoOutput.keyInfo.dataType), bytes: bytes)
    }

    private func hasKey(_ key: String) -> Bool {
        let keyCode = Self.fourCharCode(key)
        var infoInput = KeyData()
        var infoOutput = KeyData()
        infoInput.key = keyCode
        infoInput.data8 = 9
        return call(input: &infoInput, output: &infoOutput) == kIOReturnSuccess
            && infoOutput.result == 0
    }

    private func writeNumeric(_ key: String, value: Double) -> Bool {
        guard let existing = readValue(key),
              let bytes = Self.encode(value, as: existing.dataType)
        else { return false }
        return writeValue(key, bytes: bytes)
    }

    private func writeValue(_ key: String, bytes: [UInt8]) -> Bool {
        let keyCode = Self.fourCharCode(key)
        var infoInput = KeyData()
        var infoOutput = KeyData()
        infoInput.key = keyCode
        infoInput.data8 = 9
        guard call(input: &infoInput, output: &infoOutput) == kIOReturnSuccess,
              infoOutput.result == 0
        else { return false }

        var writeInput = KeyData()
        var writeOutput = KeyData()
        writeInput.key = keyCode
        writeInput.keyInfo = infoOutput.keyInfo
        writeInput.data8 = 6
        writeInput.bytes = Self.bytesTuple(Array(bytes.prefix(32)))

        return call(input: &writeInput, output: &writeOutput) == kIOReturnSuccess
            && writeOutput.result == 0
    }

    private func call(input: inout KeyData, output: inout KeyData) -> kern_return_t {
        var outputSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<KeyData>.stride,
            &output,
            &outputSize
        )
    }

    private static func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func string(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private static func bytesArray(_ bytes: SMCBytes) -> [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }

    private static func bytesTuple(_ bytes: [UInt8]) -> SMCBytes {
        let padded = bytes + Array(repeating: 0, count: max(0, 32 - bytes.count))
        return (
            padded[0], padded[1], padded[2], padded[3],
            padded[4], padded[5], padded[6], padded[7],
            padded[8], padded[9], padded[10], padded[11],
            padded[12], padded[13], padded[14], padded[15],
            padded[16], padded[17], padded[18], padded[19],
            padded[20], padded[21], padded[22], padded[23],
            padded[24], padded[25], padded[26], padded[27],
            padded[28], padded[29], padded[30], padded[31]
        )
    }

    private static func encode(_ value: Double, as dataType: String) -> [UInt8]? {
        switch dataType {
        case "fpe2":
            let raw = UInt16(max(0, min(value * 4, Double(UInt16.max))).rounded())
            return [UInt8(raw >> 8), UInt8(raw & 0xff)]
        case "ui8 ":
            return [UInt8(max(0, min(value, 255)).rounded())]
        case "ui16":
            let raw = UInt16(max(0, min(value, Double(UInt16.max))).rounded())
            return [UInt8(raw >> 8), UInt8(raw & 0xff)]
        case "ui32":
            let raw = UInt32(max(0, min(value, Double(UInt32.max))).rounded())
            return [
                UInt8((raw >> 24) & 0xff),
                UInt8((raw >> 16) & 0xff),
                UInt8((raw >> 8) & 0xff),
                UInt8(raw & 0xff),
            ]
        case "flt ":
            let raw = Float(value).bitPattern
            return [
                UInt8(raw & 0xff),
                UInt8((raw >> 8) & 0xff),
                UInt8((raw >> 16) & 0xff),
                UInt8((raw >> 24) & 0xff),
            ]
        default:
            return nil
        }
    }
}
