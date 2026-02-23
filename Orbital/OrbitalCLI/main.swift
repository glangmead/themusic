//
//  main.swift
//  OrbitalCLI
//
//  A command-line tool that plays Orbital patterns through speakers
//  or renders them to AIFF files.
//
//  DESIGN NOTES — why this file is structured the way it is:
//
//  1. Why "main.swift" instead of @main on the struct?
//     Swift treats a file named main.swift as the program entry point via
//     top-level code. You cannot also use @main in the same module — the
//     compiler rejects it with "'main' attribute cannot be used in a module
//     that contains top-level code". Renaming the file (to use @main instead)
//     would work in theory, but Xcode's project navigator and pbxproj don't
//     reliably stay in sync when renaming files in an open workspace.
//     So we keep main.swift and use top-level code as the entry point.
//
//  2. Why the @available annotation on the struct?
//     ArgumentParser checks at runtime (in debug builds) that async commands
//     carry an availability annotation for the concurrency-capable OS versions.
//     Without it, the library calls fatalError() before run() is ever invoked.
//
//  3. Why the runAsync() generic helper instead of calling orbital.run() directly?
//     OrbitalPlay conforms to AsyncParsableCommand, whose run() is
//     `mutating func run() async throws`. But ParsableCommand (the parent
//     protocol) also declares `mutating func run() throws` (sync). When you
//     call orbital.run() from top-level code, Swift resolves the overload to
//     the *sync* version — which hits the default implementation that just
//     prints help text. This happens regardless of `await`, existential
//     wrappers (`any AsyncParsableCommand`), or direct casts.
//     The fix: a generic function `runAsync<C: AsyncParsableCommand>` whose
//     constraint forces the compiler to resolve run() through the
//     AsyncParsableCommand protocol witness table, dispatching to our async
//     override.
//

