//
//  AgentTraceSink.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public protocol AgentTraceSink: Sendable {
    func record(
        _ event: AgentTraceEvent
    ) async
}
