import XCTest
@testable import MacParakeetCore

final class MeetingTranscriptNoiseFilterTests: XCTestCase {
    func testFinalizeDropsFillerOnlyMicrophoneRuns() {
        let finalized = MeetingTranscriptFinalizer.finalize(sourceTranscripts: [
            .init(
                source: .microphone,
                result: STTResult(
                    text: "Uh uh",
                    words: [
                        TimestampedWord(word: "Uh", startMs: 0, endMs: 120, confidence: 0.92),
                        TimestampedWord(word: "uh", startMs: 180, endMs: 300, confidence: 0.90),
                    ]
                ),
                startOffsetMs: 0
            ),
            .init(
                source: .system,
                result: STTResult(
                    text: "lecture content",
                    words: [
                        TimestampedWord(word: "lecture", startMs: 0, endMs: 240, confidence: 0.95),
                        TimestampedWord(word: "content", startMs: 280, endMs: 560, confidence: 0.95),
                    ]
                ),
                startOffsetMs: 0
            ),
        ])

        XCTAssertEqual(finalized.words.map(\.word), ["lecture", "content"])
        XCTAssertEqual(finalized.words.map(\.speakerId), ["system", "system"])
        XCTAssertEqual(finalized.speakers, [
            SpeakerInfo(id: "system", label: "Others"),
        ])
        XCTAssertEqual(finalized.rawTranscript, "lecture content")
    }

    func testFinalizeDropsLowConfidenceMicDuplicateOfSystemRun() {
        let finalized = MeetingTranscriptFinalizer.finalize(sourceTranscripts: [
            .init(
                source: .microphone,
                result: STTResult(
                    text: "account information",
                    words: [
                        TimestampedWord(word: "account", startMs: 80, endMs: 220, confidence: 0.48),
                        TimestampedWord(word: "information", startMs: 240, endMs: 480, confidence: 0.50),
                    ]
                ),
                startOffsetMs: 0
            ),
            .init(
                source: .system,
                result: STTResult(
                    text: "account information",
                    words: [
                        TimestampedWord(word: "account", startMs: 0, endMs: 140, confidence: 0.93),
                        TimestampedWord(word: "information", startMs: 160, endMs: 400, confidence: 0.93),
                    ]
                ),
                startOffsetMs: 0
            ),
        ])

        XCTAssertEqual(finalized.words.map(\.speakerId), ["system", "system"])
        XCTAssertEqual(finalized.rawTranscript, "account information")
    }

    func testFinalizePreservesHighConfidenceOverlappingMicSpeech() {
        let finalized = MeetingTranscriptFinalizer.finalize(sourceTranscripts: [
            .init(
                source: .microphone,
                result: STTResult(
                    text: "Can you hear me",
                    words: [
                        TimestampedWord(word: "Can", startMs: 120, endMs: 220, confidence: 0.90),
                        TimestampedWord(word: "you", startMs: 240, endMs: 320, confidence: 0.90),
                        TimestampedWord(word: "hear", startMs: 340, endMs: 450, confidence: 0.90),
                        TimestampedWord(word: "me", startMs: 470, endMs: 540, confidence: 0.90),
                    ]
                ),
                startOffsetMs: 0
            ),
            .init(
                source: .system,
                result: STTResult(
                    text: "Can you hear me",
                    words: [
                        TimestampedWord(word: "Can", startMs: 0, endMs: 100, confidence: 0.90),
                        TimestampedWord(word: "you", startMs: 120, endMs: 200, confidence: 0.90),
                        TimestampedWord(word: "hear", startMs: 220, endMs: 330, confidence: 0.90),
                        TimestampedWord(word: "me", startMs: 350, endMs: 420, confidence: 0.90),
                    ]
                ),
                startOffsetMs: 0
            ),
        ])

        XCTAssertEqual(
            finalized.words.map(\.speakerId),
            ["system", "microphone", "system", "system", "microphone", "microphone", "system", "microphone"]
        )
    }

    func testFinalizeDropsWhisperSubtitleArtifactFromRawText() {
        let finalized = MeetingTranscriptFinalizer.finalize(sourceTranscripts: [
            .init(
                source: .microphone,
                result: STTResult(
                    text: "What is happening? Продолжение следует...",
                    words: [
                        TimestampedWord(word: "What", startMs: 0, endMs: 150, confidence: 0.98),
                        TimestampedWord(word: "is", startMs: 150, endMs: 270, confidence: 0.99),
                        TimestampedWord(word: "happening?", startMs: 270, endMs: 610, confidence: 1.0),
                        TimestampedWord(word: "Продолжение", startMs: 9_300, endMs: 10_700, confidence: 0.54),
                        TimestampedWord(word: "следует...", startMs: 10_700, endMs: 12_100, confidence: 0.97),
                    ],
                    engine: .whisper,
                    engineVariant: "large-v3-v20240930_turbo_632MB"
                ),
                startOffsetMs: 0
            ),
        ])

        XCTAssertEqual(finalized.words.map(\.word), ["What", "is", "happening?"])
        XCTAssertEqual(finalized.rawTranscript, "What is happening?")
    }

    func testFinalizeKeepsHighConfidenceWhisperSubtitlePhrase() {
        let finalized = MeetingTranscriptFinalizer.finalize(sourceTranscripts: [
            .init(
                source: .microphone,
                result: STTResult(
                    text: "Продолжение следует...",
                    words: [
                        TimestampedWord(word: "Продолжение", startMs: 100, endMs: 1_400, confidence: 0.97),
                        TimestampedWord(word: "следует...", startMs: 1_400, endMs: 2_800, confidence: 0.98),
                    ],
                    engine: .whisper,
                    engineVariant: "large-v3-v20240930_turbo_632MB"
                ),
                startOffsetMs: 0
            ),
        ])

        XCTAssertEqual(finalized.words.map(\.word), ["Продолжение", "следует..."])
        XCTAssertEqual(finalized.rawTranscript, "Продолжение следует...")
    }
}
