import DarkbloomCore
import Foundation

enum FanHelper {
    static let installedURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/dev.darkbloom.monitor.fan-helper")

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: installedURL.path)
    }

    static func install() throws {
        let bundledURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/Helpers/DarkbloomFanHelper")
        guard FileManager.default.isExecutableFile(atPath: bundledURL.path) else {
            throw FanHelperError.missingBundledHelper
        }

        let command = "/usr/bin/install -o root -g wheel -m 4755 \(shellQuote(bundledURL.path)) \(shellQuote(installedURL.path))"
        let script = "do shell script \(appleScriptString(command)) with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0, isInstalled else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FanHelperError.installFailed(message?.isEmpty == false ? message! : "administrator authorization failed")
        }
    }

    static func apply(configuration: FanControlConfiguration) -> FanControlStatus {
        guard isInstalled else {
            return .unavailable("install fan helper")
        }
        return runHelper(arguments: [
            "apply",
            configuration.sensor.rawValue,
            String(configuration.startTemperatureC),
            String(configuration.fullSpeedTemperatureC),
        ])
    }

    static func restoreAutomatic() -> FanControlStatus {
        guard isInstalled else {
            return .automatic
        }
        return runHelper(arguments: ["automatic"])
    }

    private static func runHelper(arguments: [String]) -> FanControlStatus {
        let process = Process()
        process.executableURL = installedURL
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failed(error.localizedDescription)
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if let status = FanControlStatus.commandOutput(output) {
            return status
        }

        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(errorOutput?.isEmpty == false ? errorOutput! : "fan helper returned an invalid response")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

enum FanHelperError: LocalizedError {
    case missingBundledHelper
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledHelper:
            return "The bundled fan helper is missing from this app build."
        case .installFailed(let message):
            return message
        }
    }
}
