//
//  OpenAIErrorResponse.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

internal struct OpenAIErrorResponse: Decodable, Sendable {
    let error: OpenAIErrorDetail
}

internal struct OpenAIErrorDetail: Decodable, Sendable {
    let message: String
    let type: String?
    let parameter: String?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case message
        case type
        case parameter = "param"
        case code
    }
}
