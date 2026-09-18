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
        let request = try await authentication.authenticate(request)
        let (data, response) = try await transport.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw RemoteError.invalidResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            throw RemoteError.httpStatus(
                response.statusCode,
                String(decoding: data, as: UTF8.self)
            )
        }

        return RemoteHTTPResponse(
            data: data,
            response: response
        )
    }
}
