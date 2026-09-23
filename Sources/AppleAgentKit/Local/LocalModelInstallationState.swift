//
//  LocalModelInstallationState.swift
//  AppleAgentKit
//

public enum LocalModelInstallationState: Hashable, Sendable {
  case notInstalled
  case downloading(LocalModelDownloadProgress)
  case installed(LocalModelInstallation)
  case updateAvailable(
    installed: LocalModelInstallation,
    availableRevision: String
  )
  case invalid(String)
}
