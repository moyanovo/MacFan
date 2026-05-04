import Foundation

public struct FanRange: Equatable, Sendable {
    public let minRPM: Int
    public let maxRPM: Int

    public init(minRPM: Int, maxRPM: Int) {
        self.minRPM = min(minRPM, maxRPM)
        self.maxRPM = max(minRPM, maxRPM)
    }

    public func clamped(_ rpm: Int) -> Int {
        min(max(rpm, minRPM), maxRPM)
    }
}

public struct FanSnapshot: Equatable, Sendable {
    public let temperatureCelsius: Int?
    public let currentRPM: Int?
    public let range: FanRange?
    public let isControlAvailable: Bool

    public init(temperatureCelsius: Int?, currentRPM: Int?, range: FanRange?, isControlAvailable: Bool) {
        self.temperatureCelsius = temperatureCelsius
        self.currentRPM = currentRPM
        self.range = range
        self.isControlAvailable = isControlAvailable
    }

    public static let unavailable = FanSnapshot(
        temperatureCelsius: nil,
        currentRPM: nil,
        range: nil,
        isControlAvailable: false
    )
}

public protocol FanControlClient: Sendable {
    func temperatureCelsius() async -> Int?
    func snapshot() async -> FanSnapshot
    func restoreSystemAuto() async throws
    func setTargetRPM(_ rpm: Int) async throws
}
