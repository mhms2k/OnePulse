import Foundation

// MARK: - Byte reading

/// Sequential reader over a byte buffer with explicit endianness.
/// Reads past the end throw instead of crashing, so malformed packets from a
/// device can never take the app down.
struct ByteReader {
    enum ReadError: Error { case outOfBounds(needed: Int, remaining: Int) }

    let bytes: [UInt8]
    private(set) var offset: Int = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }
    init(_ data: Data) { self.bytes = [UInt8](data) }

    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { remaining <= 0 }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, remaining >= n else { throw ReadError.outOfBounds(needed: n, remaining: remaining) }
        defer { offset += n }
        return bytes[offset..<(offset + n)]
    }

    mutating func u8() throws -> UInt8 { try take(1).first! }

    mutating func u16LE() throws -> UInt16 {
        let s = try take(2); let a = Array(s)
        return UInt16(a[0]) | UInt16(a[1]) << 8
    }

    mutating func u16BE() throws -> UInt16 {
        let s = try take(2); let a = Array(s)
        return UInt16(a[0]) << 8 | UInt16(a[1])
    }

    mutating func u32LE() throws -> UInt32 {
        let a = Array(try take(4))
        return UInt32(a[0]) | UInt32(a[1]) << 8 | UInt32(a[2]) << 16 | UInt32(a[3]) << 24
    }

    mutating func u32BE() throws -> UInt32 {
        let a = Array(try take(4))
        return UInt32(a[0]) << 24 | UInt32(a[1]) << 16 | UInt32(a[2]) << 8 | UInt32(a[3])
    }

    mutating func i16LE() throws -> Int16 { Int16(bitPattern: try u16LE()) }
    mutating func i32LE() throws -> Int32 { Int32(bitPattern: try u32LE()) }

    mutating func bytes(_ n: Int) throws -> [UInt8] { Array(try take(n)) }
    mutating func skip(_ n: Int) throws { _ = try take(n) }
    mutating func rest() -> [UInt8] {
        defer { offset = bytes.count }
        return Array(bytes[min(offset, bytes.count)...])
    }
}

// MARK: - Byte writing

struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16BE(_ v: UInt16) { bytes.append(UInt8(v >> 8)); bytes.append(UInt8(v & 0xff)) }
    mutating func u16LE(_ v: UInt16) { bytes.append(UInt8(v & 0xff)); bytes.append(UInt8(v >> 8)) }
    mutating func u32BE(_ v: UInt32) {
        bytes.append(UInt8((v >> 24) & 0xff)); bytes.append(UInt8((v >> 16) & 0xff))
        bytes.append(UInt8((v >> 8) & 0xff)); bytes.append(UInt8(v & 0xff))
    }
    mutating func u32LE(_ v: UInt32) {
        bytes.append(UInt8(v & 0xff)); bytes.append(UInt8((v >> 8) & 0xff))
        bytes.append(UInt8((v >> 16) & 0xff)); bytes.append(UInt8((v >> 24) & 0xff))
    }
    mutating func i32BE(_ v: Int32) { u32BE(UInt32(bitPattern: v)) }
    mutating func append(_ b: [UInt8]) { bytes.append(contentsOf: b) }
}

// MARK: - Hex helpers

extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        let clean = hex.lowercased()
            .replacingOccurrences(of: "0x", with: "")
            .filter { !$0.isWhitespace && $0 != ":" }
        guard clean.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let b = UInt8(clean[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        self = out
    }
}

extension ArraySlice where Element == UInt8 {
    var hex: String { Array(self).hex }
}

extension Data {
    var hex: String { [UInt8](self).hex }
}

// MARK: - CRC32 (IEEE 802.3, same as java.util.zip.CRC32)

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes { crc = table[Int((crc ^ UInt32(b)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
