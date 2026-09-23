//
//  HuggingFaceInstallationManifest.swift
//  AppleAgentKit
//

import Foundation

internal struct HuggingFaceInstallationManifest: Codable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let modelID: String
  let repositoryID: String
  let requestedRevision: String
  let resolvedRevision: String
  let installedAt: Date
  let files: [String]

  init(
    modelID: String,
    repositoryID: String,
    requestedRevision: String,
    resolvedRevision: String,
    installedAt: Date,
    files: [String]
  ) {
    self.schemaVersion = Self.currentSchemaVersion
    self.modelID = modelID
    self.repositoryID = repositoryID
    self.requestedRevision = requestedRevision
    self.resolvedRevision = resolvedRevision
    self.installedAt = installedAt
    self.files = files
  }
}
