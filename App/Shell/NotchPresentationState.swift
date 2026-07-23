//
//  NotchPresentationState.swift
//

import SwiftUI
import VoidNotchKit

@MainActor
@Observable
final class NotchAgentAlertState {
    var event: AgentActivityEvent?
    var submit: ((AgentInputRequest, [Int: Set<String>]) -> String?)?
}

enum NotchPresentation {
    case compact
    case expanded
    case hidden
}
