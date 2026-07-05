import Foundation
import MacParakeetCore
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import OSLog

#if MACPARAKEET_HAS_MLX_LOCAL_LLM

public actor MLXLocalLLMRuntime: LocalLLMRuntime {
    private let logger = Logger(subsystem: "com.macparakeet.core", category: "MLXLocalLLMRuntime")
    private var session: ChatSession?
    private var loadedModel: LocalLLMModelReference?
    private var latestMetrics: LLMGenerationMetrics?

    public init() {}

    public func load(model: LocalLLMModelReference) async throws {
        try Task.checkCancellation()
        if loadedModel == model, session != nil {
            return
        }

        session = nil
        latestMetrics = nil

        let container = try await loadModelContainer(from: model.directory)
        session = ChatSession(container)
        loadedModel = model
        logger.info("Loaded local MLX model \(model.modelName, privacy: .public)")
    }

    public func unload() async {
        session = nil
        loadedModel = nil
        latestMetrics = nil
        logger.info("Unloaded local MLX model")
    }

    public func generateStream(
        messages: [ChatMessage],
        options: ChatCompletionOptions
    ) async throws -> AsyncThrowingStream<LocalLLMRuntimeEvent, Error> {
        guard session != nil else {
            throw LLMError.modelNotFound("Local MLX model is not loaded.")
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                await self.generate(
                    messages: messages,
                    options: options,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func instrumentation() async -> LLMGenerationMetrics? {
        latestMetrics
    }

    private func generate(
        messages: [ChatMessage],
        options: ChatCompletionOptions,
        continuation: AsyncThrowingStream<LocalLLMRuntimeEvent, Error>.Continuation
    ) async {
        do {
            guard let session else {
                throw LLMError.modelNotFound("Local MLX model is not loaded.")
            }

            try Task.checkCancellation()
            let prompt = Self.prompt(from: messages)
            let parameters = GenerateParameters(
                temperature: Float(options.temperature ?? 0.2),
                maxTokens: options.maxTokens,
                kvBits: 4
            )

            let start = Date()
            var firstTokenDate: Date?
            var tokenCount = 0

            for try await token in session.streamResponse(
                to: prompt,
                generateParameters: parameters
            ) {
                try Task.checkCancellation()
                if firstTokenDate == nil {
                    firstTokenDate = Date()
                }
                tokenCount += 1
                continuation.yield(.text(token))
            }

            let duration = max(Date().timeIntervalSince(start), 0.001)
            let metrics = LLMGenerationMetrics(
                tokensPerSecond: Double(tokenCount) / duration,
                promptTokensPerSecond: nil,
                timeToFirstTokenMs: firstTokenDate.map { Int($0.timeIntervalSince(start) * 1_000) },
                peakRSSBytes: nil
            )
            latestMetrics = metrics
            continuation.yield(.metrics(metrics))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private static func prompt(from messages: [ChatMessage]) -> String {
        messages.map { message in
            switch message.role {
            case .system:
                return "System: \(message.content)"
            case .user:
                return "User: \(message.modelContent)"
            case .assistant:
                return "Assistant: \(message.content)"
            }
        }
        .joined(separator: "\n\n")
    }
}

#endif
