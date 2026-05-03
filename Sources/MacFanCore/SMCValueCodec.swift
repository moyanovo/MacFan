import Foundation

public enum SMCValueCodec {
    public static func decodeSp78(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let integer = Int8(bitPattern: bytes[0])
        let fraction = Double(bytes[1]) / 256.0
        return Double(integer) + fraction
    }

    public static func decodeFpe2(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 2 else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Int((Double(raw) / 4.0).rounded())
    }

    public static func encodeFpe2(_ rpm: Int) -> [UInt8] {
        let clamped = max(0, min(rpm, Int(UInt16.max / 4)))
        let raw = UInt16(clamped * 4)
        return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
    }

    public static func encodeUInt16(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }
}
