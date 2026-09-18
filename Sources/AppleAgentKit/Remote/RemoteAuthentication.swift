//
//  RemoteAuthentication.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public protocol RemoteAuthentication: Sendable {
    func authenticate(
        _ request: URLRequest
    ) async throws -> URLRequest
}

public struct NoRemoteAuthentication: RemoteAuthentication {
    public init() {}

    public func authenticate(
        _ request: URLRequest
    ) async throws -> URLRequest {
        request
    }
}

public struct BearerTokenAuthentication: RemoteAuthentication {
    public let token: String

    public init(
        token: String
    ) {
        self.token = token
    }

    public func authenticate(
        _ request: URLRequest
    ) async throws -> URLRequest {
        var request = request
        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }
}
