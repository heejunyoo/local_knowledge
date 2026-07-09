import Foundation

/// Top-level destinations from hub Home. New features = new cases + hub cards.
public enum AppRoute: String, Hashable, CaseIterable, Identifiable, Sendable {
    case record
    case chat
    case library
    case review
    case search
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .record: return "녹음"
        case .chat: return "물어보기"
        case .library: return "지식 연결"
        case .review: return "확인함"
        case .search: return "찾아보기"
        case .settings: return "설정"
        }
    }

    public var subtitle: String {
        switch self {
        case .record: return "회의 소리 남기기"
        case .chat: return "지식에 질문하기"
        case .library: return "메모·폴더 연결"
        case .review: return "요약 확인 후 저장"
        case .search: return "키워드 검색"
        case .settings: return "보관·저장 위치"
        }
    }

    public var systemImage: String {
        switch self {
        case .record: return "waveform.circle.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .library: return "folder.fill"
        case .review: return "checkmark.circle.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}
