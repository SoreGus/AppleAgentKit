//
//  AgentTraceConfiguration.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public struct AgentTraceConfiguration: Sendable, Equatable {
    public var capturePrompts: Bool
    public var captureResponses: Bool
    public var captureReasoning: Bool
    public var captureToolArguments: Bool
    public var captureToolOutputs: Bool

    public init(
        capturePrompts: Bool = false,
        captureResponses: Bool = false,
        captureReasoning: Bool = false,
        captureToolArguments: Bool = false,
        captureToolOutputs: Bool = false
    ) {
        self.capturePrompts = capturePrompts
        self.captureResponses = captureResponses
        self.captureReasoning = captureReasoning
        self.captureToolArguments = captureToolArguments
        self.captureToolOutputs = captureToolOutputs
    }

    public static let metadataOnly = AgentTraceConfiguration()

    public static let verbose = AgentTraceConfiguration(
        capturePrompts: true,
        captureResponses: true,
        captureReasoning: true,
        captureToolArguments: true,
        captureToolOutputs: true
    )
}
