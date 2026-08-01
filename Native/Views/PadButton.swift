import SwiftUI

struct PadButton: View {
    let pad: Pad
    let selected: Bool
    var circular = false
    var executeOnPress = false
    var displayColor: String?
    let action: () -> Void
    var runAction: (() -> Void)? = nil

    @State private var pressed = false

    var body: some View {
        Button {
            pressed = true
            action()
            if executeOnPress { runAction?() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
        } label: {
            VStack(spacing: 1) {
                if !pad.title.isEmpty || !pad.symbol.isEmpty {
                    Image(systemName: pad.symbol)
                        .font(.system(size: circular ? 15 : 14, weight: .medium))
                }
                if !pad.title.isEmpty {
                    Text(pad.title)
                        .font(.system(size: circular ? 8 : 9, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(3)
            .background {
                if circular {
                    Circle().fill(padColor)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(padColor)
                }
            }
            .overlay {
                if circular {
                    Circle().stroke(selected ? Color.orange : .white.opacity(0.18), lineWidth: selected ? 2 : 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.orange : .white.opacity(0.18), lineWidth: selected ? 2 : 1.5)
                }
            }
            .shadow(color: selected ? .orange.opacity(0.8) : (pad.idleColor == "off" ? .clear : padColor.opacity(0.62)), radius: selected ? 11 : 8)
            .scaleEffect(pressed ? 0.95 : (selected ? 1.035 : 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let runAction {
                Button("동작 실행", action: runAction)
            }
        }
    }

    private var padColor: Color {
        PadColor(rawValue: pressed ? pad.activeColor : (displayColor ?? pad.idleColor))?.color ?? .gray
    }
}
