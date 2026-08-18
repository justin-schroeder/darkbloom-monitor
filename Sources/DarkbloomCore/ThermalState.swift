import Foundation

/// Apple's qualitative thermal pressure levels (`ProcessInfo.thermalState`).
/// The provider forwards the same four states with each heartbeat, and the
/// coordinator scales this machine's serving health by them, so elevated
/// states directly reduce routing and earnings. Apple publishes no fixed
/// temperature boundaries; the state is the OS's own judgement.
public enum ThermalState: Int, CaseIterable, Comparable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        // A future unknown level is treated as elevated without claiming
        // the coordinator blocks routing for it.
        @unknown default: self = .serious
        }
    }

    /// Parses the `thermal_state` string the provider writes to
    /// daemon-state.json and forwards to the coordinator.
    public init?(daemonString: String) {
        switch daemonString.trimmingCharacters(in: .whitespaces).lowercased() {
        case "nominal": self = .nominal
        case "fair": self = .fair
        case "serious": self = .serious
        case "critical": self = .critical
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        }
    }

    /// Multiplier the coordinator applies to this machine's serving health.
    public var servingHealthMultiplier: Double {
        switch self {
        case .nominal: return 1
        case .fair: return 0.8
        case .serious: return 0.4
        case .critical: return 0
        }
    }

    /// At critical the coordinator stops routing requests to this machine.
    public var blocksRouting: Bool {
        self == .critical
    }

    public var isElevated: Bool {
        self != .nominal
    }

    public static func < (lhs: ThermalState, rhs: ThermalState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
