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

        if let outputPath = output {
            // Offline render to AIFF
            let renderDuration = duration ?? 10.0
            try await renderToFile(
                patternSpec: patternSpec,
                resourcesURL: resourcesURL,
                duration: renderDuration,
                outputPath: outputPath
            )
        } else {
            // Play through speakers
            try await playThroughSpeakers(
                patternSpec: patternSpec,
                resourcesURL: resourcesURL,
                duration: duration
            )
        }
    }

    // MARK: - Speaker Playback

    private func playThroughSpeakers(
        patternSpec: PatternSyntax,
        resourcesURL: URL,
        duration: Double?
    ) async throws {
        let engine = SpatialAudioEngine()
        try engine.start()

        let (musicPattern, trackInfos) = try await patternSpec.compile(
            engine: engine,
            resourceBaseURL: resourcesURL
        )

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
            // Give the fade a moment, then exit
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
        outputPath: String
    ) async throws {
        // Set up the engine in normal mode first to build the audio graph
        let engine = SpatialAudioEngine()

        let (musicPattern, trackInfos) = try await patternSpec.compile(
            engine: engine,
            resourceBaseURL: resourcesURL
        )

        print("Rendering \(trackInfos.count) track(s), \(duration)s to \(outputPath)...")

        // Configure for manual (offline) rendering
        let sampleRate = engine.audioEngine.outputNode.inputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let totalFrames = AVAudioFrameCount(duration * sampleRate)

        // Stop the engine if it was running, then enable manual rendering
        engine.audioEngine.stop()
        try engine.audioEngine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 4096
        )

        // Start the engine in offline mode
        try engine.audioEngine.start()

        // Start pattern playback in background
        let playTask = Task {
            await musicPattern.play()
        }

        // Create the output file
        let outputURL = URL(fileURLWithPath: outputPath)
        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )

        // Render in chunks
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var framesRemaining = totalFrames
        var framesRendered: AVAudioFrameCount = 0

        while framesRemaining > 0 {
            let framesToRender = min(buffer.frameCapacity, framesRemaining)
            let status = try engine.audioEngine.renderOffline(framesToRender, to: buffer)

            switch status {
            case .success:
                try audioFile.write(from: buffer)
                framesRendered += buffer.frameLength
                framesRemaining -= buffer.frameLength
            case .insufficientDataFromInputNode:
                // Input node hasn't produced data yet; continue
                continue
            case .cannotDoInCurrentContext:
                // Try again
                try await Task.sleep(for: .milliseconds(1))
                continue
            case .error:
                throw CLIError.renderFailed
            @unknown default:
                throw CLIError.renderFailed
            }

            // Progress indicator every ~1 second of audio
            let secondsRendered = Double(framesRendered) / sampleRate
            if Int(secondsRendered) > Int(Double(framesRendered - buffer.frameLength) / sampleRate) {
                print("  \(Int(secondsRendered))s / \(Int(duration))s")
            }
        }

        playTask.cancel()
        engine.audioEngine.stop()
        engine.audioEngine.disableManualRenderingMode()

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
