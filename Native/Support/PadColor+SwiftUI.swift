import SwiftUI

extension PadColor {
    var color: Color {
        switch self {
        case .off: Color.black
        case .darkRed: Color(red: 0.45, green: 0.10, blue: 0.10)
        case .red: Color(red: 0.86, green: 0.15, blue: 0.15)
        case .brightRed: Color(red: 1.00, green: 0.20, blue: 0.20)
        case .darkGreen: Color(red: 0.08, green: 0.30, blue: 0.16)
        case .green: Color(red: 0.09, green: 0.64, blue: 0.28)
        case .brightGreen: Color(red: 0.13, green: 0.86, blue: 0.35)
        case .darkAmber: Color(red: 0.46, green: 0.27, blue: 0.07)
        case .amber: Color(red: 0.82, green: 0.51, blue: 0.00)
        case .yellow: Color(red: 0.96, green: 0.72, blue: 0.02)
        case .orange: Color(red: 0.98, green: 0.36, blue: 0.04)
        }
    }
}
