//
//  JSONLTraceSink.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public actor JSONLTraceSink: AgentTraceSink {
    private let fileURL: URL
    private let encoder: JSONEncoder

    public init(
        fileURL: URL
    ) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func record(
        _ event: AgentTraceEvent
    ) async {
        do {
            let data = try encoder.encode(event)
            var line = data
            line.append(0x0A)

            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try Data().write(to: fileURL)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } catch {
            // Trace persistence must never crash the agent runtime.
        }
    }
}
