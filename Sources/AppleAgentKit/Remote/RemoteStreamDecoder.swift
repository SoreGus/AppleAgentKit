//
//  RemoteStreamDecoder.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public protocol RemoteStreamDecoder: Sendable {
    associatedtype Event: Sendable

    func decode(
        line: String
    ) throws -> Event?
}

public struct JSONServerSentEventDecoder<Event>: RemoteStreamDecoder
where Event: Decodable & Sendable {
    private let decoder: JSONDecoder

    public init(
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.decoder = decoder
    }

    public func decode(
        line: String
    ) throws -> Event? {
        guard line.hasPrefix("data:") else {
            return nil
        }

        let payload = line.dropFirst(5).trimmingCharacters(
            in: .whitespaces
        )

        guard !payload.isEmpty,
              payload != "[DONE]",
              let data = payload.data(using: .utf8) else {
            return nil
        }

        do {
            return try decoder.decode(
                Event.self,
                from: data
            )
        } catch {
            let maximumCharacters = 2_048
            let diagnosticPayload: String

            if payload.count > maximumCharacters {
                diagnosticPayload = String(
                    payload.prefix(maximumCharacters)
                ) + "… [truncated]"
            } else {
                diagnosticPayload = payload
            }

            throw RemoteError.decodingFailed(
                "Unable to decode server-sent event. \(error.localizedDescription) Payload: \(diagnosticPayload)"
            )
        }
    }
}
