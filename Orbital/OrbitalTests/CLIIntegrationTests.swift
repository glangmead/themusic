//
//  CLIIntegrationTests.swift
//  OrbitalTests
//
//  Integration test that exercises the same audio pipeline as the CLI tool:
//  compile a pattern, run the engine, capture audio, and verify nonzero output.
//

import Testing
import Foundation
import AVFAudio
@testable import Orbital

@Suite("CLI Audio Pipeline", .serialized)
struct CLIAudioPipelineTests {

    /// Load a frozen pattern fixture from OrbitalTests/Fixtures/.
    private func loadFixturePattern(_ filename: String, filePath: String = #filePath) throws -> PatternSyntax {
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let url = testsDir.appendingPathComponent("Fixtures").appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError.fileNotFound("Fixture not found: \(url.path)")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PatternSyntax.self, from: data)
    }

    private enum FixtureError: Error { case fileNotFound(String) }

    @Test("Table Aurora pattern produces nonzero audio output")
    func tableAuroraProducesNonzeroAudio() async throws {
        // 1. Load the frozen pattern fixture (decoupled from live Resources/)
        let pattern = try loadFixturePattern("table_aurora_frozen.json")

        // 2. Create a headless engine (no spatial audio, matching CLI behavior)
        let engine = SpatialAudioEngine(spatialEnabled: false)
        try engine.start()

        // 3. Compile the pattern — this attaches source nodes to the engine
        let (musicPattern, trackInfos) = try await pattern.compile(
            engine: engine
        )
        #expect(trackInfos.count > 0, "Pattern should have at least one track")

        // 4. Restart engine so newly-connected source nodes are pulled.
        //    (On macOS, nodes attached after start() aren't automatically pulled.)
        engine.audioEngine.stop()
        try engine.audioEngine.start()

        // 5. Install a tap on the main mixer to capture audio
        let mainMixer = engine.audioEngine.mainMixerNode
        let mixerFormat = mainMixer.outputFormat(forBus: 0)

        let requiredBuffers = 50  // ~0.5s of audio at 4096-sample buffers
        nonisolated(unsafe) var peakAmplitude: Float = 0
        nonisolated(unsafe) var buffersReceived = 0
        nonisolated(unsafe) var tapContinuation: CheckedContinuation<Void, Never>?

        mainMixer.installTap(onBus: 0, bufferSize: 4096, format: mixerFormat) { buffer, _ in
            // Scan for peak amplitude in this buffer
            if let channelData = buffer.floatChannelData {
                let frameLength = Int(buffer.frameLength)
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<frameLength {
                        let sample = abs(channelData[channel][frame])
                        if sample > peakAmplitude {
                            peakAmplitude = sample
                        }
                    }
                }
            }
            buffersReceived += 1
            if buffersReceived >= requiredBuffers {
                tapContinuation?.resume()
                tapContinuation = nil
            }
        }

        // 6. Start pattern playback
        let playTask = Task {
            await musicPattern.play()
        }

        // 7. Wait for enough audio to be captured (up to 10 seconds)
        let capturedEnough = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    tapContinuation = continuation
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return false
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }

        // 8. Clean up
        playTask.cancel()
        mainMixer.removeTap(onBus: 0)
        engine.audioEngine.stop()

        // 9. Verify results
        #expect(capturedEnough,
                "Should have received \(requiredBuffers) audio buffers within timeout")
        #expect(peakAmplitude > 0.001,
                "Audio output should be nonzero; peak amplitude was \(peakAmplitude)")
    }
}
