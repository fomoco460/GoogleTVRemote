import Foundation

enum WireError: Error { case malformed, tooLarge }

// Small bounded protobuf codec: only the fields required by Remote Service v2.
enum PB {
    struct Field {
        let number: Int
        var integer: UInt64 = 0
        var bytes = Data()
    }
    static func varint(_ value: UInt64) -> Data {
        var n = value, out = Data()
        repeat {
            out.append(UInt8(n & 127) | (n > 127 ? 128 : 0))
            n >>= 7
        } while n > 0
        return out
    }
    static func read(_ data: [UInt8], _ index: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard index < data.count else { throw WireError.malformed }
            let b = data[index]; index += 1
            if shift == 63 && b > 1 { throw WireError.malformed }
            result |= UInt64(b & 127) << shift
            if b & 128 == 0 { return result }
        }
        throw WireError.malformed
    }
    static func int(_ field: Int, _ value: UInt64) -> Data {
        varint(UInt64(field << 3)) + varint(value)
    }
    static func blob(_ field: Int, _ value: Data) -> Data {
        varint(UInt64(field << 3 | 2)) + varint(UInt64(value.count)) + value
    }
    static func string(_ field: Int, _ value: String) -> Data { blob(field, Data(value.utf8)) }
    static func fields(_ data: Data) throws -> [Field] {
        let bytes = Array(data); var i = 0; var out: [Field] = []
        while i < bytes.count {
            let key = try read(bytes, &i)
            guard key >> 3 > 0 else { throw WireError.malformed }
            var field = Field(number: Int(key >> 3))
            switch key & 7 {
            case 0: field.integer = try read(bytes, &i)
            case 2:
                let length = try read(bytes, &i)
                guard length <= UInt64(bytes.count - i) else { throw WireError.malformed }
                field.bytes = Data(bytes[i..<i + Int(length)]); i += Int(length)
            case 1, 5:
                let length = key & 7 == 1 ? 8 : 4
                guard i + length <= bytes.count else { throw WireError.malformed }
                i += length
            default: throw WireError.malformed
            }
            out.append(field)
        }
        return out
    }
}

extension Array where Element == PB.Field {
    func number(_ n: Int) -> UInt64 { first { $0.number == n }?.integer ?? 0 }
    func bytes(_ n: Int) -> Data? { first { $0.number == n }?.bytes }
}

struct FrameBuffer {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while !buffer.isEmpty {
            let bytes = Array(buffer.prefix(5))
            guard let last = bytes.firstIndex(where: { $0 & 128 == 0 }) else {
                if buffer.count >= 5 { throw WireError.tooLarge }
                break
            }
            var i = 0
            let length = try PB.read(bytes, &i)
            guard length <= 1_048_576 else { throw WireError.tooLarge }
            let prefix = last + 1
            guard buffer.count >= prefix + Int(length) else { break }
            frames.append(Data(buffer.dropFirst(prefix).prefix(Int(length))))
            buffer = Data(buffer.dropFirst(prefix + Int(length)))
        }
        return frames
    }
}
