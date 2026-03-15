import SwiftUI

/// A reusable settings row with icon, label, and optional trailing content
struct SettingRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String,
        iconColor: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: DSIconSize.md))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DSTypography.body)
                if let subtitle {
                    Text(subtitle)
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            trailing()
        }
        .contentShape(Rectangle())
    }
}
