//
//  ApprovalHandler.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import FoundationModels

public protocol ApprovalHandler: Sendable {
    func requestApproval(
        for call: Transcript.ToolCall
    ) async -> Bool
}

public struct ClosureApprovalHandler: ApprovalHandler {
    public typealias Handler = @Sendable (Transcript.ToolCall) async -> Bool

    private let handler: Handler

    public init(
        handler: @escaping Handler
    ) {
        self.handler = handler
    }

    public func requestApproval(
        for call: Transcript.ToolCall
    ) async -> Bool {
        await handler(call)
    }
}
