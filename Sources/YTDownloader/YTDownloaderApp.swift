import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case traditionalChinese
    case japanese
    case korean

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .traditionalChinese: "language.chinese"
        case .japanese: "language.japanese"
        case .korean: "language.korean"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system, .english: "en"
        case .traditionalChinese: "zh-Hant"
        case .japanese: "ja"
        case .korean: "ko"
        }
    }

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let languageCode = identifier
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .first?
                .lowercased()
            switch languageCode {
            case "en": return .english
            case "zh": return .traditionalChinese
            case "ja": return .japanese
            case "ko": return .korean
            default: continue
            }
        }
        return .english
    }
}

@MainActor
@Observable
final class LanguageSettings {
    static let storageKey = "app.languagePreference"
    static let shared = LanguageSettings()

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var selectedLanguage: AppLanguage

    var activeLanguage: AppLanguage {
        selectedLanguage == .system
            ? AppLanguage.resolve(preferredLanguages: Locale.preferredLanguages)
            : selectedLanguage
    }

    var locale: Locale {
        Locale(identifier: activeLanguage.localeIdentifier)
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedLanguage = defaults.string(forKey: Self.storageKey)
            .flatMap(AppLanguage.init(rawValue:))
            ?? .system
    }

    func setLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        defaults.set(language.rawValue, forKey: Self.storageKey)
    }

    func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module, locale: locale)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
}

struct LanguageSettingsView: View {
    @Environment(LanguageSettings.self) private var languageSettings

    var body: some View {
        Form {
            Picker(
                languageSettings.string("settings.language"),
                selection: Binding(
                    get: { languageSettings.selectedLanguage },
                    set: { languageSettings.setLanguage($0) }
                )
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(languageSettings.string(language.titleKey))
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(24)
        .frame(width: 420, height: 150)
        .navigationTitle(languageSettings.string("settings.title"))
    }
}

@main
struct YouTubeDownloaderApp: App {
    @State private var languageSettings = LanguageSettings.shared
    @State private var viewModel = DownloaderViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(languageSettings)
                .environment(\.locale, languageSettings.locale)
        }
        .defaultSize(width: 1120, height: 720)

        Settings {
            LanguageSettingsView()
                .environment(languageSettings)
                .environment(\.locale, languageSettings.locale)
        }
    }
}
