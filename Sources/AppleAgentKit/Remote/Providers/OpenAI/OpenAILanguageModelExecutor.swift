//
//  OpenAILanguageModelExecutor.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation
import FoundationModels

public struct OpenAILanguageModelExecutor: LanguageModelExecutor {
    public typealias Model = OpenAILanguageModel

    public struct Configuration: Hashable, Sendable {
        public let modelID: String
        public let baseURL: URL
        public let client: RemoteHTTPClientHandle

        public init(
            modelID: String,
            baseURL: URL,
            client: RemoteHTTPClientHandle
        ) {
            self.modelID = modelID
            self.baseURL = baseURL
            self.client = client
        }
    }

    private let configuration: Configuration

    public init(
        configuration: Configuration
    ) throws {
        guard !configuration.modelID.isEmpty else {
            throw RemoteError.invalidRequest("OpenAI model ID cannot be empty.")
        }

        self.configuration = configuration
    }

    public func prewarm(
        model: Model,
        transcript: Transcript
    ) {
        // Remote providers do not require local model prewarming.
    }

    public nonisolated(nonsending) func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let urlRequest = try OpenAIRequestBuilder.makeRequest(
            request: request,
            modelID: configuration.modelID,
            baseURL: configuration.baseURL
        )

        let httpResponse = try await configuration.client.client.send(urlRequest)
        let response: OpenAIResponse

        do {
            response = try JSONDecoder().decode(
                OpenAIResponse.self,
                from: httpResponse.data
            )
        } catch {
            throw RemoteError.decodingFailed(error.localizedDescription)
        }

        try await emit(
            response,
            into: channel
        )
    }

    private nonisolated func emit(
        _ response: OpenAIResponse,
        into channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        var emittedContent = false

        for output in response.output {
            switch output.type {
            case "message":
                for content in output.content ?? [] where content.type == "output_text" {
                    guard let text = content.text,
                          !text.isEmpty else {
                        continue
                    }

                    emittedContent = true
                    await channel.send(
                        .response(
                            action: .appendText(
                                text,
                                tokenCount: 1
                            )
                        )
                    )
                }

            case "function_call":
                guard let name = output.name,
                      let arguments = output.arguments else {
                    continue
                }

                let callID = output.callID ?? output.id ?? UUID().uuidString
                emittedContent = true

                await channel.send(
                    .toolCalls(
                        action: .toolCall(
                            id: callID,
                            name: name,
                            action: .appendArguments(
                                arguments,
                                tokenCount: 1
                            )
                        )
                    )
                )

            default:
                continue
            }
        }

        if let usage = response.usage {
            await channel.send(
                .response(
                    action: .updateUsage(
                        input: .init(
                            totalTokenCount: usage.inputTokens ?? 0,
                            cachedTokenCount: 0
                        ),
                        output: .init(
                            totalTokenCount: usage.outputTokens ?? 0,
                            reasoningTokenCount: usage.outputTokenDetails?.reasoningTokens ?? 0
                        )
                    )
                )
            )
        }

        guard emittedContent else {
            throw RemoteError.invalidResponse
        }
    }
}
