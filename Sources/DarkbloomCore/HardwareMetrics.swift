import Darwin
import Foundation
import IOKit

public struct HardwareMetrics: Equatable {
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
        let count = Int(readNumeric("FNum") ?? 0)
        guard count > 0 else { return [] }
        return (0..<count).compactMap { index in
            readNumeric("F\(index)Ac").map { $0.rounded() }
        }
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
}
