import SwiftUI

struct OnboardingView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(AppState.self) private var appState
    @State private var currentPage = 0

    private let pages: [(icon: String, titleKey: String, descKey: String, color: Color)] = [
        ("bubble.left.and.bubble.right.fill", "onboarding_welcome", "onboarding_welcome_desc", .blue),
        ("person.2.fill", "onboarding_chat", "onboarding_chat_desc", .purple),
        ("paintbrush.fill", "onboarding_customize", "onboarding_customize_desc", .orange),
        ("checkmark.circle.fill", "onboarding_done", "onboarding_done_desc", .green),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                if currentPage < pages.count - 1 {
                    Button(localization.t("onboarding_skip")) {
                        appState.completeOnboarding()
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                }
            }

            Spacer()

            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: DSSpacing.xl) {
                        // Icon with layered circle backdrop
                        ZStack {
                            Circle()
                                .fill(page.color.opacity(0.1))
                                .frame(width: 160, height: 160)
                            Circle()
                                .fill(page.color.opacity(0.15))
                                .frame(width: 110, height: 110)
                            Image(systemName: page.icon)
                                .font(.system(size: 52))
                                .foregroundStyle(page.color)
                                .symbolEffect(.bounce, value: currentPage == index)
                        }

                        VStack(spacing: DSSpacing.sm) {
                            Text(localization.t(page.titleKey))
                                .font(DSTypography.title1)
                                .multilineTextAlignment(.center)

                            Text(localization.t(page.descKey))
                                .font(DSTypography.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, DSSpacing.xxl)
                        }
                    }
                    .tag(index)
                }
            }
#if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
#endif

            Spacer()

            // Pill-shaped page indicator
            HStack(spacing: DSSpacing.xs) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentPage)
                }
            }
            .padding(.bottom, DSSpacing.lg)

            // Navigation buttons
            HStack(spacing: DSSpacing.md) {
                if currentPage > 0 {
                    Button {
                        withAnimation(.spring(response: 0.35)) { currentPage -= 1 }
                    } label: {
                        Text(localization.t("onboarding_back"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation(.spring(response: 0.35)) { currentPage += 1 }
                    } else {
                        appState.completeOnboarding()
                    }
                } label: {
                    Text(currentPage < pages.count - 1
                         ? localization.t("onboarding_next")
                         : localization.t("onboarding_get_started"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.bottom, DSSpacing.xxl)
        }
    }
}
