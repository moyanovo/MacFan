import Foundation
import IOKit
import MacFanCore

struct SMCClient {
    func snapshot() -> String {
        do {
            let smc = try SMCConnection()
            let temperature = smc.firstTemperature(keys: Self.temperatureKeys)
            let currentRPM = smc.readRPM(key: "F0Ac")
            let minRPM = smc.readRPM(key: "F0Mn")
            let maxRPM = smc.readRPM(key: "F0Mx")
            let controlAvailable = minRPM != nil && maxRPM != nil

            let reason = temperature == nil && currentRPM == nil && !controlAvailable ? " reason=smc_keys_unreadable" : ""
            return [
                "temperature=\(temperature.map(String.init) ?? "nil")",
                "currentRPM=\(currentRPM.map(String.init) ?? "nil")",
                "minRPM=\(minRPM.map(String.init) ?? "nil")",
                "maxRPM=\(maxRPM.map(String.init) ?? "nil")",
                "control=\(controlAvailable ? "true" : "false")",
                "source=AppleSMC\(reason)"
            ].joined(separator: " ")
        } catch {
            return unavailableSnapshot(reason: "apple_smc_unavailable")
        }
    }

    func restoreSystemAuto() throws {
        let smc = try SMCConnection()
        try smc.writeKey("FS!", bytes: SMCValueCodec.encodeUInt16(0))
    }

    func setTargetRPM(_ rpm: Int) throws {
        guard rpm > 0 else { throw SMCClientError.invalidRPM }
        let smc = try SMCConnection()
        try smc.writeKey("FS!", bytes: SMCValueCodec.encodeUInt16(1))
        try smc.writeKey("F0Tg", bytes: SMCValueCodec.encodeFpe2(rpm))
    }

    private func unavailableSnapshot(reason: String) -> String {
        "temperature=nil currentRPM=nil minRPM=nil maxRPM=nil control=false reason=\(reason)"
    }

    private static let temperatureKeys = [
        "Tp09", "Tp0T", "Tp01", "Ts0P", "TC0P", "TC0E", "TC0F", "TC0D", "TC0H"
    ]
}

enum SMCClientError: Error {
    case invalidRPM
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case keyReadFailed(String)
    case keyWriteFailed(String)
}

private final class SMCConnection {
    private let connection: io_connect_t

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
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
        case "fpe2":
            return SMCValueCodec.decodeFpe2(value.bytes)
        case "ui16":
            guard value.bytes.count >= 2 else { return nil }
            return Int(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
        default:
            return nil
        }
    }

    func writeKey(_ key: String, bytes: [UInt8]) throws {
        var input = SMCParamStruct()
        input.key = key.smcKeyCode
        input.data8 = SMCCommand.writeBytes.rawValue
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.keyInfo.dataType = 0
        input.setBytes(bytes)

        let output = try call(input)
        guard output.result == 0 else { throw SMCClientError.keyWriteFailed(key) }
    }

    private func readKey(_ key: String) throws -> SMCValue {
        var infoInput = SMCParamStruct()
        infoInput.key = key.smcKeyCode
        infoInput.data8 = SMCCommand.readKeyInfo.rawValue
        let infoOutput = try call(infoInput)
        guard infoOutput.result == 0 else { throw SMCClientError.keyReadFailed(key) }

        var readInput = SMCParamStruct()
        readInput.key = key.smcKeyCode
        readInput.keyInfo = infoOutput.keyInfo
        readInput.data8 = SMCCommand.readBytes.rawValue
        let readOutput = try call(readInput)
        guard readOutput.result == 0 else { throw SMCClientError.keyReadFailed(key) }

        let size = min(Int(infoOutput.keyInfo.dataSize), 32)
        return SMCValue(
            key: key,
            type: infoOutput.keyInfo.dataType.smcString,
            bytes: Array(readOutput.byteArray.prefix(size))
        )
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var mutableInput = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let inputSize = MemoryLayout<SMCParamStruct>.stride

        let result = withUnsafePointer(to: &mutableInput) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    SMCSelector.handleYPCEvent.rawValue,
                    inputPointer,
                    inputSize,
                    outputPointer,
                    &outputSize
                )
            }
        }

        guard result == KERN_SUCCESS else { throw SMCClientError.callFailed(result) }
        return output
    }

    private func decodeTemperature(_ value: SMCValue) -> Double? {
        switch value.type {
        case "sp78":
            return SMCValueCodec.decodeSp78(value.bytes)
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

private enum SMCSelector: UInt32 {
    case handleYPCEvent = 2
}

private enum SMCCommand: UInt8 {
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
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = SMCBytes()

    var byteArray: [UInt8] {
        withUnsafeBytes(of: bytes) { rawBuffer in
            Array(rawBuffer)
        }
    }

    mutating func setBytes(_ newBytes: [UInt8]) {
        withUnsafeMutableBytes(of: &bytes) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for index in 0..<min(newBytes.count, rawBuffer.count) {
                rawBuffer[index] = newBytes[index]
            }
        }
    }
}

private struct SMCBytes {
    var b00: UInt8 = 0
    var b01: UInt8 = 0
    var b02: UInt8 = 0
    var b03: UInt8 = 0
    var b04: UInt8 = 0
    var b05: UInt8 = 0
    var b06: UInt8 = 0
    var b07: UInt8 = 0
    var b08: UInt8 = 0
    var b09: UInt8 = 0
    var b10: UInt8 = 0
    var b11: UInt8 = 0
    var b12: UInt8 = 0
    var b13: UInt8 = 0
    var b14: UInt8 = 0
    var b15: UInt8 = 0
    var b16: UInt8 = 0
    var b17: UInt8 = 0
    var b18: UInt8 = 0
    var b19: UInt8 = 0
    var b20: UInt8 = 0
    var b21: UInt8 = 0
    var b22: UInt8 = 0
    var b23: UInt8 = 0
    var b24: UInt8 = 0
    var b25: UInt8 = 0
    var b26: UInt8 = 0
    var b27: UInt8 = 0
    var b28: UInt8 = 0
    var b29: UInt8 = 0
    var b30: UInt8 = 0
    var b31: UInt8 = 0
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
