import Foundation

@main
struct SecurityScanTestRunner {
    static func runScan(arguments: [String] = []) -> Int32 {
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/security_scan.sh"] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    static func main() throws {
        print("==> Running Security Scanner Integration Tests...")

        // 1. Clean run should succeed with exit code 0
        let cleanStatus = runScan()
        assert(cleanStatus == 0, "Security scan should succeed on clean codebase (got exit status \(cleanStatus))")

        // 2. Secret leak simulation: temporary unencrypted private key in Sources/
        let fm = FileManager.default
        let leakFile = URL(fileURLWithPath: "Sources/Core/dummy_test_leak.pem")
        let keyHeader = ["-----BEGIN", "RSA", "PRIVATE", "KEY-----"].joined(separator: " ")
        let dummyKey = "\(keyHeader)\nMIIEowIBAAKCAQEA0mockkey...\n-----END RSA PRIVATE KEY-----\n"
        try dummyKey.write(to: leakFile, atomically: true, encoding: .utf8)

        let leakedStatus = runScan()
        try? fm.removeItem(at: leakFile)
        assert(leakedStatus == 1, "Security scan must fail (exit 1) when private key is present (got \(leakedStatus))")

        // 3. Binary tampering simulation: corrupt Vendor checksum manifest
        let checksumURL = URL(fileURLWithPath: "Vendor/checksums.sha256")
        let originalChecksums = try String(contentsOf: checksumURL, encoding: .utf8)
        let corruptedChecksums = originalChecksums.replacingOccurrences(of: "5906f02d", with: "deadbeef")
        try corruptedChecksums.write(to: checksumURL, atomically: true, encoding: .utf8)

        let tamperedStatus = runScan(arguments: ["--strict"])
        try originalChecksums.write(to: checksumURL, atomically: true, encoding: .utf8)
        assert(tamperedStatus == 1, "Security scan must fail (exit 1) when checksum mismatch occurs (got \(tamperedStatus))")

        // 4. Verify restored state is clean again
        let restoredStatus = runScan()
        assert(restoredStatus == 0, "Restored state must pass security scan with exit status 0")

        print("All security scanner integration tests passed!")
    }
}
