import UIKit

/// The home-screen icons a person can choose in Settings. `scripts/make-icon.swift` draws them all: the
/// default set (light, dark and tinted) and one light-only alternate set per palette, named
/// `AppIcon-<name>`, plus a small preview of each in `IconPreviews/`. Keep the two lists in step.
/// The build setting ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS puts the alternates in Info.plist.
nonisolated enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case pencilBlue = "PencilBlue"
    case paper = "Paper"
    case ink = "Ink"
    case sky = "Sky"
    case pigletPink = "PigletPink"
    case pigletPinkOnWhite = "PigletPinkOnWhite"
    case pencilBluePinkCurl = "PencilBluePinkCurl"
    case pencilBlueCoralCurl = "PencilBlueCoralCurl"
    case warmPigPink = "WarmPigPink"
    case coral = "Coral"
    case moss = "Moss"
    case butter = "Butter"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pencilBlue: "Pencil blue"
        case .paper: "Paper"
        case .ink: "Ink"
        case .sky: "Sky"
        case .pigletPink: "Piglet pink"
        case .pigletPinkOnWhite: "Pink on white"
        case .pencilBluePinkCurl: "Blue, pink curl"
        case .pencilBlueCoralCurl: "Blue, coral curl"
        case .warmPigPink: "Warm pink"
        case .coral: "Coral"
        case .moss: "Moss"
        case .butter: "Butter"
        }
    }

    /// The alternate icon's name for `setAlternateIconName`; nil for the default icon.
    var iconName: String? { self == .pencilBlue ? nil : "AppIcon-\(rawValue)" }

    /// The asset catalog preview shown in Settings.
    var previewName: String { "IconPreviews/\(rawValue)" }

    /// The choice matching the icon the app is showing now.
    @MainActor static var current: AppIconChoice {
        allCases.first { $0.iconName == UIApplication.shared.alternateIconName } ?? .pencilBlue
    }
}
