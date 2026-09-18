//
//  AgentServices.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public struct AgentServices: Sendable {
    public let approvalHandler: (any ApprovalHandler)?
    public let tracer: AgentTracer?

    public init(
        approvalHandler: (any ApprovalHandler)? = nil,
        tracer: AgentTracer? = nil
    ) {
        self.approvalHandler = approvalHandler
        self.tracer = tracer
    }
}
