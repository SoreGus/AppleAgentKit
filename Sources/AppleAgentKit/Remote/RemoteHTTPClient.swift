//
//  RemoteHTTPClient.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public struct RemoteHTTPResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse

    public init(
        data: Data,
        response: HTTPURLResponse
    ) {
        self.data = data
        self.response = response
    }
}

public protocol RemoteHTTPClient: Sendable {
    func send(
        _ request: URLRequest
    ) async throws -> RemoteHTTPResponse
}

public struct DefaultRemoteHTTPClient: RemoteHTTPClient {
    private let transport: any RemoteTransport
    private let authentication: any RemoteAuthentication

    public init(
        transport: any RemoteTransport = URLSessionRemoteTransport(),
        authentication: any RemoteAuthentication = NoRemoteAuthentication()
    ) {
        self.transport = transport
        self.authentication = authentication
    }

    public func send(
        _ request: URLRequest
    ) async throws -> RemoteHTTPResponse {
        let authenticatedRequest: URLRequest

        do {
            authenticatedRequest = try await authentication.authenticate(
                request
            )
        } catch let error as RemoteError {
            throw error
        } catch {
            throw RemoteError.authenticationFailed(
                error.localizedDescription
            )
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await transport.data(
                for: authenticatedRequest
            )
        } catch let error as RemoteError {
            throw error
        } catch {
            let nsError = error as NSError

            throw RemoteError.transportFailure(
                RemoteTransportFailure(
                    domain: nsError.domain,
                    code: nsError.code,
                    message: error.localizedDescription,
                    url: authenticatedRequest.url?.absoluteString
                )
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteError.invalidResponseDetail(
                "Expected HTTPURLResponse but received \(String(reflecting: type(of: response)))."
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RemoteError.httpFailure(
                RemoteHTTPFailure(
                    statusCode: httpResponse.statusCode,
                    method: authenticatedRequest.httpMethod,
                    url: authenticatedRequest.url?.absoluteString,
                    requestID: Self.requestID(from: httpResponse),
                    retryAfter: httpResponse.value(
                        forHTTPHeaderField: "Retry-After"
                    ),
                    responseBody: Self.responseBody(from: data)
                )
            )
        }

        return RemoteHTTPResponse(
            data: data,
            response: httpResponse
        )
    }
}

private extension DefaultRemoteHTTPClient {
    static func requestID(
        from response: HTTPURLResponse
    ) -> String? {
        response.value(forHTTPHeaderField: "x-request-id")
            ?? response.value(forHTTPHeaderField: "request-id")
            ?? response.value(forHTTPHeaderField: "x-correlation-id")
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
