import Foundation

/// Encodes commands into BLE-sized frames and reassembles incoming frames.
///
/// Wire format of every frame (big-endian header):
/// ```
/// 0xF5 | len:u16 | cmd1:u16 | chunkCount:u16 | chunkIndex:u16 (1-based) | cmd2:u16 | body[len]
/// ```
/// The body is `AES-CBC(chunk + CRC32LE(chunk))` for encrypted commands, or
/// `chunk + CRC32LE(chunk)` in plaintext for the two pairing commands.
final class CMFCodec {
    static let header: UInt8 = 0xF5
    static let headerLength = 11

    enum Inbound: Equatable {
        /// A full, verified message.
        case message(CMFCommand, [UInt8])
        /// A chunk of a multi-part message was stored; waiting for the rest.
        case partial(CMFCommand, received: Int, of: Int)
        /// A frame whose command codes we do not know (payload decrypted if possible).
        case unknown(cmd1: UInt16, cmd2: UInt16, payload: [UInt8])
        case error(String)
    }

    enum CodecError: Error, LocalizedError {
        case noSessionKey
        var errorDescription: String? { "Not authenticated with the watch yet" }
    }

    /// Current AES key (the pairing key or the per-connection session key).
    var key: [UInt8]?
    /// Negotiated ATT MTU (payload bytes + 3).
    var mtu: Int = 247

    private var buffers: [CMFCommand: (expected: Int, data: [UInt8])] = [:]

    init(key: [UInt8]? = nil, mtu: Int = 247) {
        self.key = key
        self.mtu = mtu
    }

    // MARK: Encoding

    func encode(_ command: CMFCommand, payload: [UInt8] = []) throws -> [[UInt8]] {
        let chunks: [[UInt8]]
        if command.isEncrypted {
            guard let key else { throw CodecError.noSessionKey }
            chunks = try encryptedChunks(payload, key: key)
        } else {
            chunks = plaintextChunks(payload)
        }

        return chunks.enumerated().map { index, chunk in
            var w = ByteWriter()
            w.u8(Self.header)
            w.u16BE(UInt16(chunk.count))
            w.u16BE(command.cmd1)
            w.u16BE(UInt16(chunks.count))
            w.u16BE(UInt16(index + 1))
            w.u16BE(command.cmd2)
            w.append(chunk)
            return w.bytes
        }
    }

    private func plaintextChunks(_ payload: [UInt8]) -> [[UInt8]] {
        let size = max(1, mtu - 20)
        return stride(from: 0, to: payload.count, by: size).map { start in
            let chunk = Array(payload[start..<min(start + size, payload.count)])
            var w = ByteWriter()
            w.append(chunk)
            w.u32LE(CRC32.checksum(chunk))
            return w.bytes
        }
    }

    private func encryptedChunks(_ payload: [UInt8], key: [UInt8]) throws -> [[UInt8]] {
        // An empty payload is sent as a single empty frame with no CRC.
        if payload.isEmpty { return [[]] }
        let maxEncrypted = ((mtu - Self.headerLength) / 16) * 16
        let maxPlain = max(1, maxEncrypted - 4 - 1) // room for CRC + at least one byte of padding
        return try stride(from: 0, to: payload.count, by: maxPlain).map { start in
            let chunk = Array(payload[start..<min(start + maxPlain, payload.count)])
            var w = ByteWriter()
            w.append(chunk)
            w.u32LE(CRC32.checksum(chunk))
            return try CMFCrypto.encrypt(w.bytes, key: key)
        }
    }

    // MARK: Decoding

