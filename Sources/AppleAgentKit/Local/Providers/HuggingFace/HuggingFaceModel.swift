//
//  HuggingFaceModel.swift
//  AppleAgentKit
//

import Foundation

public struct HuggingFaceModel: LocalModel {
  public let id: String
  public let displayName: String
  public let repositoryID: String
  public let revision: String
  public let matchingFiles: [String]
  public let expectedDownloadSize: Int64?
  public let compatibility: LocalModelCompatibility

  public init(
    id: String,
    displayName: String,
    repositoryID: String,
    revision: String = "main",
    matchingFiles: [String] = [],
    expectedDownloadSize: Int64? = nil,
    compatibility: LocalModelCompatibility = .coreAI
  ) {
    self.id = id
    self.displayName = displayName
    self.repositoryID = repositoryID
    self.revision = revision
    self.matchingFiles = matchingFiles
    self.expectedDownloadSize = expectedDownloadSize
    self.compatibility = compatibility
  }
}
