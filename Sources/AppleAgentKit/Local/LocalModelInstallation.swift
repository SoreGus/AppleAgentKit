//
//  LocalModelInstallation.swift
//  AppleAgentKit
//

import Foundation

public struct LocalModelInstallation: Hashable, Sendable {
  public let modelID: String
  public let repositoryID: String
  public let requestedRevision: String
  public let resolvedRevision: String
  public let localURL: URL
  public let installedAt: Date
  public let files: [String]

  public init(
    modelID: String,
    repositoryID: String,
    requestedRevision: String,
    resolvedRevision: String,
    localURL: URL,
    installedAt: Date,
    files: [String]
  ) {
    self.modelID = modelID
    self.repositoryID = repositoryID
    self.requestedRevision = requestedRevision
    self.resolvedRevision = resolvedRevision
    self.localURL = localURL
    self.installedAt = installedAt
    self.files = files
  }
}

public struct LocalModelFileInformation: Hashable, Sendable {
  public let path: String
  public let size: Int64?

  public init(
    path: String,
    size: Int64? = nil
  ) {
    self.path = path
    self.size = size
  }
}

public struct LocalModelInformation: Hashable, Sendable {
  public enum Access: String, Hashable, Sendable {
    case publicAccess
    case gatedAutomatic
    case gatedManual
  }

  public let modelID: String
  public let repositoryID: String
  public let requestedRevision: String
  public let resolvedRevision: String
  public let lastModified: Date?
  public let access: Access
  public let files: [LocalModelFileInformation]
  public let downloadSize: Int64?

  public init(
    modelID: String,
    repositoryID: String,
    requestedRevision: String,
    resolvedRevision: String,
    lastModified: Date? = nil,
    access: Access,
    files: [LocalModelFileInformation],
    downloadSize: Int64? = nil
  ) {
    self.modelID = modelID
    self.repositoryID = repositoryID
    self.requestedRevision = requestedRevision
    self.resolvedRevision = resolvedRevision
    self.lastModified = lastModified
    self.access = access
    self.files = files
    self.downloadSize = downloadSize
  }
}
