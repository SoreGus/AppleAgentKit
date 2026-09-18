//
//  AgentTracer.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public actor AgentTracer {
    public let configuration: AgentTraceConfiguration
    private let sinks: [any AgentTraceSink]

    public init(
        configuration: AgentTraceConfiguration = .init(),
        sinks: [any AgentTraceSink]
    ) {
        self.configuration = configuration
        self.sinks = sinks
    }

    public func traceConfiguration() -> AgentTraceConfiguration {
        configuration
    }

    public func record(
        _ event: AgentTraceEvent
    ) async {
        for sink in sinks {
            await sink.record(event)
        }
    }
}
