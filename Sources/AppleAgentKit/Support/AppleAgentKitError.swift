//
//  AppleAgentKitError.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public enum AppleAgentKitError: Error, Sendable, Equatable {
    case approvalDenied
    case invalidAgentConfiguration(String)
    case tracePersistenceFailed(String)
    case remoteTransportFailed(String)
}
