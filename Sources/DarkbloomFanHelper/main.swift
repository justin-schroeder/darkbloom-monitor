import DarkbloomCore
import Foundation

private func usage() -> Never {
    FileHandle.standardError.write(
        Data("usage: DarkbloomFanHelper apply <hottest|cpu|gpu> <startC> <fullC> | automatic\n".utf8)
    )
    exit(64)
}

let args = CommandLine.arguments.dropFirst()
guard let command = args.first else {
    usage()
}

let status: FanControlStatus

switch command {
case "apply":
    guard args.count == 4,
          let sensor = FanControlSensorSelection(rawValue: args.dropFirst().first ?? ""),
          let start = Double(args.dropFirst(2).first ?? ""),
          let full = Double(args.dropFirst(3).first ?? "")
    else {
        usage()
    }
    let metrics = HardwareMetricsReader.snapshot()
    status = FanControl.apply(
        configuration: FanControlConfiguration(
            enabled: true,
            sensor: sensor,
            startTemperatureC: start,
            fullSpeedTemperatureC: full
        ),
        metrics: metrics
    )

case "automatic":
    status = FanControl.restoreAutomatic()

default:
    usage()
}

print(status.commandOutput)

switch status {
case .failed:
    exit(1)
default:
    exit(0)
}
