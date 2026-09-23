//
//  LocalModel.swift
//  AppleAgentKit
//

import Foundation

public protocol LocalModel: Identifiable, Hashable, Sendable where ID == String {
  var displayName: String { get }
  var expectedDownloadSize: Int64? { get }
  var compatibility: LocalModelCompatibility { get }
}

public struct LocalModelCompatibility: Hashable, Codable, Sendable {
  public enum Runtime: String, Hashable, Codable, Sendable {
    case coreAI
  }

  public let runtime: Runtime
  public let formatVersion: String?

  public init(
    runtime: Runtime,
    formatVersion: String? = nil
  ) {
    self.runtime = runtime
    self.formatVersion = formatVersion
  }

  public static let coreAI = LocalModelCompatibility(
    runtime: .coreAI
  )
}
