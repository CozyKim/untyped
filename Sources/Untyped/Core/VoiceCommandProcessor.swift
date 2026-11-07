import Foundation

/// 명령 실패에는 받아쓰기 폴백이 없다. 지시문을 입력창에 붙여넣지 않는다.
@MainActor
enum VoiceCommandProcessor {
    enum Outcome: Equatable {
        case edited(String), submitted, failed(String)

        var notice: String {
            switch self {
            case .edited: "입력창 수정 완료"
            case .submitted: "Enter 전송됨"
            case .failed(let reason): reason
            }
        }
    }

    /// 대상 앱 활성화 전 원래 앱의 포커스를 확인한다. 조회 실패도 이동으로 취급한다.
    static func prepareTarget(
        originIsCurrent: (() -> Bool)?, activate: () async -> Bool
    ) async -> Bool {
        guard !Task.isCancelled, originIsCurrent?() == true else { return false }
        return await activate()
    }

    static func run(
        _ command: VoiceCommand, input: VoiceCommandInput?,
        edit: (String, String) async -> LLMTextResult
    ) async -> Outcome {
        guard let input else { return .failed(VoiceCommandInput.Result.unavailable.notice) }
        guard !Task.isCancelled else { return .failed(VoiceCommandInput.Result.cancelled.notice) }
        switch command {
        case .submit:
            let result = input.submit()
            return result == .completed ? .submitted : .failed(result.notice)
        case .edit(let instruction):
            guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failed("수정할 내용을 함께 말해주세요 — 예: 수정, 내일을 오늘로 바꿔")
            }
            guard input.isCurrent() else { return .failed(VoiceCommandInput.Result.changed.notice) }
            guard let text = input.text, !text.isEmpty else {
                return .failed("수정할 입력창 내용을 읽을 수 없음")
            }
            guard TextInserter.exactlyMatches(input.read(), text) else { return .failed(VoiceCommandInput.Result.changed.notice) }
            switch await edit(text, instruction) {
            case .failed(let reason): return .failed("\(reason.label) — 수정 안 함")
            case .text(let json):
                do {
                    let plan = try VoiceEditPlan.decode(json, original: text)
                    guard !plan.patches.isEmpty else { return .failed("수정할 부분을 특정할 수 없음 — 원문 유지") }
                    let result = await input.apply(plan)
                    return result == .completed ? .edited(plan.result) : .failed(input.failureReason() ?? result.notice)
                } catch let failure as VoiceEditPlan.Failure {
                    return .failed(failure.localizedDescription)
                } catch {
                    return .failed("수정 응답을 해석할 수 없음 — 원문 유지")
                }
            }
        }
    }
}
