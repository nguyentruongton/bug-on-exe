import Foundation
import zlib

public enum ExtractorError: Error, Equatable {
    case fileUnreadable(String)
    case notAFlashExecutable
}

public struct SwfPayload: Equatable {
    public let data: Data
    public let signature: String // "FWS", "CWS", or "ZWS"
    public let version: UInt8
    public let uncompressedLength: UInt32
}

public enum ExeSwfExtractor {
    private static let projectorFooterMagic: UInt32 = 0xFA123456

    public static func extract(from fileURL: URL) throws -> SwfPayload {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw ExtractorError.fileUnreadable(error.localizedDescription)
        }
        return try extract(from: data)
    }

    public static func extract(from data: Data) throws -> SwfPayload {
        guard data.count >= 12 else {
            throw ExtractorError.notAFlashExecutable
        }

        // 1. Direct SWF file check at offset 0
        if let direct = validateSwfCandidate(data, verifyFullDecompression: true) {
            return direct
        }

        // 2. Fast-path: check last 8 bytes for 0xFA123456 footer
        if data.count >= 20 {
            let footerOffset = data.count - 8
            let magic = readUInt32LE(data, at: footerOffset)
            let swfLen = Int(readUInt32LE(data, at: footerOffset + 4))
            if magic == projectorFooterMagic, swfLen >= 12, swfLen <= footerOffset {
                let start = footerOffset - swfLen
                let slice = data.subdata(in: start..<footerOffset)
                if let payload = validateSwfCandidate(slice, verifyFullDecompression: true) {
                    return payload
                }
            }
        }

        // 3. Fallback scan: look for internal projector footer (0xFA123456) followed by length
        // (Handles .exe files with trailing Authenticode signature or overlay bytes)
        let footerMagicBytes = Data([0x56, 0x34, 0x12, 0xFA])
        var searchRange = 12..<(data.count - 4)
        while let matchRange = data.range(of: footerMagicBytes, options: [], in: searchRange) {
            let footerPos = matchRange.lowerBound
            if footerPos + 8 <= data.count {
                let swfLen = Int(readUInt32LE(data, at: footerPos + 4))
                if swfLen >= 12, swfLen <= footerPos {
                    let start = footerPos - swfLen
                    let slice = data.subdata(in: start..<footerPos)
                    if let payload = validateSwfCandidate(slice, verifyFullDecompression: true) {
                        return payload
                    }
                }
            }
            let nextStart = matchRange.lowerBound + 1
            if nextStart >= data.count - 4 { break }
            searchRange = nextStart..<(data.count - 4)
        }

        // 4. Fallback scan for raw FWS/CWS header without footer
        for sigBytes in [Data([0x43, 0x57, 0x53]), Data([0x46, 0x57, 0x53])] {
            var sigSearch = 1..<(data.count - 12)
            while let sigMatch = data.range(of: sigBytes, options: [], in: sigSearch) {
                let pos = sigMatch.lowerBound
                if pos + 12 <= data.count {
                    let ver = data[pos + 3]
                    let uncompLen = Int(readUInt32LE(data, at: pos + 4))
                    if (1...45).contains(ver), uncompLen >= 12, uncompLen <= 100_000_000 {
                        if sigBytes[0] == 0x46, pos + uncompLen <= data.count {
                            let slice = data.subdata(in: pos..<(pos + uncompLen))
                            if let payload = validateSwfCandidate(slice, verifyFullDecompression: true) {
                                return payload
                            }
                        } else if sigBytes[0] == 0x43 {
                            let slice = data.subdata(in: pos..<data.count)
                            if let payload = validateSwfCandidate(slice, verifyFullDecompression: true) {
                                return payload
                            }
                        }
                    }
                }
                let nextPos = pos + 1
                if nextPos >= data.count - 12 { break }
                sigSearch = nextPos..<(data.count - 12)
            }
        }

        throw ExtractorError.notAFlashExecutable
    }

    private static func validateSwfCandidate(_ slice: Data, verifyFullDecompression: Bool) -> SwfPayload? {
        guard slice.count >= 12 else { return nil }
        let b0 = slice[slice.startIndex]
        let b1 = slice[slice.startIndex + 1]
        let b2 = slice[slice.startIndex + 2]
        let version = slice[slice.startIndex + 3]

        guard b1 == 0x57, b2 == 0x53, (1...45).contains(version) else {
            return nil
        }

        let uncompressedLength = readUInt32LE(slice, at: slice.startIndex + 4)
        guard uncompressedLength >= 12, uncompressedLength <= 100_000_000 else {
            return nil
        }

        switch b0 {
        case 0x46: // "FWS" uncompressed
            guard slice.count == Int(uncompressedLength) else { return nil }
            return SwfPayload(
                data: slice,
                signature: "FWS",
                version: version,
                uncompressedLength: uncompressedLength
            )
        case 0x43: // "CWS" zlib compressed
            let zHeader0 = slice[slice.startIndex + 8]
            let zHeader1 = slice[slice.startIndex + 9]
            // RFC 1950 zlib header check: CM == 8 (deflate) and (CMF*256 + FLG) % 31 == 0
            guard (zHeader0 & 0x0F) == 8,
                  (UInt16(zHeader0) * 256 + UInt16(zHeader1)) % 31 == 0 else {
                return nil
            }
            if verifyFullDecompression {
                let expectedDecompressedCount = Int(uncompressedLength) - 8
                guard expectedDecompressedCount > 0 else { return nil }
                var dest = Data(count: expectedDecompressedCount)
                var destLen = uLongf(expectedDecompressedCount)
                let compressedSlice = slice.subdata(in: (slice.startIndex + 8)..<slice.endIndex)
                let status = dest.withUnsafeMutableBytes { destPtr -> Int32 in
                    compressedSlice.withUnsafeBytes { srcPtr -> Int32 in
                        guard let dBase = destPtr.bindMemory(to: Bytef.self).baseAddress,
                              let sBase = srcPtr.bindMemory(to: Bytef.self).baseAddress else {
                            return Z_DATA_ERROR
                        }
                        return uncompress(dBase, &destLen, sBase, uLong(compressedSlice.count))
                    }
                }
                guard status == Z_OK, Int(destLen) == expectedDecompressedCount else {
                    return nil
                }
            }
            return SwfPayload(
                data: slice,
                signature: "CWS",
                version: version,
                uncompressedLength: uncompressedLength
            )
        case 0x5A: // "ZWS" LZMA compressed
            guard slice.count > 16 else { return nil }
            return SwfPayload(
                data: slice,
                signature: "ZWS",
                version: version,
                uncompressedLength: uncompressedLength
            )
        default:
            return nil
        }
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
