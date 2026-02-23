//
//  CLIEndToEndTests.swift
//  OrbitalCLITests
//
//  End-to-end test that runs the orbital-play binary as a subprocess,
//  renders a pattern to an AIFF file, and verifies nonzero audio output.
//

import Testing
import Foundation
import AVFAudio

@Suite("CLI End-to-End", .serialized)
struct CLIEndToEndTests {

    /// Locate the orbital-play binary next to the test bundle in BUILT_PRODUCTS_DIR.
    private func binaryURL() throws -> URL {
        // The test bundle and the CLI binary are both in BUILT_PRODUCTS_DIR.
        // Bundle.main for an xctest is the .xctest bundle itself.
        let testBundle = Bundle(for: BundleLocator.self)
        let builtProductsDir = testBundle.bundleURL.deletingLastPathComponent()
        let binaryURL = builtProductsDir.appendingPathComponent("orbital-play")
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw CLITestError.binaryNotFound(binaryURL.path)
        }
        return binaryURL
    }

    /// Locate the project's Resources/ directory (contains presets/, samples/).
    /// The CLI needs this for preset and sample file lookups.
    private func resourcesDir() throws -> URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        // sourceFile is .../Orbital/OrbitalCLITests/CLIEndToEndTests.swift
        let projectRoot = sourceFile
            .deletingLastPathComponent()  // OrbitalCLITests/
            .deletingLastPathComponent()  // Orbital/
        let resourcesURL = projectRoot.appendingPathComponent("Resources")
        guard FileManager.default.fileExists(atPath: resourcesURL.path) else {
            throw CLITestError.resourcesNotFound(resourcesURL.path)
        }
        return resourcesURL
    }

    /// Locate a frozen pattern fixture in OrbitalCLITests/Fixtures/.
    private func fixturePatternPath(_ filename: String) throws -> String {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let fixturesDir = sourceFile.deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let url = fixturesDir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLITestError.fixtureNotFound(url.path)
        }
        return url.path
    }

    @Test("orbital-play renders nonzero AIFF from table_aurora pattern")
    func rendersNonzeroAIFF() async throws {
        let binary = try binaryURL()
        let resources = try resourcesDir()
        let patternPath = try fixturePatternPath("table_aurora_frozen.json")

        let outputPath = NSTemporaryDirectory() + "orbital_cli_test_\(UUID().uuidString).aiff"
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        // Run the CLI
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            patternPath,
            "--resources", resources.path,
            "--duration", "3",
            "--output", outputPath
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        #expect(process.terminationStatus == 0,
                "orbital-play should exit with status 0, got \(process.terminationStatus). stderr: \(stderrString)")

        // Verify the output file exists
        #expect(FileManager.default.fileExists(atPath: outputPath),
                "Output AIFF file should exist at \(outputPath)")

        // Read the AIFF and check for nonzero audio
        let audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: outputPath))
        let frameCount = AVAudioFrameCount(audioFile.length)
        #expect(frameCount > 0, "AIFF should have frames, got \(frameCount)")

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: min(frameCount, 441_000) // read up to ~10s at 44.1kHz
        ) else {
            Issue.record("Failed to create PCM buffer")
            return
        }
        try audioFile.read(into: buffer)

        // Scan for peak amplitude
        var peakAmplitude: Float = 0
        if let channelData = buffer.floatChannelData {
            let framesToScan = Int(buffer.frameLength)
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<framesToScan {
                    let sample = abs(channelData[channel][frame])
                    if sample > peakAmplitude {
                        peakAmplitude = sample
                    }
                }
            }
        }

        #expect(peakAmplitude > 0.001,
                "AIFF should contain nonzero audio; peak amplitude was \(peakAmplitude)")
    }
}

// Dummy class used to locate the test bundle via Bundle(for:)
private class BundleLocator {}

private enum CLITestError: Error, CustomStringConvertible {
    case binaryNotFound(String)
    case resourcesNotFound(String)
    case fixtureNotFound(String)

    var description: String {
        switch self {
        case .binaryNotFound(let path):
            return "orbital-play binary not found at \(path)"
        case .resourcesNotFound(let path):
            return "Resources directory not found at \(path)"
        case .fixtureNotFound(let path):
            return "Fixture not found at \(path)"
        }
    }
}
