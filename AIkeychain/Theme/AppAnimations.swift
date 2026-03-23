import SwiftUI

enum AppAnimations {
    static let transition: Animation = .spring(duration: 0.3)
    static let statusChange: Animation = .easeInOut(duration: 0.2)
    static let saveSuccess: Animation = .spring(duration: 0.5, bounce: 0.3)
}
