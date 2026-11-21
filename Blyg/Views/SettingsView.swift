import SwiftUI

/// Appearance: Studio or System. Stored in UserDefaults under `appearance` (privacy manifest: CA92.1).
///
/// One source of truth: `ThemedRoot` reads the setting and hands the theme down. This screen shows the
/// theme it's given and only writes the setting. With its own `@AppStorage` reading the same key too, it
/// stopped redrawing after the first change, so later taps looked dead (Jenna, build 3).
struct SettingsView: View {
    @Environment(\.theme) private var theme
    private var appearance: Appearance { theme.appearance }

    var body: some View {
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
                            if appearance == choice {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
                            }
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
                Text("The same layout either way; this changes the type and colours. The share sheet always uses the System look.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
