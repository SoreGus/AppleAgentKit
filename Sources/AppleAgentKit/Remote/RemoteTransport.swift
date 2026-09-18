//
//  RemoteTransport.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public protocol RemoteTransport: Sendable {
    func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse)
}

public struct URLSessionRemoteTransport: RemoteTransport {
    private let session: URLSession

    public init(
        session: URLSession = .shared
    ) {
        self.session = session
    }

    public func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
