import Foundation
import IOKit
import MacFanCore

struct SMCClient {
    func temperature() -> String {
        do {
            let smc = try SMCConnection()
            let temperature = smc.firstTemperature(keys: Self.temperatureKeys)
            return [
                "temperature=\(temperature.map(String.init) ?? "nil")",
                "source=AppleSMC"
            ].joined(separator: " ")
        } catch {
            return "temperature=nil source=AppleSMC reason=apple_smc_unavailable"
        }
    }

    func snapshot() -> String {
        do {
            let smc = try SMCConnection()
            let fanCount = smc.readFanCount()
            let temperature = smc.firstTemperature(keys: Self.temperatureKeys)
            let currentRPM = smc.readRPM(key: "F0Ac")
            let minRPM = smc.readRPM(key: "F0Mn")
            let maxRPM = smc.readRPM(key: "F0Mx")
            let modeKey = smc.detectModeKeyFormat().map { String(format: $0, 0) } ?? "nil"
            let ftstAvailable = smc.keyExists("Ftst")
            let controlAvailable = fanCount > 0 && minRPM != nil && maxRPM != nil && modeKey != "nil"
            let reason = temperature == nil && currentRPM == nil && !controlAvailable ? " reason=smc_keys_unreadable" : ""

            return [
                "temperature=\(temperature.map(String.init) ?? "nil")",
                "currentRPM=\(currentRPM.map(String.init) ?? "nil")",
                "minRPM=\(minRPM.map(String.init) ?? "nil")",
                "maxRPM=\(maxRPM.map(String.init) ?? "nil")",
                "fanCount=\(fanCount)",
                "modeKey=\(modeKey)",
                "ftst=\(ftstAvailable ? "true" : "false")",
                "control=\(controlAvailable ? "true" : "false")",
                "source=AppleSMC\(reason)"
            ].joined(separator: " ")
        } catch {
            return unavailableSnapshot(reason: "apple_smc_unavailable")
        }
    }

