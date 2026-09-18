//
//  RemoteHTTPClientHandle.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public struct RemoteHTTPClientHandle: Hashable, @unchecked Sendable {
    public let id: UUID
    public let client: any RemoteHTTPClient

    public init(
        id: UUID = UUID(),
        client: any RemoteHTTPClient
    ) {
        self.id = id
        self.client = client
    }

    public static func == (
        lhs: RemoteHTTPClientHandle,
        rhs: RemoteHTTPClientHandle
    ) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(
        into hasher: inout Hasher
    ) {
        hasher.combine(id)
    }
}
