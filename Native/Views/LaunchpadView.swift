import SwiftUI

struct LaunchpadView: View {
    let page: LaunchPage
    let pages: [LaunchPage]
    let activePage: Int
    let selectedPadID: String
    let midiConnected: Bool
    @Binding var virtualPreviewEnabled: Bool
    let motionFrame: MotionFrame?
    let gridOverlay: [String]?
    let onSelectPage: (Int) -> Void
    let onSelectPageLED: (Int) -> Void
    let onSelectPad: (Pad) -> Void
    let onRunPad: (Pad) -> Void
    let onVirtualPadPress: (Pad) -> Void
    let onMoveGridPad: (String, String) -> Void

    @State private var dropTargetPadID: String?

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 8
            let cell = min(44, max(34, (proxy.size.width - 48 - gap * 8) / 9))
            let gridWidth = cell * 9 + gap * 8

            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 5).fill(.orange).frame(width: 17, height: 17).shadow(color: .orange.opacity(0.7), radius: 6)
                    Text("NOVATION").font(.system(size: 18, weight: .bold))
                    Text("LAUNCHPAD MINI (MK1)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        virtualPreviewEnabled.toggle()
                    } label: {
                        Label(virtualPreviewEnabled ? "가상 작동" : "편집", systemImage: virtualPreviewEnabled ? "hand.tap.fill" : "slider.horizontal.3")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background((virtualPreviewEnabled ? Color.orange : Color.white.opacity(0.10)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Circle().fill(midiConnected ? .green : .gray).frame(width: 8, height: 8)
                }
                .foregroundStyle(.white)

                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        ForEach(0..<8, id: \.self) { index in
                            pageButton(index: index, size: cell)
                        }
                        Text("CC").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: cell, height: cell)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 9), spacing: gap) {
                        ForEach(0..<72, id: \.self) { slot in
                            let row = slot / 9
                            let column = slot % 9
                            if column == 8 {
                                let side = page.pads.first(where: { $0.id == "side_\(row)" }) ?? Pad(id: "side_\(row)", title: PadDefaults.sideTitles[row], symbol: PadDefaults.sideSymbols[row])
                                PadButton(pad: side, selected: side.id == selectedPadID, circular: true, executeOnPress: virtualPreviewEnabled, action: {
                                    virtualPreviewEnabled ? onVirtualPadPress(side) : onSelectPad(side)
                                }, runAction: { onRunPad(side) })
                                    .frame(width: cell, height: cell)
                            } else {
                                let pad = page.pads[row * 8 + column]
                                gridPadButton(pad, row: row, column: column, size: cell)
                            }
                        }
                    }
                }
                .frame(width: gridWidth)

                HStack {
                    Text("MODEL: NOVATION L_PAD_MINI_MK1").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary.opacity(0.55))
                    Spacer()
                    Circle().fill(.orange).frame(width: 7, height: 7)
                    Text("64 GRID + 16 CC").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary.opacity(0.55))
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Color(red: 0.11, green: 0.11, blue: 0.14), in: RoundedRectangle(cornerRadius: 36))
            .overlay(RoundedRectangle(cornerRadius: 36).stroke(.black.opacity(0.9), lineWidth: 4))
        }
        .frame(minHeight: 620)
    }

    @ViewBuilder
    private func gridPadButton(_ pad: Pad, row: Int, column: Int, size: CGFloat) -> some View {
        let button = PadButton(
            pad: pad,
            selected: pad.id == selectedPadID,
            executeOnPress: virtualPreviewEnabled,
            displayColor: motionColor(row: row, column: column),
            action: { virtualPreviewEnabled ? onVirtualPadPress(pad) : onSelectPad(pad) },
            runAction: { onRunPad(pad) }
        )
        .frame(width: size, height: size)
        .overlay {
            if dropTargetPadID == pad.id {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow, lineWidth: 3)
            }
        }

        if virtualPreviewEnabled {
            button
        } else {
            button
                .draggable(pad.id) {
                    Label(pad.title.isEmpty ? "빈 버튼" : pad.title, systemImage: pad.symbol.isEmpty ? "square" : pad.symbol)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .dropDestination(for: String.self) { sourceIDs, _ in
                    guard let sourceID = sourceIDs.first,
                          sourceID.hasPrefix("grid_") else { return false }
                    onMoveGridPad(sourceID, pad.id)
                    return sourceID != pad.id
                } isTargeted: { isTargeted in
                    dropTargetPadID = isTargeted ? pad.id : nil
                }
        }
    }

    private func pageButton(index: Int, size: CGFloat) -> some View {
        let active = index == activePage
        let pageColor = PadColor(rawValue: pages[index].topButtonColor(isSelected: active))?.color ?? .black
        return Button {
            onSelectPage(index)
            if !virtualPreviewEnabled {
                onSelectPageLED(index)
            }
        } label: {
            Text("P\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: size, height: size)
                .foregroundStyle(active ? .white : .white.opacity(0.6))
                .background(pageColor.opacity(active ? 1 : 0.36), in: Circle())
                .overlay(Circle().stroke(active ? Color.orange : pageColor.opacity(0.58), lineWidth: active ? 2 : 1.5))
                .shadow(color: active ? pageColor.opacity(0.85) : .clear, radius: 11)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func motionColor(row: Int, column: Int) -> String? {
        if let motionFrame {
            return motionFrame.pixels.first(where: { $0.row == row + 1 && $0.column == column + 1 })?.color ?? "off"
        }
        return gridOverlay?[row * 8 + column]
    }
}
