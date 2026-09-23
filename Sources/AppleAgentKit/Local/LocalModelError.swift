//
//  LocalModelError.swift
//  AppleAgentKit
//

import Foundation

public enum LocalModelError: Error, Hashable, Sendable {
  case unknownModel(String)
  case duplicateModelID(String)
  case invalidRepositoryID(String)
  case unavailableRevision(repositoryID: String, revision: String)
  case noMatchingFiles(String)
  case installationInProgress(String)
  case installationCancelled(String)
  case insufficientStorage(required: Int64, available: Int64)
  case invalidInstallation(String)
  case fileSystemFailure(String)
  case providerFailure(String)
}

extension LocalModelError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unknownModel(let id):
      return "No local model with ID '\(id)' is registered."

    case .duplicateModelID(let id):
      return "More than one local model uses the ID '\(id)'."

    case .invalidRepositoryID(let id):
      return "Hugging Face repository ID '\(id)' must use the owner/repository format."

    case .unavailableRevision(let repositoryID, let revision):
      return "Revision '\(revision)' is unavailable for Hugging Face repository '\(repositoryID)'."

    case .noMatchingFiles(let id):
      return
        "Hugging Face repository for model '\(id)' contains no files matching its artifact patterns."

    case .installationInProgress(let id):
      return "Model '\(id)' is already being installed."

    case .installationCancelled(let id):
      return "Installation of model '\(id)' was cancelled."

    case .insufficientStorage(let required, let available):
      return "The model requires \(required) bytes, but only \(available) bytes are available."

    case .invalidInstallation(let reason):
      return "The local model installation is invalid. \(reason)"

    case .fileSystemFailure(let message):
      return "Local model storage failed. \(message)"

    case .providerFailure(let message):
      return "The local model provider failed. \(message)"
    }
  }
}

extension LocalModelError: CustomStringConvertible {
  public var description: String {
    errorDescription ?? "Local model error."
  }
}
