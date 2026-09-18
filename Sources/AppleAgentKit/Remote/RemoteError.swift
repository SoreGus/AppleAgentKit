//
//  RemoteError.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public struct RemoteHTTPFailure: Sendable, Equatable {
    public let statusCode: Int
    public let method: String?
    public let url: String?
    public let requestID: String?
    public let retryAfter: String?
    public let responseBody: String?

    public init(
        statusCode: Int,
        method: String? = nil,
        url: String? = nil,
        requestID: String? = nil,
        retryAfter: String? = nil,
        responseBody: String? = nil
    ) {
        self.statusCode = statusCode
        self.method = method
        self.url = url
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.responseBody = responseBody
    }
}

public struct RemoteTransportFailure: Sendable, Equatable {
    public let domain: String
    public let code: Int
    public let message: String
    public let url: String?

    public init(
        domain: String,
        code: Int,
        message: String,
        url: String? = nil
    ) {
        self.domain = domain
        self.code = code
        self.message = message
        self.url = url
    }
}

public struct RemoteProviderFailure: Sendable, Equatable {
    public let provider: String
    public let statusCode: Int?
    public let code: String?
    public let type: String?
    public let parameter: String?
    public let message: String
    public let requestID: String?
    public let retryAfter: String?
    public let responseBody: String?

    public init(
        provider: String,
        statusCode: Int? = nil,
        code: String? = nil,
        type: String? = nil,
        parameter: String? = nil,
        message: String,
        requestID: String? = nil,
        retryAfter: String? = nil,
        responseBody: String? = nil
    ) {
        self.provider = provider
        self.statusCode = statusCode
        self.code = code
        self.type = type
        self.parameter = parameter
        self.message = message
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.responseBody = responseBody
    }
}

public enum RemoteError: Error, Sendable, Equatable {
    case invalidURL
    case invalidRequest(String)
    case invalidResponse
    case invalidResponseDetail(String)
    case httpStatus(Int, String)
    case authenticationFailed(String)
    case httpFailure(RemoteHTTPFailure)
    case providerFailure(RemoteProviderFailure)
    case transportFailure(RemoteTransportFailure)
    case encodingFailed(String)
    case decodingFailed(String)
    case unsupportedTranscriptContent(String)
}

extension RemoteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Remote request URL is invalid."

        case .invalidRequest(let message):
            return "Remote request is invalid. \(message)"

        case .invalidResponse:
            return "Remote provider returned an invalid response."

        case .invalidResponseDetail(let message):
            return "Remote provider returned an invalid response. \(message)"

        case .httpStatus(let statusCode, let body):
            var description = "Remote HTTP request failed with status \(statusCode) (\(Self.httpStatusMeaning(statusCode)))."

            if !body.isEmpty {
                description += "\nResponse: \(body)"
            }

            return description

        case .authenticationFailed(let message):
            return "Remote authentication failed. \(message)"

        case .httpFailure(let failure):
            return Self.httpDescription(failure)

        case .providerFailure(let failure):
            return Self.providerDescription(failure)

        case .transportFailure(let failure):
            return Self.transportDescription(failure)

        case .encodingFailed(let message):
            return "Remote request encoding failed. \(message)"

        case .decodingFailed(let message):
            return "Remote response decoding failed. \(message)"

        case .unsupportedTranscriptContent(let message):
            return "Remote provider does not support part of the transcript. \(message)"
        }
    }
}

extension RemoteError: CustomStringConvertible {
    public var description: String {
        errorDescription ?? "Remote error."
    }
}

private extension RemoteError {
    static func httpDescription(
        _ failure: RemoteHTTPFailure
    ) -> String {
        var lines = [
            "Remote HTTP request failed with status \(failure.statusCode) (\(httpStatusMeaning(failure.statusCode)))."
        ]

        if let method = failure.method,
           let url = failure.url {
            lines.append("Request: \(method) \(url)")
        } else if let url = failure.url {
            lines.append("URL: \(url)")
        }

        if let requestID = failure.requestID,
           !requestID.isEmpty {
            lines.append("Request ID: \(requestID)")
        }

        if let retryAfter = failure.retryAfter,
           !retryAfter.isEmpty {
            lines.append("Retry-After: \(retryAfter)")
        }

        if let responseBody = failure.responseBody,
           !responseBody.isEmpty {
            lines.append("Response: \(responseBody)")
        }

        return lines.joined(separator: "\n")
    }

    static func providerDescription(
        _ failure: RemoteProviderFailure
    ) -> String {
        var headline = "\(failure.provider) request failed"

        if let statusCode = failure.statusCode {
            headline += " with status \(statusCode) (\(httpStatusMeaning(statusCode)))"
        }

        headline += "."

        var lines = [headline, "Message: \(failure.message)"]

        if let type = failure.type,
           !type.isEmpty {
            lines.append("Type: \(type)")
        }

        if let code = failure.code,
           !code.isEmpty {
            lines.append("Code: \(code)")
        }

        if let parameter = failure.parameter,
           !parameter.isEmpty {
            lines.append("Parameter: \(parameter)")
        }

        if let requestID = failure.requestID,
           !requestID.isEmpty {
            lines.append("Request ID: \(requestID)")
        }

        if let retryAfter = failure.retryAfter,
           !retryAfter.isEmpty {
            lines.append("Retry-After: \(retryAfter)")
        }

        return lines.joined(separator: "\n")
    }

    static func transportDescription(
        _ failure: RemoteTransportFailure
    ) -> String {
        var lines = [
            "Remote transport failed.",
            "Message: \(failure.message)",
            "Error: \(failure.domain) \(failure.code)"
        ]

        if let url = failure.url,
           !url.isEmpty {
            lines.append("URL: \(url)")
        }

        return lines.joined(separator: "\n")
    }

    static func httpStatusMeaning(
        _ statusCode: Int
    ) -> String {
        switch statusCode {
        case 400:
            "bad request"
        case 401:
            "authentication failed"
        case 403:
            "permission denied"
        case 404:
            "not found"
        case 408:
            "request timeout"
        case 409:
            "conflict"
        case 422:
            "unprocessable request"
        case 429:
            "rate limited"
        case 500...599:
            "server error"
        default:
            "HTTP error"
        }
    }
}
