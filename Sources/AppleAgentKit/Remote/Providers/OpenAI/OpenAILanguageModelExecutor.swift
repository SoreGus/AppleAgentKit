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
            throw RemoteError.invalidRequest(
                "OpenAI model ID cannot be empty."
            )
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

        let httpResponse: RemoteHTTPResponse

        do {
            httpResponse = try await configuration.client.client.send(
                urlRequest
            )
        } catch {
            throw Self.mapOpenAIError(error)
        }

        let response: OpenAIResponse

        do {
            response = try JSONDecoder().decode(
                OpenAIResponse.self,
                from: httpResponse.data
            )
        } catch {
            let body = Self.responseBody(
                from: httpResponse.data
            )

            throw RemoteError.decodingFailed(
                "OpenAI response could not be decoded. \(error.localizedDescription)\(body.map { " Response: \($0)" } ?? "")"
            )
        }

        if let providerError = response.error {
            throw RemoteError.providerFailure(
                RemoteProviderFailure(
                    provider: "OpenAI",
                    statusCode: httpResponse.response.statusCode,
                    code: providerError.code,
                    type: providerError.type,
                    parameter: providerError.parameter,
                    message: providerError.message,
                    requestID: Self.requestID(
                        from: httpResponse.response
                    ),
                    retryAfter: httpResponse.response.value(
                        forHTTPHeaderField: "Retry-After"
                    ),
                    responseBody: Self.responseBody(
                        from: httpResponse.data
                    )
                )
            )
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
            let status = response.status.map { " Status: \($0)." } ?? ""

            throw RemoteError.invalidResponseDetail(
                "OpenAI response contained no text or function calls.\(status) Response ID: \(response.id)."
            )
        }
    }
}

private extension OpenAILanguageModelExecutor {
    static func mapOpenAIError(
        _ error: any Error
    ) -> any Error {
        guard let remoteError = error as? RemoteError,
              case .httpFailure(let failure) = remoteError else {
            return error
        }

        guard let body = failure.responseBody,
              let data = body.data(using: .utf8),
              let response = try? JSONDecoder().decode(
                  OpenAIErrorResponse.self,
                  from: data
              ) else {
            return error
        }

        return RemoteError.providerFailure(
            RemoteProviderFailure(
                provider: "OpenAI",
                statusCode: failure.statusCode,
                code: response.error.code,
                type: response.error.type,
                parameter: response.error.parameter,
                message: response.error.message,
                requestID: failure.requestID,
                retryAfter: failure.retryAfter,
                responseBody: failure.responseBody
            )
        )
    }

    static func requestID(
        from response: HTTPURLResponse
    ) -> String? {
        response.value(forHTTPHeaderField: "x-request-id")
            ?? response.value(forHTTPHeaderField: "request-id")
    }

    static func responseBody(
        from data: Data
    ) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        let body = String(decoding: data, as: UTF8.self)
        let maximumCharacters = 16_384

        guard body.count > maximumCharacters else {
            return body
        }

        return String(body.prefix(maximumCharacters)) + "… [truncated]"
    }
}
