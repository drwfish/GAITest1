import Foundation
import Combine

@MainActor
final class KillSwitch: ObservableObject {
    @Published private(set) var active: Bool = false
    @Published private(set) var activatedAt: Date? = nil
    @Published private(set) var reason: String? = nil
    @Published private(set) var actor: String? = nil

    func activate(reason: String, actor: String) {
        active = true
        self.reason = reason
        self.actor = actor
        activatedAt = Date()
    }

    func clear(actor: String) {
        active = false
        self.actor = actor
        reason = nil
        activatedAt = nil
    }
}
