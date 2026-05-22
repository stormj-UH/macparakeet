import Foundation

struct MeetingEchoSuppressionDiagnostics: Sendable, Equatable {
    var processorName: String
    var loaded: Bool
    var micFrames: Int
    var processedFrames: Int
    var rawFallbackFrames: Int
    var fullReferenceFrames: Int
    var partialReferenceFrames: Int
    var missingReferenceFrames: Int
    var processingFailures: Int

    static func passthrough(loaded: Bool = true) -> MeetingEchoSuppressionDiagnostics {
        MeetingEchoSuppressionDiagnostics(
            processorName: "passthrough",
            loaded: loaded,
            micFrames: 0,
            processedFrames: 0,
            rawFallbackFrames: 0,
            fullReferenceFrames: 0,
            partialReferenceFrames: 0,
            missingReferenceFrames: 0,
            processingFailures: 0
        )
    }
}

protocol MeetingEchoSuppressing: AnyObject, Sendable {
    var name: String { get }
    var sampleRate: Int { get }
    var frameSize: Int { get }
    func reset()
    func processFrame(microphone: [Float], reference: [Float]) throws -> [Float]
}

protocol MicConditioning: AnyObject, Sendable {
    var diagnostics: MeetingEchoSuppressionDiagnostics { get }
    func condition(microphone: [Float], speaker: [Float], hasSpeakerReference: Bool) -> [Float]
    func reset()
}

extension MicConditioning {
    func condition(microphone: [Float], speaker: [Float]) -> [Float] {
        condition(microphone: microphone, speaker: speaker, hasSpeakerReference: !speaker.isEmpty)
    }
}

/// No-op pass-through. This is the call-safe baseline: MacParakeet keeps raw
/// mic capture and only enables model-backed cleanup when a local processor is
/// explicitly configured and loaded.
final class PassthroughMicConditioner: MicConditioning, @unchecked Sendable {
    private(set) var diagnostics = MeetingEchoSuppressionDiagnostics.passthrough()

    func condition(microphone: [Float], speaker: [Float], hasSpeakerReference: Bool) -> [Float] {
        microphone
    }

    func reset() {
        diagnostics = MeetingEchoSuppressionDiagnostics.passthrough()
    }
}

final class StreamingMeetingEchoSuppressor: MicConditioning, @unchecked Sendable {
    private let processor: any MeetingEchoSuppressing
    private(set) var diagnostics: MeetingEchoSuppressionDiagnostics

    init(processor: any MeetingEchoSuppressing) {
        self.processor = processor
        self.diagnostics = MeetingEchoSuppressionDiagnostics(
            processorName: processor.name,
            loaded: true,
            micFrames: 0,
            processedFrames: 0,
            rawFallbackFrames: 0,
            fullReferenceFrames: 0,
            partialReferenceFrames: 0,
            missingReferenceFrames: 0,
            processingFailures: 0
        )
    }

    func condition(microphone: [Float], speaker: [Float], hasSpeakerReference: Bool) -> [Float] {
        guard !microphone.isEmpty else { return [] }

        let frameSize = max(processor.frameSize, 1)
        var output: [Float] = []
        output.reserveCapacity(microphone.count)

        var cursor = 0
        while cursor + frameSize <= microphone.count {
            let micFrame = Array(microphone[cursor..<(cursor + frameSize)])
            let referenceFrame = makeReferenceFrame(
                speaker: speaker,
                start: cursor,
                count: frameSize,
                hasSpeakerReference: hasSpeakerReference
            )

            diagnostics.micFrames += 1
            switch referenceFrame.quality {
            case .full:
                diagnostics.fullReferenceFrames += 1
            case .partial:
                diagnostics.partialReferenceFrames += 1
            case .missing:
                diagnostics.missingReferenceFrames += 1
            }

            do {
                let processed = try processor.processFrame(
                    microphone: micFrame,
                    reference: referenceFrame.samples
                )
                if processed.count == frameSize {
                    output.append(contentsOf: processed)
                    diagnostics.processedFrames += 1
                } else {
                    output.append(contentsOf: micFrame)
                    diagnostics.rawFallbackFrames += 1
                    diagnostics.processingFailures += 1
                }
            } catch {
                output.append(contentsOf: micFrame)
                diagnostics.rawFallbackFrames += 1
                diagnostics.processingFailures += 1
            }

            cursor += frameSize
        }

        if cursor < microphone.count {
            output.append(contentsOf: microphone[cursor...])
            diagnostics.rawFallbackFrames += 1
        }

        return output
    }

    func reset() {
        processor.reset()
        diagnostics = MeetingEchoSuppressionDiagnostics(
            processorName: processor.name,
            loaded: true,
            micFrames: 0,
            processedFrames: 0,
            rawFallbackFrames: 0,
            fullReferenceFrames: 0,
            partialReferenceFrames: 0,
            missingReferenceFrames: 0,
            processingFailures: 0
        )
    }

    private enum ReferenceQuality {
        case full
        case partial
        case missing
    }

    private func makeReferenceFrame(
        speaker: [Float],
        start: Int,
        count: Int,
        hasSpeakerReference: Bool
    ) -> (samples: [Float], quality: ReferenceQuality) {
        guard hasSpeakerReference, !speaker.isEmpty, start < speaker.count else {
            return ([Float](repeating: 0, count: count), .missing)
        }

        if start + count <= speaker.count {
            return (Array(speaker[start..<(start + count)]), .full)
        }

        let available = speaker.count - start
        guard available > 0 else {
            return ([Float](repeating: 0, count: count), .missing)
        }

        var frame = [Float](repeating: 0, count: count)
        frame.replaceSubrange(0..<available, with: speaker[start..<speaker.count])
        return (frame, .partial)
    }
}
