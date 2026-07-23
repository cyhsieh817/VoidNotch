//
//  AgentInputQuestion.swift — isolated agent question models
//

import Foundation

public struct AgentInputOption: Sendable, Equatable {
    public let label: String
    public let description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct AgentInputQuestion: Sendable, Equatable {
    public let question: String
    public let header: String
    public let options: [AgentInputOption]
    public let multiSelect: Bool

    public init(question: String, header: String, options: [AgentInputOption], multiSelect: Bool) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}