    func restoreSystemAuto() throws {
        let smc = try SMCConnection()
        let fanCount = max(smc.readFanCount(), 1)
        var attemptedWrite = false
        var firstError: Error?

        if let modeFormat = smc.detectModeKeyFormat() {
            for fanIndex in 0..<fanCount {
                attemptedWrite = true
                do {
                    try smc.writeMode(key: String(format: modeFormat, fanIndex), mode: 0)
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
        }
        if smc.keyExists("Ftst") {
            attemptedWrite = true
            do {
                try smc.writeUInt8(key: "Ftst", value: 0)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let firstError { throw firstError }
        guard attemptedWrite else { throw SMCClientError.keyReadFailed("fan mode") }
    }

    func setTargetRPM(_ rpm: Int) throws -> Int {
        guard rpm > 0 else { throw SMCClientError.invalidRPM }
        let smc = try SMCConnection()
        let fanIndex = 0
        guard let modeFormat = smc.detectModeKeyFormat() else { throw SMCClientError.keyReadFailed("F0Md/F0md") }
        guard let minRPM = smc.readRPM(key: "F0Mn"), let maxRPM = smc.readRPM(key: "F0Mx") else {
            throw SMCClientError.keyReadFailed("F0Mn/F0Mx")
        }
        let safeRPM = min(max(rpm, minRPM), maxRPM)
        let modeKey = String(format: modeFormat, fanIndex)

        do {
            try smc.writeMode(key: modeKey, mode: 1)
        } catch {
            guard smc.keyExists("Ftst") else { throw error }
            try smc.writeUInt8(key: "Ftst", value: 1)
            try smc.retryModeUnlock(modeKey: modeKey)
        }

        do {
            try smc.writeRPM(key: "F0Tg", rpm: safeRPM)
        } catch {
            try? restoreSystemAuto()
            throw error
        }
        return safeRPM
    }

    private func unavailableSnapshot(reason: String) -> String {
        "temperature=nil currentRPM=nil minRPM=nil maxRPM=nil fanCount=0 modeKey=nil ftst=false control=false reason=\(reason)"
    }

    private static let temperatureKeys = [
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
        "Ts0P", "TC0P", "TC0E", "TC0F", "TC0D", "TC0H"
    ]
}

enum SMCClientError: Error {
    case invalidRPM
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case firmware(UInt8)
    case timeout
    case keyReadFailed(String)
}

private final class SMCConnection {
    private let connection: io_connect_t

    init() throws {
        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        let servicesResult = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator)
        guard servicesResult == kIOReturnSuccess else { throw SMCClientError.callFailed(servicesResult) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { throw SMCClientError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var opened: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
        guard result == KERN_SUCCESS else { throw SMCClientError.openFailed(result) }
        connection = opened
    }

    deinit {
        IOServiceClose(connection)
    }

    func readFanCount() -> Int {
        guard let value = try? readKey("FNum"), let first = value.bytes.first else { return 0 }
        return Int(first)
    }

    func detectModeKeyFormat() -> String? {
        for candidate in ["F%dmd", "F%dMd"] {
            if keyExists(String(format: candidate, 0)) { return candidate }
        }
        return nil
    }

    func keyExists(_ key: String) -> Bool {
        (try? fetchKeyInfo(key)) != nil
    }

    func firstTemperature(keys: [String]) -> Int? {
        for key in keys {
            guard let value = try? readKey(key), let temperature = decodeTemperature(value) else { continue }
            guard temperature > 0, temperature < 130 else { continue }
            return Int(temperature.rounded())
        }
        return nil
    }

    func readRPM(key: String) -> Int? {
        guard let value = try? readKey(key) else { return nil }
        switch value.type {
        case "flt ", "flt":
            return SMCValueCodec.decodeFloat(value.bytes).map { Int($0.rounded()) }
        case "fpe2":
            return SMCValueCodec.decodeFpe2(value.bytes)
        case "ui16":
            guard value.bytes.count >= 2 else { return nil }
            return Int(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
        default:
            return nil
        }
    }

    func writeMode(key: String, mode: UInt8) throws {
        try writeKey(key, bytes: [mode])
    }

    func writeUInt8(key: String, value: UInt8) throws {
        try writeKey(key, bytes: [value])
    }

    func retryModeUnlock(modeKey: String) throws {
        let deadline = Date().addingTimeInterval(10.0)
        while Date() < deadline {
            do {
                try writeMode(key: modeKey, mode: 1)
                return
            } catch {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        throw SMCClientError.timeout
    }

    func writeRPM(key: String, rpm: Int) throws {
        let info = try fetchKeyInfo(key)
        let bytes: [UInt8]
        switch info.type {
        case "flt ", "flt":
            bytes = SMCValueCodec.encodeFloat(Float(rpm))
        case "fpe2":
            bytes = SMCValueCodec.encodeFpe2(rpm)
        case "ui16":
            bytes = SMCValueCodec.encodeUInt16(UInt16(max(0, min(rpm, Int(UInt16.max)))))
        default:
            bytes = info.size == 4 ? SMCValueCodec.encodeFloat(Float(rpm)) : SMCValueCodec.encodeFpe2(rpm)
        }
        try writeKey(key, bytes: bytes)
    }

    private func writeKey(_ key: String, bytes: [UInt8]) throws {
        let info = try fetchKeyInfo(key)
        var input = SMCParamStruct()
        input.key = key.smcKeyCode
        input.data8 = SMCCommand.writeBytes.rawValue
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = info.dataType
        input.setBytes(bytes)

        let output = try call(input)
        guard output.result == 0 else { throw SMCClientError.firmware(output.result) }
    }

    private func readKey(_ key: String) throws -> SMCValue {
        let info = try fetchKeyInfo(key)
        var readInput = SMCParamStruct()
        readInput.key = key.smcKeyCode
        readInput.keyInfo.dataSize = info.size
        readInput.keyInfo.dataType = info.dataType
        readInput.data8 = SMCCommand.readBytes.rawValue
        let readOutput = try call(readInput)
        guard readOutput.result == 0 else { throw SMCClientError.firmware(readOutput.result) }

        let size = min(Int(info.size), 32)
        return SMCValue(key: key, type: info.type, bytes: Array(readOutput.byteArray.prefix(size)))
    }

    private func fetchKeyInfo(_ key: String) throws -> SMCKeyInfo {
        var input = SMCParamStruct()
        input.key = key.smcKeyCode
        input.data8 = SMCCommand.readKeyInfo.rawValue
        let output = try call(input)
        guard output.result == 0 else { throw SMCClientError.firmware(output.result) }
        return SMCKeyInfo(size: output.keyInfo.dataSize, dataType: output.keyInfo.dataType, type: output.keyInfo.dataType.smcString)
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var mutableInput = SMCParamStruct()
        mutableInput.key = input.key
        mutableInput.data8 = input.data8
        mutableInput.data32 = input.data32
        mutableInput.keyInfo.dataSize = input.keyInfo.dataSize
        mutableInput.keyInfo.dataType = input.keyInfo.dataType
        mutableInput.bytes = input.bytes

        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCCommand.kernelIndex.rawValue),
            &mutableInput,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )

        guard result == KERN_SUCCESS else { throw SMCClientError.callFailed(result) }
        return output
    }

    private func decodeTemperature(_ value: SMCValue) -> Double? {
        switch value.type {
        case "sp78":
            return SMCValueCodec.decodeSp78(value.bytes)
        case "flt ", "flt":
            return SMCValueCodec.decodeFloat(value.bytes).map(Double.init)
        case "ui8 ":
            return value.bytes.first.map(Double.init)
        case "ui16":
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
        default:
            return nil
        }
    }
}

private struct SMCValue {
    let key: String
    let type: String
    let bytes: [UInt8]
}

private struct SMCKeyInfo {
    let size: UInt32
    let dataType: UInt32
    let type: String
}

private enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case writeBytes = 6
    case readKeyInfo = 9
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamStruct {
    typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    var byteArray: [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }

    mutating func setBytes(_ newBytes: [UInt8]) {
        var padded = newBytes + Array(repeating: 0, count: max(0, 32 - newBytes.count))
        if padded.count > 32 { padded = Array(padded.prefix(32)) }
        bytes = (
            padded[0], padded[1], padded[2], padded[3], padded[4], padded[5], padded[6], padded[7],
            padded[8], padded[9], padded[10], padded[11], padded[12], padded[13], padded[14], padded[15],
            padded[16], padded[17], padded[18], padded[19], padded[20], padded[21], padded[22], padded[23],
            padded[24], padded[25], padded[26], padded[27], padded[28], padded[29], padded[30], padded[31]
        )
    }
}

private extension String {
    var smcKeyCode: UInt32 {
        utf8.prefix(4).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}

private extension UInt32 {
    var smcString: String {
        let bytes = [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
