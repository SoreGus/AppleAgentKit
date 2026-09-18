//
//  OpenAIResponse.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

internal struct OpenAIResponse: Decodable, Sendable {
    struct Output: Decodable, Sendable {
        let type: String
        let id: String?
        let callID: String?
        let name: String?
        let arguments: String?
        let content: [Content]?

        enum CodingKeys: String, CodingKey {
            case type
            case id
            case callID = "call_id"
            case name
            case arguments
            case content
        }
    }

    struct Content: Decodable, Sendable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable, Sendable {
        struct OutputDetails: Decodable, Sendable {
            let reasoningTokens: Int?

            enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let inputTokens: Int?
        let outputTokens: Int?
        let outputTokenDetails: OutputDetails?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case outputTokenDetails = "output_tokens_details"
        }
    }

    let id: String
    let output: [Output]
    let usage: Usage?
}
