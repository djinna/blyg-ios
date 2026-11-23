import SwiftUI
import UIKit

/// Settings: the look (Studio or System), the color theme, and the home-screen icon.
/// Look and color are stored in UserDefaults under `appearance` and `colorTheme` (privacy manifest: CA92.1).
///
/// One source of truth: `ThemedRoot` reads the settings and hands the theme down. This screen shows the
/// theme it's given and only writes the settings. With its own `@AppStorage` reading the same key too, it
/// stopped redrawing after the first change, so later taps looked dead (Jenna, build 3).
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @State private var icon = AppIconChoice.current
    private var appearance: Appearance { theme.appearance }

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                ForEach(Appearance.allCases) { choice in
                    Button {
                        UserDefaults.standard.set(choice.rawValue, forKey: Appearance.storageKey)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(choice.title).font(.headline).foregroundStyle(.primary)
                                Text("The quick brown fox reads a blyg.")
                                    .font(Theme(appearance: choice).prose())
                                    .foregroundStyle(.primary)
                                Text(choice.summary).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            checkmark(appearance == choice)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(appearance == choice ? .isSelected : [])
                    .accessibilityIdentifier("appearance-\(choice.rawValue)")
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("The same layout either way; this changes the type. The share sheet always uses the System look.")
            }

            Section {
                ForEach(ColorTheme.allCases) { choice in
                    Button {
                        UserDefaults.standard.set(choice.rawValue, forKey: ColorTheme.storageKey)
                    } label: {
                        HStack(spacing: 12) {
                            swatch(choice)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.title).font(.headline).foregroundStyle(.primary)
                                Text(choice.summary).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            checkmark(theme.colors == choice)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(theme.colors == choice ? .isSelected : [])
                    .accessibilityIdentifier("colorTheme-\(choice.rawValue)")
                }
            } header: {
                Text("Color")
            } footer: {
                Text(appearance == .studio
                     ? "Colors for pages, text and links."
                     : "The System look keeps iPhone's colors and takes only the link color from here.")
            }

            if UIApplication.shared.supportsAlternateIcons {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 16) {
                        ForEach(AppIconChoice.allCases) { choice in
                            Button { choose(choice) } label: { iconTile(choice) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(choice.title)
                                .accessibilityAddTraits(icon == choice ? .isSelected : [])
                                .accessibilityIdentifier("appIcon-\(choice.rawValue)")
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("App icon")
                } footer: {
                    Text("iPhone confirms each change. Only Pencil blue changes with dark and tinted home screens; the others look the same in every mode.")
                }
                .id("appIcon")
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                    .accessibilityIdentifier("aboutVersion")
                Link("Help", destination: URL(string: "https://blyglet.com/")!)
                Link("Privacy", destination: URL(string: "https://blyglet.com/privacy.html")!)
                Link("Source code", destination: URL(string: "https://github.com/djinna/blyg-ios")!)
            }
        }
        #if DEBUG
        .task {
            // Screenshots: simctl can't scroll, so a launch flag brings the icon picker into view.
            guard LaunchFlags.has(LaunchFlags.showIcons) else { return }
            try? await Task.sleep(for: .milliseconds(400))
            proxy.scrollTo("appIcon", anchor: .top)
        }
        #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "0.1 (9)": the version and build number testers quote in feedback.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Always laid out, hidden when not chosen, so choosing a row doesn't re-wrap its text (Jenna, 2026-11-23).
    private func checkmark(_ shown: Bool) -> some View {
        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(true)
    }

    /// The theme's page with a line of its ink and a pencil underline, as the theme looks in the current mode
    /// (or always light or dark for Paper and Ink).
    private func swatch(_ choice: ColorTheme) -> some View {
        let p = choice.scheme == .dark ? choice.dark : choice.light
        return RoundedRectangle(cornerRadius: 8)
            .fill(Color(UIColor(hex: p.page)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(UIColor(hex: p.rule)), lineWidth: 1))
            .overlay {
                VStack(spacing: 3) {
                    Text("Aa").font(.system(size: 15, weight: .medium, design: .serif)).foregroundStyle(Color(UIColor(hex: p.ink)))
                    Capsule().fill(Color(UIColor(hex: p.pencil))).frame(width: 22, height: 3)
                }
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }

    private func iconTile(_ choice: AppIconChoice) -> some View {
        VStack(spacing: 6) {
            Image(choice.previewName)
                .resizable()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13.5, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(icon == choice ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2.5))
            Text(choice.title)
                .font(.caption2)
                .foregroundStyle(icon == choice ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .contentShape(.rect)
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != icon else { return }
        Task {
            do { try await UIApplication.shared.setAlternateIconName(choice.iconName) } catch {}
            icon = AppIconChoice.current
        }
    }
}