    func decode(_ frame: [UInt8]) -> Inbound {
        var r = ByteReader(frame)
        do {
            guard try r.u8() == Self.header else { return .error("Bad header byte in \(frame.prefix(4).hex)") }
            let length = Int(try r.u16BE())
            let cmd1 = try r.u16BE()
            let chunkCount = Int(try r.u16BE())
            let chunkIndex = Int(try r.u16BE())
            let cmd2 = try r.u16BE()
            let command = CMFCommand.from(cmd1, cmd2)

            var payload: [UInt8] = []
            if length > 0 {
                if command == nil || command!.isEncrypted {
                    guard let key else { return .error("Encrypted frame received before authentication") }
                    let body = try r.bytes(min(length, r.remaining))
                    let plain = try CMFCrypto.decrypt(body, key: key)
                    guard plain.count >= 4 else { return .error("Decrypted frame too short") }
                    payload = Array(plain.dropLast(4))
                    var crcReader = ByteReader(Array(plain.suffix(4)))
                    let expected = try crcReader.u32LE()
                    guard CRC32.checksum(payload) == expected else {
                        if let command { buffers[command] = nil }
                        return .error("CRC mismatch for \(command?.name ?? String(format: "%04x/%04x", cmd1, cmd2))")
                    }
                } else {
                    // Plaintext pairing frames: the body has no trailing CRC.
                    payload = r.rest()
                }
            }

            guard let command else { return .unknown(cmd1: cmd1, cmd2: cmd2, payload: payload) }

            if chunkCount <= 1 { return .message(command, payload) }

            var buffer = buffers[command] ?? (expected: 1, data: [])
            if chunkIndex != buffer.expected {
                guard chunkIndex == 1 else { return .error("Out-of-order chunk \(chunkIndex) for \(command)") }
                buffer = (expected: 1, data: [])
            }
            buffer.data.append(contentsOf: payload)
            buffer.expected = chunkIndex + 1

            if chunkIndex < chunkCount {
                buffers[command] = buffer
                return .partial(command, received: chunkIndex, of: chunkCount)
            }
            buffers[command] = nil
            return .message(command, buffer.data)
        } catch {
            return .error("Malformed frame \(frame.prefix(16).hex): \(error)")
        }
    }

    func reset() { buffers.removeAll() }
}

// MARK: - Pairing / session key derivation

/// Pure functions for the CMF authentication handshake.
///
/// 1. The app writes `AT GETSECRET` to the shell characteristic; the watch answers
///    `GETSECRET:<32 hex chars>,OK` (the app secret).
/// 2. The app sends `random1 + SHA256(random1 + secret)` (AUTH_PAIR_REQUEST, plaintext).
/// 3. The watch replies `random2 + SHA256(random2 + secret)` (AUTH_PAIR_REPLY).
/// 4. Pairing key = `SHA256(random1 + random2 + secret)[0..<16]` — stored for reconnects.
/// 5. Every connection: phone name → watch MAC → nonce; session key = `SHA256(nonce + pairingKey)[0..<16]`.
enum CMFAuth {
    static func parseSecret(shellResponse: String) -> [UInt8]? {
        let s = shellResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("GETSECRET:"), s.hasSuffix(",OK") else { return nil }
        let hexPart = s.dropFirst("GETSECRET:".count).prefix(32)
        guard let bytes = [UInt8](hex: String(hexPart)), bytes.count == 16 else { return nil }
        return bytes
    }

    static func pairRequest(random1: [UInt8], secret: [UInt8]) -> [UInt8] {
        random1 + CMFCrypto.sha256(random1, secret)
    }

    /// Verifies the watch's reply and returns the long-term pairing key.
    static func pairingKey(reply: [UInt8], random1: [UInt8], secret: [UInt8]) -> [UInt8]? {
        guard reply.count >= 48 else { return nil }
        let random2 = Array(reply[0..<16])
        let signed = Array(reply[16..<48])
        guard signed == CMFCrypto.sha256(random2, secret) else { return nil }
        return Array(CMFCrypto.sha256(random1, random2, secret).prefix(16))
    }

    static func sessionKey(nonce: [UInt8], pairingKey: [UInt8]) -> [UInt8] {
        Array(CMFCrypto.sha256(nonce, pairingKey).prefix(16))
    }

    static func phoneNamePayload(_ name: String) -> [UInt8] {
        [0xA5] + Array(name.utf8)
    }

    static func timePayload(date: Date, timeZone: TimeZone = .current) -> [UInt8] {
        var w = ByteWriter()
        w.u32BE(UInt32(truncatingIfNeeded: Int(date.timeIntervalSince1970)))
        w.i32BE(Int32(timeZone.secondsFromGMT(for: date) * 1000)) // offset in milliseconds
        return w.bytes
    }
}
