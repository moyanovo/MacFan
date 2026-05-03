import Testing
@testable import MacFanCore

@Suite
struct SMCValueCodecTests {
    @Test func decodesSp78Temperature() {
        #expect(SMCValueCodec.decodeSp78([52, 0]) == 52.0)
        #expect(SMCValueCodec.decodeSp78([52, 128]) == 52.5)
    }

    @Test func decodesFpe2RPM() {
        #expect(SMCValueCodec.decodeFpe2([0x12, 0xC0]) == 1200)
        #expect(SMCValueCodec.decodeFpe2([0x70, 0x80]) == 7200)
    }

    @Test func encodesFpe2RPM() {
        #expect(SMCValueCodec.encodeFpe2(1200) == [0x12, 0xC0])
        #expect(SMCValueCodec.encodeFpe2(7200) == [0x70, 0x80])
    }

    @Test func encodesUInt16BigEndian() {
        #expect(SMCValueCodec.encodeUInt16(1) == [0x00, 0x01])
        #expect(SMCValueCodec.encodeUInt16(0) == [0x00, 0x00])
    }
}
