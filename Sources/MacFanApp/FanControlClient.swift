import Foundation
import MacFanCore

enum AppFanControlClientError: Error {
    case helperFailed
}

struct AppFanControlClient: FanControlClient {
    private let helperURL: URL?

    init(helperURL: URL? = AppFanControlClient.defaultHelperURL()) {
        self.helperURL = helperURL
    }

    func temperatureCelsius() async -> Int? {
        guard let output = await runHelper(arguments: ["temperature"]) else {
            return nil
        }
        return Int(Self.field("temperature", in: output) ?? "")
    }

    func snapshot() async -> FanSnapshot {
        guard let output = await runHelper(arguments: ["snapshot"]) else {
            return .unavailable
        }
        return FanSnapshot(helperOutput: output)
    }

    func restoreSystemAuto() async throws {
        guard await runHelper(arguments: ["auto"]) != nil else {
            throw AppFanControlClientError.helperFailed
        }
    }

    func setTargetRPM(_ rpm: Int) async throws {
        guard await runHelper(arguments: ["rpm", String(rpm)]) != nil else {
            throw AppFanControlClientError.helperFailed
        }
    }

    private func runHelper(arguments: [String]) async -> String? {
        guard let helperURL else { return nil }
        return await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            process.executableURL = helperURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errorOutput
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                _ = errorOutput.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0, let string = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: string.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private static func defaultHelperURL() -> URL? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["MACFAN_HELPER_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let installed = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper")
        if fileManager.isExecutableFile(atPath: installed.path) {
            return installed
        }

        if let bundled = Bundle.main.url(forResource: "MacFanHelper", withExtension: nil),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let executable = Bundle.main.executableURL
        let productDirectory = executable?.deletingLastPathComponent()
        let sibling = productDirectory?.appendingPathComponent("MacFanHelper")
        if let sibling, fileManager.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        return nil
    }

    fileprivate static func field(_ name: String, in output: String) -> String? {
        for token in output.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == name else { continue }
            return parts[1]
        }
        return nil
    }
}

private extension FanSnapshot {
    init(helperOutput: String) {
        let fields = Dictionary(uniqueKeysWithValues: helperOutput.split(separator: " ").compactMap { token -> (String, String)? in
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        })

        let temperature = Int(fields["temperature"] ?? "")
        let currentRPM = Int(fields["currentRPM"] ?? "")
        let minRPM = Int(fields["minRPM"] ?? "")
        let maxRPM = Int(fields["maxRPM"] ?? "")
        let control = fields["control"] == "true"
        let range = minRPM.flatMap { minValue in maxRPM.map { FanRange(minRPM: minValue, maxRPM: $0) } }

        self.init(
            temperatureCelsius: temperature,
            currentRPM: currentRPM,
            range: range,
            isControlAvailable: control && range != nil
        )
    }
}
