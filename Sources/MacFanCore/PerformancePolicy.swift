import Foundation

public enum PerformancePolicy {
    public static let closedMenuTemperatureInterval: TimeInterval = 10.0
    public static let openMenuRefreshInterval: TimeInterval = 1.0
}

public struct ManualWritePolicy: Sendable {
    public let minimumInterval: TimeInterval
    public let minimumDeltaRPM: Int

    public init(minimumInterval: TimeInterval = 0.35, minimumDeltaRPM: Int = 100) {
        self.minimumInterval = minimumInterval
        self.minimumDeltaRPM = minimumDeltaRPM
    }

    public func shouldWrite(lastWriteTime: TimeInterval?, lastRPM: Int?, newTime: TimeInterval, newRPM: Int) -> Bool {
        guard let lastWriteTime, let lastRPM else { return true }
        guard newTime - lastWriteTime >= minimumInterval else { return false }
        return abs(newRPM - lastRPM) >= minimumDeltaRPM
    }
}
