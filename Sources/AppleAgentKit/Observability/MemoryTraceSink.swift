//
//  MemoryTraceSink.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public actor MemoryTraceSink: AgentTraceSink {
    private let capacity: Int
    private var events: [AgentTraceEvent] = []

    public init(
        capacity: Int = 1_000
    ) {
        self.capacity = max(1, capacity)
    }

    public func record(
        _ event: AgentTraceEvent
    ) async {
        events.append(event)

        let overflow = events.count - capacity

        if overflow > 0 {
            events.removeFirst(overflow)
        }
    }

    public func snapshot() -> [AgentTraceEvent] {
        events
    }

    public func clear() {
        events.removeAll(keepingCapacity: true)
    }
}
