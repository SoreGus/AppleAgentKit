//
//  RemoteError.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public enum RemoteError: Error, Sendable, Equatable {
    case invalidURL
    case invalidRequest(String)
    case invalidResponse
    case httpStatus(Int, String)
    case encodingFailed(String)
    case decodingFailed(String)
    case unsupportedTranscriptContent(String)
}
