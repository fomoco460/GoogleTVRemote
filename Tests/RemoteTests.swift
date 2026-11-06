import XCTest
import Security
@testable import GoogleTVRemote

final class RemoteTests: XCTestCase {
    func testFragmentedAndCoalescedFrames() throws {
        let first = PB.blob(8, PB.int(1, 98765))
        let second = PB.blob(40, PB.int(1, 1))
        let wire = PB.varint(UInt64(first.count)) + first + PB.varint(UInt64(second.count)) + second
        for split in 0...wire.count {
            var buffer = FrameBuffer()
            let a = try buffer.append(Data(wire.prefix(split)))
            let b = try buffer.append(Data(wire.dropFirst(split)))
            XCTAssertEqual(a + b, [first, second])
        }
        var buffer = FrameBuffer(); var output: [Data] = []
        for byte in wire { output += try buffer.append(Data([byte])) }
        XCTAssertEqual(output, [first, second])
    }
    func testMultipleByteLengthAndBoundedFrames() throws {
        let payload = Data(repeating: 123, count: 300)
        var buffer = FrameBuffer()
        XCTAssertEqual(try buffer.append(Data([0xac])), [])
        XCTAssertEqual(try buffer.append(Data([0x02]) + payload), [payload])
        var oversized = FrameBuffer()
        XCTAssertThrowsError(try oversized.append(PB.varint(1_048_577)))
    }
    func testMalformedProtobufRejected() throws {
        XCTAssertThrowsError(try PB.fields(Data([0x0a, 0x05, 0x01])))
        XCTAssertThrowsError(try PB.fields(Data([0x08, 0x80])))
        XCTAssertThrowsError(try PB.fields(Data([0])))
        let data = PB.int(1, 615) + PB.string(2, "Hello 🌎")
        let fields = try PB.fields(data)
        XCTAssertEqual(fields.number(1), 615)
        XCTAssertEqual(fields.bytes(2), Data("Hello 🌎".utf8))
    }
    func testIdentityPersistsAndCanSign() throws {
        let first = try ClientIdentity.load(), second = try ClientIdentity.load()
        XCTAssertEqual(try DER.rsaNumbers(first.publicKey), try DER.rsaNumbers(second.publicKey))
        var certificate: SecCertificate?
        XCTAssertEqual(SecIdentityCopyCertificate(first.identity, &certificate), errSecSuccess)
        let cert = try XCTUnwrap(certificate)
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust), errSecSuccess)
        let trusted = try XCTUnwrap(trust)
        SecTrustSetAnchorCertificates(trusted, [cert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trusted, true)
        var error: CFError?
        XCTAssertTrue(SecTrustEvaluateWithError(trusted, &error), "\(String(describing: error))")
    }
}
