import XCTest
@testable import MacParakeetCore

final class MeetingTranscriptAssemblerTests: XCTestCase {
    func testApplyDeduplicatesOverlapForSingleSource() {
        var assembler = MeetingTranscriptAssembler()

        let firstChunk = AudioChunker.AudioChunk(samples: [0], startMs: 0, endMs: 5_000)
        let firstResult = STTResult(text: "Hello team", words: [
            TimestampedWord(word: "Hello", startMs: 100, endMs: 400, confidence: 0.9),
            TimestampedWord(word: "team", startMs: 4_200, endMs: 4_600, confidence: 0.9),
        ])
        _ = assembler.apply(result: firstResult, chunk: firstChunk, source: .microphone)

        let secondChunk = AudioChunker.AudioChunk(samples: [0], startMs: 4_000, endMs: 9_000)
        let secondResult = STTResult(text: "team again", words: [
            TimestampedWord(word: "team", startMs: 100, endMs: 500, confidence: 0.9),
            TimestampedWord(word: "again", startMs: 700, endMs: 1_000, confidence: 0.9),
        ])
        let update = assembler.apply(result: secondResult, chunk: secondChunk, source: .microphone)

        XCTAssertEqual(update.words.map(\.word), ["Hello", "team", "again"])
        XCTAssertEqual(update.words.map(\.speakerId), ["microphone", "microphone", "microphone"])
    }

    func testApplyDropsWhisperSubtitleArtifactRun() {
        var assembler = MeetingTranscriptAssembler()

        _ = assembler.apply(
            result: STTResult(text: "Okay", words: [
                TimestampedWord(word: "Okay", startMs: 100, endMs: 400, confidence: 0.95),
            ]),
            chunk: AudioChunker.AudioChunk(samples: [0], startMs: 0, endMs: 5_000),
            source: .microphone
        )

        let update = assembler.apply(
            result: STTResult(
                text: "Продолжение следует...",
                words: [
                    TimestampedWord(word: "Продолжение", startMs: 100, endMs: 1_400, confidence: 0.54),
                    TimestampedWord(word: "следует...", startMs: 1_400, endMs: 2_800, confidence: 0.97),
                ],
                engine: .whisper,
                engineVariant: "large-v3-v20240930_turbo_632MB"
            ),
            chunk: AudioChunker.AudioChunk(samples: [0], startMs: 4_000, endMs: 9_000),
            source: .microphone
        )

        XCTAssertEqual(update.words.map(\.word), ["Okay"])
    }

    func testApplyKeepsSubtitleWordsFromNonWhisperEngine() {
        var assembler = MeetingTranscriptAssembler()

        let update = assembler.apply(
            result: STTResult(text: "Продолжение следует...", words: [
                TimestampedWord(word: "Продолжение", startMs: 100, endMs: 1_400, confidence: 0.54),
                TimestampedWord(word: "следует...", startMs: 1_400, endMs: 2_800, confidence: 0.97),
            ]),
            chunk: AudioChunker.AudioChunk(samples: [0], startMs: 0, endMs: 5_000),
            source: .microphone
        )

        XCTAssertEqual(update.words.map(\.word), ["Продолжение", "следует..."])
    }

    func testApplyKeepsContextualWhisperSubtitlePhrase() {
        var assembler = MeetingTranscriptAssembler()

        let update = assembler.apply(
            result: STTResult(
                text: "He said Продолжение следует today",
                words: [
                    TimestampedWord(word: "He", startMs: 0, endMs: 120, confidence: 0.96),
                    TimestampedWord(word: "said", startMs: 180, endMs: 340, confidence: 0.96),
                    TimestampedWord(word: "Продолжение", startMs: 390, endMs: 1_000, confidence: 0.54),
                    TimestampedWord(word: "следует", startMs: 1_000, endMs: 1_520, confidence: 0.97),
                    TimestampedWord(word: "today", startMs: 1_580, endMs: 1_900, confidence: 0.96),
                ],
                engine: .whisper,
                engineVariant: "large-v3-v20240930_turbo_632MB"
            ),
            chunk: AudioChunker.AudioChunk(samples: [0], startMs: 0, endMs: 5_000),
            source: .microphone
        )

        XCTAssertEqual(update.words.map(\.word), ["He", "said", "Продолжение", "следует", "today"])
    }

    func testApplyKeepsHighConfidenceWhisperSubtitlePhrase() {
        var assembler = MeetingTranscriptAssembler()

        let update = assembler.apply(
            result: STTResult(
                text: "Продолжение следует...",
                words: [
                    TimestampedWord(word: "Продолжение", startMs: 100, endMs: 1_400, confidence: 0.97),
                    TimestampedWord(word: "следует...", startMs: 1_400, endMs: 2_800, confidence: 0.98),
                ],
                engine: .whisper,
                engineVariant: "large-v3-v20240930_turbo_632MB"
            ),
            chunk: AudioChunker.AudioChunk(samples: [0], startMs: 0, endMs: 5_000),
            source: .microphone
        )

        XCTAssertEqual(update.words.map(\.word), ["Продолжение", "следует..."])
    }

    func testFinalizedTranscriptBuildsSpeakerMetadataAcrossSources() {
        var assembler = MeetingTranscriptAssembler()

        _ = assembler.apply(
            result: STTResult(text: "Hello there", words: [
                TimestampedWord(word: "Hello", startMs: 0, endMs: 300, confidence: 0.9),
                TimestampedWord(word: "there", startMs: 320, endMs: 650, confidence: 0.9),
            ]),
            chunk: AudioChunker.AudioChunk(samples: [0], startMs: 0, endMs: 5_000),
            source: .microphone
        )

        _ = assembler.apply(
            result: STTResult(text: "Sounds good", words: [
                TimestampedWord(word: "Sounds", startMs: 900, endMs: 1_200, confidence: 0.9),
                TimestampedWord(word: "good", startMs: 1_250, endMs: 1_500, confidence: 0.9),
            ]),
            chunk: AudioChunker.AudioChunk(samples: [0], startMs: 0, endMs: 5_000),
            source: .system
        )

        let transcript = assembler.finalizedTranscript(durationMs: 1_500)

        XCTAssertEqual(transcript?.speakerCount, 2)
        XCTAssertEqual(transcript?.speakers, [
            SpeakerInfo(id: "microphone", label: "Me"),
            SpeakerInfo(id: "system", label: "Others"),
        ])
        XCTAssertEqual(transcript?.words.map(\.word), ["Hello", "there", "Sounds", "good"])
        XCTAssertEqual(transcript?.diarizationSegments.count, 2)
        XCTAssertEqual(transcript?.rawTranscript, "Hello there Sounds good")
    }
}
