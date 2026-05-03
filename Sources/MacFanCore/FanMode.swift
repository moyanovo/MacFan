import Foundation

public enum FanPreset: String, CaseIterable, Equatable, Sendable, Identifiable {
    case silent
    case balanced
    case cool
    case max

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .silent: "Silent"
        case .balanced: "Balanced"
        case .cool: "Cool"
        case .max: "Max"
        }
    }

    private var fraction: Double {
        switch self {
        case .silent: 0.15
        case .balanced: 0.35
        case .cool: 0.65
        case .max: 1.0
        }
    }

    public func targetRPM(in range: FanRange) -> Int {
        guard range.maxRPM > range.minRPM else { return range.minRPM }
        let span = Double(range.maxRPM - range.minRPM)
        let raw = Double(range.minRPM) + span * fraction
        return range.clamped(Int(raw.rounded()))
    }
}

public enum FanMode: Equatable, Sendable {
    case systemAuto
    case preset(FanPreset)
    case manualLinear

    public var displayName: String {
        switch self {
        case .systemAuto: "System Auto"
        case .preset(let preset): preset.displayName
        case .manualLinear: "Manual"
        }
    }
}
