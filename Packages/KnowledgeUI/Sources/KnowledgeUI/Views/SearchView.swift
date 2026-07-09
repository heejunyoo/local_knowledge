import SwiftUI

/// Search — field + results only.
public struct SearchView: View {
    @ObservedObject public var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            TossColor.grey100.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(TossColor.grey900)
                            .frame(width: 40, height: 44)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(TossColor.grey500)
                        TextField("검색", text: $model.searchQuery)
                            .font(.system(size: 17))
                            .focused($focused)
                            .onSubmit { model.runSearch() }
                        if model.isSearching {
                            ProgressView().controlSize(.small)
                        } else if !model.searchQuery.isEmpty {
                            Button {
                                model.searchQuery = ""
                                model.searchHits = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(TossColor.grey200)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(TossColor.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, TossSpace.x4)
                .padding(.bottom, TossSpace.x3)

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.searchHits.isEmpty {
                            Group {
                                if model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    emptyIdle
                                } else if model.isSearching {
                                    ProgressView("찾는 중…")
                                        .controlSize(.regular)
                                } else {
                                    emptyNoResults
                                }
                            }
                                .padding(.top, TossSpace.x8)
                                .padding(.horizontal, TossSpace.x6)
                        } else {
                            ForEach(model.searchHits.prefix(30)) { hit in
                                Button {
                                    model.openSearchHit(hit)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(hit.title)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(TossColor.grey900)
                                            .lineLimit(1)
                                        if !hit.snippet.isEmpty {
                                            Text(hit.snippet)
                                                .font(.system(size: 14))
                                                .foregroundStyle(TossColor.grey500)
                                                .lineLimit(2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, TossSpace.x6)
                                    .padding(.vertical, 16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                                    .overlay(TossColor.grey200)
                                    .padding(.leading, TossSpace.x6)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            focused = true
            if !model.searchQuery.isEmpty {
                model.runSearch()
            }
        }
    }

    private var emptyIdle: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("무엇을 찾을까요?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(TossColor.grey900)
            Text("미팅, 메모, 노트 이름을 검색해 보세요.")
                .font(.system(size: 16))
                .foregroundStyle(TossColor.grey700)
            if model.corpusTotalUnits == 0 {
                Text("아직 연결된 지식이 없어요. 지식 연결에서 동기화해 주세요.")
                    .font(.system(size: 14))
                    .foregroundStyle(TossColor.grey500)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyNoResults: some View {
        VStack(alignment: .leading, spacing: TossSpace.x3) {
            Text("결과가 없어요")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(TossColor.grey900)
            Text("다른 단어로 시도해 보세요. 지식 연결을 다시 동기화하면 새로 추가된 노트가 반영돼요.")
                .font(.system(size: 16))
                .foregroundStyle(TossColor.grey700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
