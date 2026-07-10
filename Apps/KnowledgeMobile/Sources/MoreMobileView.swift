import SwiftUI

struct MoreMobileView: View {
    @EnvironmentObject var core: CoreClient

    var body: some View {
        NavigationStack {
            ZStack {
                KPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: KSpace.x6) {
                        Text("더보기")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(KColor.grey900)
                            .padding(.top, KSpace.x4)

                        Text("확인 · 검색 · 설정")
                            .font(.system(size: 15))
                            .foregroundStyle(KColor.grey500)

                        KCard(padded: false) {
                            VStack(spacing: 0) {
                                NavigationLink {
                                    ReviewMobileView()
                                } label: {
                                    rowLabel(
                                        title: "확인함",
                                        subtitle: core.reviewCount > 0 ? "저장 대기 \(core.reviewCount)건" : "비어 있어요",
                                        icon: "checkmark.circle.fill",
                                        trailing: core.reviewCount > 0 ? "\(core.reviewCount)" : nil
                                    )
                                }
                                Divider().padding(.leading, 56)
                                NavigationLink {
                                    InboxMobileView()
                                } label: {
                                    rowLabel(
                                        title: "인박스",
                                        subtitle: "빠른 메모 → Mac vault",
                                        icon: "tray.fill",
                                        trailing: core.inboxOpenCount > 0 ? "\(core.inboxOpenCount)" : nil
                                    )
                                }
                                Divider().padding(.leading, 56)
                                NavigationLink {
                                    WeekReviewMobileView()
                                } label: {
                                    rowLabel(
                                        title: "주간 리뷰",
                                        subtitle: core.streakDays > 0 ? "연속 \(core.streakDays)일" : "7일 요약",
                                        icon: "chart.bar.fill",
                                        trailing: nil
                                    )
                                }
                                Divider().padding(.leading, 56)
                                NavigationLink {
                                    SearchMobileView()
                                } label: {
                                    rowLabel(title: "검색", subtitle: "키워드로 찾기", icon: "magnifyingglass", trailing: nil)
                                }
                                Divider().padding(.leading, 56)
                                NavigationLink {
                                    SettingsMobileView()
                                } label: {
                                    rowLabel(title: "설정", subtitle: "연결 · 건강 · 페어링", icon: "gearshape.fill", trailing: nil)
                                }
                            }
                            .padding(.horizontal, KSpace.x4)
                        }
                    }
                    .padding(.horizontal, KSpace.x6)
                    .padding(.bottom, KSpace.x8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await core.refreshStatus() }
        }
    }

    private func rowLabel(title: String, subtitle: String, icon: String, trailing: String?) -> some View {
        HStack(spacing: KSpace.x3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(KColor.blue50).frame(width: 40, height: 40)
                Image(systemName: icon).foregroundStyle(KColor.blue500)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(KColor.grey900)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(KColor.grey500)
            }
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 13, weight: .semibold)).foregroundStyle(KColor.blue500)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(KColor.grey200)
        }
        .padding(.vertical, KSpace.x3)
    }
}
