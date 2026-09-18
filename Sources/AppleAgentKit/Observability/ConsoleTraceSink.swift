//
//  ConsoleTraceSink.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public actor ConsoleTraceSink: AgentTraceSink {
    private let label: String
    private var sequence = 0

    private let timestampFormatter: ISO8601DateFormatter

    public init(
        label: String = "AppleAgentKit"
    ) {
        self.label = label

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        timestampFormatter = formatter
    }

    public func record(
        _ event: AgentTraceEvent
    ) async {
        sequence += 1

        let timestamp = timestampFormatter.string(
            from: event.timestamp
        )

        var lines: [String] = [
            "[\(label)] [\(timestamp)] [\(sequence)] [\(event.kind.rawValue.uppercased())]"
        ]

        if let name = event.name,
           !name.isEmpty {
            lines.append("name: \(name)")
        }

        if let message = event.message,
           !message.isEmpty {
            lines.append("message:")
            lines.append(message)
        }

        if !event.metadata.isEmpty {
            let metadata = event.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")

            lines.append("metadata: \(metadata)")
        }

        print(
            lines.joined(separator: "\n")
        )
    }
}
