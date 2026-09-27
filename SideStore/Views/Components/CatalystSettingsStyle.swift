//
//  CatalystSettingsStyle.swift
//  Catalyst
//
//  Small building blocks so Catalyst's SwiftUI settings screens look like the rest of
//  Settings (uppercase section headers, rounded 50pt rows, dividers, settings background).
//

import SwiftUI

enum CatalystSettingsStyle {
    static let rowBackground = Color.white.opacity(0.15)
    static let divider = Color.white.opacity(0.15)
    static let secondaryText = Color.white.opacity(0.6)
    static let background = Color(uiColor: .settingsBackground)
}

struct CatalystSettingsSection<Content: View>: View {
    let header: String
    var footer: String? = nil
    var footerColor: Color = CatalystSettingsStyle.secondaryText
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CatalystSettingsStyle.secondaryText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(CatalystSettingsStyle.rowBackground)
            .cornerRadius(14)

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 13))
                    .foregroundColor(footerColor)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CatalystSettingsDivider: View {
    var body: some View {
        Divider()
            .background(CatalystSettingsStyle.divider)
            .padding(.horizontal, 16)
    }
}

/// A 50pt settings row: optional icon, bold title, optional trailing value, optional chevron/checkmark.
struct CatalystSettingsRow: View {
    let title: String
    var icon: String? = nil
    var value: String? = nil
    var showsChevron = false
    var isChecked = false
    var titleColor: Color = .white

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundColor(CatalystSettingsStyle.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}
