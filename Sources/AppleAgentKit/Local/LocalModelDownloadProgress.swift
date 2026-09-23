//
//  LocalModelDownloadProgress.swift
//  AppleAgentKit
//

import Foundation

public struct LocalModelDownloadProgress: Hashable, Sendable {
  public enum Phase: String, Hashable, Sendable {
    case preparing
    case downloading
    case installing
  }

  public let phase: Phase
  public let receivedBytes: Int64
  public let totalBytes: Int64?

  public init(
    phase: Phase,
    receivedBytes: Int64 = 0,
    totalBytes: Int64? = nil
  ) {
    self.phase = phase
    self.receivedBytes = receivedBytes
    self.totalBytes = totalBytes
  }

  public var fractionCompleted: Double? {
    guard let totalBytes,
      totalBytes > 0
    else {
      return nil
    }

    return min(
      max(Double(receivedBytes) / Double(totalBytes), 0),
      1
    )
  }
}
