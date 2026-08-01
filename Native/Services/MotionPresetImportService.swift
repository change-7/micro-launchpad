import Foundation

enum MotionPresetImportError: LocalizedError {
    case empty
    case malformed
    case missingName
    case invalidDuration
    case missingFrames
    case invalidCoordinate(frame: Int, row: Int, column: Int)
    case unsupportedColor(frame: Int, color: String)

    var errorDescription: String? {
        switch self {
        case .empty: "가져올 JSON을 붙여 넣으세요."
        case .malformed: "JSON 형식이 올바르지 않습니다. 안내 프롬프트의 출력 형식을 그대로 사용하세요."
        case .missingName: "프리셋 이름(name)이 필요합니다."
        case .invalidDuration: "frameDurationMs는 40~2000 사이의 숫자여야 합니다."
        case .missingFrames: "최소 한 개의 프레임이 필요합니다."
        case let .invalidCoordinate(frame, row, column): "\(frame)번 프레임의 좌표 (\(row), \(column))는 1~8 범위여야 합니다."
        case let .unsupportedColor(frame, color): "\(frame)번 프레임의 ‘\(color)’는 MK1에서 지원하지 않는 색상입니다."
        }
    }
}

enum MotionPresetImportService {
    /// Copy this together with a natural-language request to receive import-ready data.
    static let chatGPTPrompt = """
    당신은 Novation Launchpad Mini MK1용 8×8 LED 모션 디자이너입니다.
    중앙 8×8 그리드만 사용합니다. row 1은 위쪽, row 8은 아래쪽이며 column 1은 왼쪽, column 8은 오른쪽입니다.
    MK1은 RGB 장치가 아닙니다. 다음 색상 문자열만 사용하세요:
    off, darkRed, red, brightRed, darkGreen, green, brightGreen, darkAmber, amber, yellow, orange
    blue, purple, pink, white, cyan, lime은 절대 사용하지 마세요.
    복사하기 쉽도록 설명은 절대 쓰지 말고, 결과 JSON 전체를 반드시 json 코드박스 안에만 작성하세요.
    각 프레임에는 켜질 픽셀만 넣고, 없는 픽셀은 off입니다.

    {
      "name": "프리셋 이름",
      "loop": true,
      "frameDurationMs": 120,
      "frames": [
        { "pixels": [{ "row": 1, "column": 1, "color": "green" }] }
      ]
    }

    요청: 여기에 원하는 모션을 한국어로 작성
    """

    static func decode(_ text: String) throws -> MotionPreset {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MotionPresetImportError.empty }
        let json = stripCodeFence(from: trimmed)
        guard let data = json.data(using: .utf8), let draft = try? JSONDecoder().decode(Draft.self, from: data) else {
            throw MotionPresetImportError.malformed
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MotionPresetImportError.missingName }
        guard (40...2000).contains(draft.frameDurationMs) else { throw MotionPresetImportError.invalidDuration }
        guard !draft.frames.isEmpty else { throw MotionPresetImportError.missingFrames }

        let allowed = Set(PadColor.launchpadPalette.map(\.rawValue))
        for (frameIndex, frame) in draft.frames.enumerated() {
            for pixel in frame.pixels {
                guard (1...8).contains(pixel.row), (1...8).contains(pixel.column) else {
                    throw MotionPresetImportError.invalidCoordinate(frame: frameIndex + 1, row: pixel.row, column: pixel.column)
                }
                guard allowed.contains(pixel.color) else {
                    throw MotionPresetImportError.unsupportedColor(frame: frameIndex + 1, color: pixel.color)
                }
            }
        }

        return MotionPreset(name: name, loop: draft.loop, frameDurationMs: draft.frameDurationMs, frames: draft.frames)
    }

    private static func stripCodeFence(from text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        let lines = text.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return text }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    private struct Draft: Decodable {
        var name: String
        var loop: Bool
        var frameDurationMs: Int
        var frames: [MotionFrame]
    }
}
