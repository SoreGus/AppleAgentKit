//
//  OpenAIRequestBuilder.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import UniformTypeIdentifiers

internal enum OpenAIRequestBuilder {
    static func makeRequest(
        request generationRequest: LanguageModelExecutorGenerationRequest,
        modelID: String,
        baseURL: URL
    ) throws -> URLRequest {
        let endpoint = baseURL.appending(path: "responses")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": modelID,
            "store": false,
            "stream": false,
            "input": try makeInput(from: generationRequest.transcript)
        ]

        if !generationRequest.enabledToolDefinitions.isEmpty {
            body["tools"] = try generationRequest.enabledToolDefinitions.map(makeTool)
        }

        if let toolCallingMode = generationRequest.generationOptions.toolCallingMode {
            body["tool_choice"] = toolChoice(for: toolCallingMode)
        }

        if let temperature = generationRequest.generationOptions.temperature {
            body["temperature"] = temperature
        }

        if let maximumResponseTokens = generationRequest.generationOptions.maximumResponseTokens {
            body["max_output_tokens"] = maximumResponseTokens
        }

        if let schema = generationRequest.schema {
            let schemaData = try JSONEncoder().encode(schema)
            let schemaObject = try JSONSerialization.jsonObject(with: schemaData)

            body["text"] = [
                "format": [
                    "type": "json_schema",
                    "name": "foundation_models_response",
                    "strict": true,
                    "schema": schemaObject
                ]
            ]
        }

        if let reasoningLevel = generationRequest.contextOptions.reasoningLevel {
            body["reasoning"] = [
                "effort": reasoningEffort(for: reasoningLevel)
            ]
        }

        do {
            urlRequest.httpBody = try JSONSerialization.data(
                withJSONObject: body,
                options: []
            )
        } catch {
            throw RemoteError.encodingFailed(error.localizedDescription)
        }

        return urlRequest
    }

    private static func makeInput(
        from transcript: Transcript
    ) throws -> [[String: Any]] {
        var input: [[String: Any]] = []

        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                input.append([
                    "role": "developer",
                    "content": try makeContent(from: instructions.segments)
                ])

            case .prompt(let prompt):
                input.append([
                    "role": "user",
                    "content": try makeContent(from: prompt.segments)
                ])

            case .response(let response):
                input.append([
                    "role": "assistant",
                    "content": try makeContent(from: response.segments)
                ])

            case .reasoning:
                continue

            case .toolCalls(let calls):
                for call in calls {
                    input.append([
                        "type": "function_call",
                        "call_id": call.id,
                        "name": call.toolName,
                        "arguments": call.arguments.jsonString
                    ])
                }

            case .toolOutput(let output):
                input.append([
                    "type": "function_call_output",
                    "call_id": output.id,
                    "output": try makePlainText(from: output.segments)
                ])

            @unknown default:
                continue
            }
        }

        return input
    }

    private static func makeContent(
        from segments: [Transcript.Segment]
    ) throws -> [[String: Any]] {
        var content: [[String: Any]] = []

        for segment in segments {
            switch segment {
            case .text(let text):
                content.append([
                    "type": "input_text",
                    "text": text.content
                ])

            case .structure(let structure):
                content.append([
                    "type": "input_text",
                    "text": structure.content.jsonString
                ])

            case .attachment(let attachment):
                switch attachment.content {
                case .image(let image):
                    content.append([
                        "type": "input_image",
                        "image_url": try imageDataURL(image.cgImage)
                    ])

                @unknown default:
                    throw RemoteError.unsupportedTranscriptContent(
                        "OpenAI provider currently supports image attachments only."
                    )
                }

            @unknown default:
                continue
            }
        }

        return content
    }

    private static func makePlainText(
        from segments: [Transcript.Segment]
    ) throws -> String {
        var values: [String] = []

        for segment in segments {
            switch segment {
            case .text(let text):
                values.append(text.content)

            case .structure(let structure):
                values.append(structure.content.jsonString)

            case .attachment:
                values.append("[attachment]")

            @unknown default:
                continue
            }
        }

        return values.joined(separator: "\n")
    }

    private static func makeTool(
        _ definition: Transcript.ToolDefinition
    ) throws -> [String: Any] {
        let parametersData = try JSONEncoder().encode(definition.parameters)
        let parameters = try JSONSerialization.jsonObject(with: parametersData)

        return [
            "type": "function",
            "name": definition.name,
            "description": definition.description,
            "parameters": parameters,
            "strict": true
        ]
    }

    private static func toolChoice(
        for mode: GenerationOptions.ToolCallingMode
    ) -> String {
        switch mode.kind {
        case .allowed:
            "auto"
        case .required:
            "required"
        case .disallowed:
            "none"
        @unknown default:
            "auto"
        }
    }

    private static func reasoningEffort(
        for level: ContextOptions.ReasoningLevel
    ) -> String {
        switch level {
        case .light:
            "low"
        case .moderate:
            "medium"
        case .deep:
            "high"
        case .custom(let value):
            value
        @unknown default:
            "medium"
        }
    }

    private static func imageDataURL(
        _ image: CGImage
    ) throws -> String {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RemoteError.encodingFailed("Unable to create image destination.")
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw RemoteError.encodingFailed("Unable to encode image attachment.")
        }

        return "data:image/png;base64,\(data.base64EncodedString())"
    }
}
