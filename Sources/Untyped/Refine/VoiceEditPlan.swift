import Foundation

/// 모델은 원문 조각과 교체 문구만 고른다. 위치와 나머지 내용은 앱이 원문에서 계산한다.
struct VoiceEditPlan {
    struct Response: Decodable {
        struct Edit: Decodable { let old: String; let new: String }
        let edits: [Edit]
    }

    struct Patch: Equatable {
        let range: NSRange
        let replacement: String
    }

    enum Failure: Error, Equatable, LocalizedError {
        case emptyAnchor, missingAnchor, ambiguousAnchor, overlappingEdits, invalidBoundary

        var errorDescription: String? {
            switch self {
            case .emptyAnchor: "수정할 원문이 비어 있음 — 원문 유지"
            case .missingAnchor: "수정할 부분이 입력창과 일치하지 않음 — 원문 유지"
            case .ambiguousAnchor: "같은 문구가 여러 곳에 있음 — 주변 문장을 포함해 다시 지시해주세요"
            case .overlappingEdits: "수정 범위가 겹침 — 원문 유지"
            case .invalidBoundary: "수정 범위가 글자 경계를 나눔 — 원문 유지"
            }
        }
    }

    let original: String
    /// 원문 기준, 뒤에서부터 적용할 최소 범위들.
    let patches: [Patch]
    let result: String

    private init(original: String, patches: [Patch], result: String) {
        self.original = original
        self.patches = patches
        self.result = result
    }

    static func decode(_ json: String, original: String) throws -> Self {
        let response = try JSONDecoder().decode(Response.self, from: Data(json.utf8))
        let source = original as NSString
        var anchorRanges: [NSRange] = []
        var patches: [Patch] = []
        for edit in response.edits {
            guard !edit.old.isEmpty else { throw Failure.emptyAnchor }
            let range = source.range(of: edit.old, options: .literal)
            guard range.location != NSNotFound else { throw Failure.missingAnchor }
            // +1로 찾아 겹치는 중복('aaa'의 'aa')도 모호한 것으로 판정한다.
            let remaining = NSRange(location: range.location + 1, length: source.length - range.location - 1)
            guard source.range(of: edit.old, options: .literal, range: remaining).location == NSNotFound else {
                throw Failure.ambiguousAnchor
            }
            guard source.rangeOfComposedCharacterSequences(for: range) == range else { throw Failure.invalidBoundary }
            guard !anchorRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else {
                throw Failure.overlappingEdits
            }
            anchorRanges.append(range)

            let old = Array(edit.old)
            let new = Array(edit.new)
            var prefix = 0
            while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < min(old.count, new.count) - prefix,
                  old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
            let removed = String(old[prefix..<(old.count - suffix)])
            let replacement = String(new[prefix..<(new.count - suffix)])
            guard !removed.isEmpty || !replacement.isEmpty else { continue }
            let patch = Patch(
                range: NSRange(location: range.location + String(old[..<prefix]).utf16.count, length: removed.utf16.count),
                replacement: replacement
            )
            // 이웃한 두 anchor가 같은 경계에 삽입하려는 경우도 순서가 모호하다.
            guard !patches.contains(where: {
                $0.range.location == patch.range.location || NSIntersectionRange($0.range, patch.range).length > 0
            }) else { throw Failure.overlappingEdits }
            patches.append(patch)
        }
        patches.sort { $0.range.location > $1.range.location }
        var result = original
        for patch in patches {
            result = (result as NSString).replacingCharacters(in: patch.range, with: patch.replacement)
        }
        return Self(original: original, patches: patches, result: result)
    }
}