import AVFAudio
import Foundation
import ArgumentParser

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct OrbitalPlay: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "orbital-play",
        abstract: "Play an Orbital pattern through speakers or render to an audio file."
    )

    @Argument(help: "Path to a pattern JSON file.")
    var pattern: String

    @Option(name: .long, help: "Root resources directory (contains presets/, samples/, etc.).")
    var resources: String

    @Option(name: .long, help: "Duration in seconds. Required for file output; optional for speaker playback (Ctrl-C to stop).")
    var duration: Double?

    @Option(name: .long, help: "Output file path (.aiff). If provided, renders offline instead of playing through speakers.")
    var output: String?

    @Flag(name: .long, help: "Disable spatial audio (AVAudioEnvironmentNode). By default spatial audio is enabled.")
    var noSpatial: Bool = false

    func validate() throws {
        if output != nil && duration == nil {
            // Default to 10 seconds when writing to a file
        }
    }

    mutating func run() async throws {
        let patternURL = URL(fileURLWithPath: pattern)
        let resourcesURL = URL(fileURLWithPath: resources)

        // Decode pattern JSON
        let patternData = try Data(contentsOf: patternURL)
        let patternSpec = try JSONDecoder().decode(PatternSyntax.self, from: patternData)

        let spatialEnabled = !noSpatial

        if let outputPath = output {
            // Offline render to AIFF
            let renderDuration = duration ?? 10.0
            try await renderToFile(
                patternSpec: patternSpec,
                resourcesURL: resourcesURL,
                duration: renderDuration,
                outputPath: outputPath,
                spatialEnabled: spatialEnabled
            )
        } else {
            // Play through speakers
            try await playThroughSpeakers(
                patternSpec: patternSpec,
                resourcesURL: resourcesURL,
                duration: duration,
                spatialEnabled: spatialEnabled
            )
        }
    }

    // MARK: - Speaker Playback

    private func playThroughSpeakers(
        patternSpec: PatternSyntax,
        resourcesURL: URL,
        duration: Double?,
        spatialEnabled: Bool
    ) async throws {
        let engine = SpatialAudioEngine(spatialEnabled: spatialEnabled)
        try engine.start()

        let (musicPattern, trackInfos) = try await patternSpec.compile(
            engine: engine,
            resourceBaseURL: resourcesURL
        )

        // Nodes were attached after engine.start(). On macOS CLI, the engine
        // may not automatically pull from newly-connected source nodes.
        // Stop and restart to force the render graph to reconfigure.
        engine.audioEngine.stop()
        try engine.audioEngine.start()

        print("Playing \(trackInfos.count) track(s)...")
        if let duration {
            print("Will stop after \(duration) seconds.")
        } else {
            print("Press Ctrl-C to stop.")
        }

        // Handle SIGINT for clean shutdown
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            print("\nStopping...")
            engine.fadeOutAndStop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Foundation.exit(0)
            }
        }
        signalSource.resume()

        // Start playback in a task
        let playTask = Task {
            await musicPattern.play()
        }

        if let duration {
            try await Task.sleep(for: .seconds(duration))
            playTask.cancel()
            engine.fadeOutAndStop()
            try await Task.sleep(for: .seconds(0.1))
        } else {
            // Run forever until Ctrl-C
            await playTask.value
        }
    }

    // MARK: - Offline Rendering

    private func renderToFile(
        patternSpec: PatternSyntax,
        resourcesURL: URL,
        duration: Double,
        outputPath: String,
        spatialEnabled: Bool
    ) async throws {
        // Use real-time engine with a tap to capture audio, since offline
        // manual rendering mode has ordering constraints that conflict with
        // the Orbital compile flow (nodes must be attached after enabling
        // manual mode, but compile needs engine format info).
        let engine = SpatialAudioEngine(spatialEnabled: spatialEnabled)
        try engine.start()

        let (musicPattern, trackInfos) = try await patternSpec.compile(
            engine: engine,
            resourceBaseURL: resourcesURL
        )

        // Restart engine so newly-connected source nodes are pulled
        engine.audioEngine.stop()
        try engine.audioEngine.start()

        print("Rendering \(trackInfos.count) track(s), \(duration)s to \(outputPath)...")

        let sampleRate = engine.sampleRate

        // When spatial is enabled, audio flows: sources → envNode → outputNode.
        // Tap the envNode to capture the spatialized mix. When spatial is off,
        // audio flows: sources → mainMixerNode, so tap the main mixer.
        // The engine installs a visualizer tap on envNode during start(); remove
        // it first since AVAudioNode only allows one tap per bus.
        let tapNode: AVAudioNode = spatialEnabled ? engine.envNode : engine.audioEngine.mainMixerNode
        if spatialEnabled {
            engine.envNode.removeTap(onBus: 0)
        }
        let tapFormat = tapNode.outputFormat(forBus: 0)

        // Create the output file
        let outputURL = URL(fileURLWithPath: outputPath)
        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: tapFormat.settings
        )

        // Install a tap to capture audio to file
        var framesWritten: AVAudioFrameCount = 0
        let totalFrames = AVAudioFrameCount(duration * sampleRate)

        tapNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            guard framesWritten < totalFrames else { return }
            do {
                try audioFile.write(from: buffer)
                framesWritten += buffer.frameLength

                // Progress indicator every ~1 second of audio
                let secondsWritten = Double(framesWritten) / sampleRate
                let prevSeconds = Double(framesWritten - buffer.frameLength) / sampleRate
                if Int(secondsWritten) > Int(prevSeconds) {
                    print("  \(Int(secondsWritten))s / \(Int(duration))s")
                }
            } catch {
                fputs("Error writing audio: \(error)\n", stderr)
            }
        }

        // Start pattern playback
        let playTask = Task {
            await musicPattern.play()
        }

        // Wait for the duration
        try await Task.sleep(for: .seconds(duration))

        playTask.cancel()
        tapNode.removeTap(onBus: 0)
        engine.audioEngine.stop()

        print("Done. Wrote \(outputPath)")
    }
}

enum CLIError: Error, CustomStringConvertible {
    case renderFailed

    var description: String {
        switch self {
        case .renderFailed:
            return "Audio rendering failed"
        }
    }
}

// See design note (3) above: this generic constraint is the only way to make
// Swift resolve run() to the async version instead of the sync default.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
func runAsync<C: AsyncParsableCommand>(_ command: inout C) async throws {
    try await command.run()
}

// Top-level async entry point. See design notes (1) and (3) above.
do {
    var orbital = try OrbitalPlay.parse()
    try await runAsync(&orbital)
} catch {
    OrbitalPlay.exit(withError: error)
}
