//
//  AgentTraceEvent.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public enum AgentTraceKind: String, Codable, Sendable {
    case prompt
    case reasoning
    case toolCall
    case toolOutput
    case response
    case profileChanged
    case error
}

public struct AgentTraceEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let kind: AgentTraceKind
    public let name: String?
    public let message: String?
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: AgentTraceKind,
        name: String? = nil,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.name = name
        self.message = message
        self.metadata = metadata
    }
}
