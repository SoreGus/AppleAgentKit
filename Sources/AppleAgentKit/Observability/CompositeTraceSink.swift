//
//  CompositeTraceSink.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public struct CompositeTraceSink: AgentTraceSink {
    private let sinks: [any AgentTraceSink]

    public init(
        sinks: [any AgentTraceSink]
    ) {
        self.sinks = sinks
    }

    public func record(
        _ event: AgentTraceEvent
    ) async {
        for sink in sinks {
            await sink.record(event)
        }
    }
}
