import SwiftUI

/// A bento grid card for the dashboard, with icon, title, and content
struct BentoCardView<Content: View>: View {
    let icon: String
    let title: String
    let iconColor: Color
    @ViewBuilder var content: () -> Content

    init(
        icon: String,
        title: String,
        iconColor: Color = .accentColor,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.content = content
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: DSIconSize.md))
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(DSTypography.headline)
                        .lineLimit(1)
                }

                content()
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minHeight: 120)
    }
}
