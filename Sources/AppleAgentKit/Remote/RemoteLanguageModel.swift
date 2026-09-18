//
//  RemoteLanguageModel.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation
import FoundationModels

public protocol RemoteLanguageModel: LanguageModel {
    var baseURL: URL { get }
    var modelID: String { get }
}
