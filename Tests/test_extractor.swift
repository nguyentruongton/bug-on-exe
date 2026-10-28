import Foundation

func assertThrowsNotFlash(_ data: Data, _ message: String) {
    do {
        _ = try ExeSwfExtractor.extract(from: data)
        fatalError("Expected notAFlashExecutable for \(message)")
    } catch ExtractorError.notAFlashExecutable {
        // Expected
    } catch {
        fatalError("Unexpected error \(error) for \(message)")
    }
}

@main
struct ExtractorTestRunner {
    static func main() throws {
        // 1. Truncated / tiny data (< 8 bytes)
        assertThrowsNotFlash(Data([0x4D, 0x5A, 0x90]), "tiny 3-byte file")

        // 2. Corrupt footer with swfLength > fileSize
        var badFooter = Data(repeating: 0x00, count: 32)
        badFooter.append(contentsOf: [0x56, 0x34, 0x12, 0xFA, 0xFF, 0xFF, 0x00, 0x00])
        assertThrowsNotFlash(badFooter, "swfLength larger than file")

        // 3. False positive "CWS" in a normal binary without valid zlib payload
        var fakeExe = Data([0x4D, 0x5A, 0x90, 0x00])
        fakeExe.append(contentsOf: Array("CWS\u{09}xxxxNOT_ZLIB_DATA".utf8))
        assertThrowsNotFlash(fakeExe, "false positive CWS")

        // 4. Trailing bytes after 0xFA123456 footer (fallback scan on valid FWS)
        var fws = Data([0x46, 0x57, 0x53, 0x09]) // FWS v9
        let fwsLen: UInt32 = 20
        withUnsafeBytes(of: fwsLen.littleEndian) { fws.append(contentsOf: $0) }
        fws.append(Data(repeating: 0x00, count: 12)) // rect + frame rate + frame count + end tag
        var exeWithOverlay = Data([0x4D, 0x5A, 0x90, 0x00, 0x00, 0x00])
        exeWithOverlay.append(fws)
        exeWithOverlay.append(contentsOf: [0x56, 0x34, 0x12, 0xFA])
        withUnsafeBytes(of: fwsLen.littleEndian) { exeWithOverlay.append(contentsOf: $0) }
        exeWithOverlay.append(Data(repeating: 0xAB, count: 64)) // trailing overlay
        let overlayPayload = try ExeSwfExtractor.extract(from: exeWithOverlay)
        assert(overlayPayload.signature == "FWS" && overlayPayload.version == 9 && overlayPayload.data.count == 20)

        // 5. Real IC3 GS6 Flash Projector .exe file
        let realURL = URL(fileURLWithPath: "/Users/stark/Documents/IC3/GS6 Level 3/GS6_LV3_TESTING_01_(2526GM).exe")
        let realPayload = try ExeSwfExtractor.extract(from: realURL)
        assert(realPayload.signature == "CWS")
        assert(realPayload.version == 9)
        assert(realPayload.data.count == 1_208_512)
        assert(realPayload.uncompressedLength == 850_135)
        print("ALL EXTRACTOR TESTS PASSED")
    }
}
