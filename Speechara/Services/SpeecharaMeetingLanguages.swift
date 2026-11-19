import Foundation

private struct SpeecharaMeetingLanguageDescriptor: Sendable {
    let label: String
    let code: String
}

private enum SpeecharaMeetingLanguageCatalog {
    // Keep this list aligned with the web application's
    // deepgramRecognitionLanguageOptions. `multi` is recognition-only.
    static let webRecognitionOptions: [SpeecharaMeetingLanguageDescriptor] = [
        .init(label: "Auto · Multilingual", code: "multi"),
        .init(label: "Arabic", code: "ar"),
        .init(label: "Arabic (Algeria)", code: "ar-DZ"),
        .init(label: "Arabic (Chad)", code: "ar-TD"),
        .init(label: "Arabic (Egypt)", code: "ar-EG"),
        .init(label: "Arabic (Iran)", code: "ar-IR"),
        .init(label: "Arabic (Iraq)", code: "ar-IQ"),
        .init(label: "Arabic (Jordan)", code: "ar-JO"),
        .init(label: "Arabic (Kuwait)", code: "ar-KW"),
        .init(label: "Arabic (Lebanon)", code: "ar-LB"),
        .init(label: "Arabic (Morocco)", code: "ar-MA"),
        .init(label: "Arabic (Palestine)", code: "ar-PS"),
        .init(label: "Arabic (Qatar)", code: "ar-QA"),
        .init(label: "Arabic (Saudi Arabia)", code: "ar-SA"),
        .init(label: "Arabic (Sudan)", code: "ar-SD"),
        .init(label: "Arabic (Syria)", code: "ar-SY"),
        .init(label: "Arabic (Tunisia)", code: "ar-TN"),
        .init(label: "Arabic (United Arab Emirates)", code: "ar-AE"),
        .init(label: "Беларуская · Belarusian", code: "be"),
        .init(label: "বাংলা · Bengali", code: "bn"),
        .init(label: "Bosanski · Bosnian", code: "bs"),
        .init(label: "Български · Bulgarian", code: "bg"),
        .init(label: "Català · Catalan", code: "ca"),
        .init(label: "中文 · Chinese (Mandarin, Simplified)", code: "zh"),
        .init(label: "中文 · Chinese (Mandarin, Simplified, China)", code: "zh-CN"),
        .init(label: "中文 · Chinese (Mandarin, Simplified script)", code: "zh-Hans"),
        .init(label: "中文 · Chinese (Mandarin, Traditional, Taiwan)", code: "zh-TW"),
        .init(label: "中文 · Chinese (Mandarin, Traditional script)", code: "zh-Hant"),
        .init(label: "粵語 · Chinese (Cantonese, Hong Kong)", code: "zh-HK"),
        .init(label: "Hrvatski · Croatian", code: "hr"),
        .init(label: "Čeština · Czech", code: "cs"),
        .init(label: "Dansk · Danish", code: "da"),
        .init(label: "Dansk (Danmark)", code: "da-DK"),
        .init(label: "Nederlands · Dutch", code: "nl"),
        .init(label: "English", code: "en"),
        .init(label: "English (Australia)", code: "en-AU"),
        .init(label: "English (India)", code: "en-IN"),
        .init(label: "English (New Zealand)", code: "en-NZ"),
        .init(label: "English (United Kingdom)", code: "en-GB"),
        .init(label: "English (United States)", code: "en-US"),
        .init(label: "Eesti · Estonian", code: "et"),
        .init(label: "Suomi · Finnish", code: "fi"),
        .init(label: "Vlaams · Flemish", code: "nl-BE"),
        .init(label: "Français · French", code: "fr"),
        .init(label: "Français (Canada)", code: "fr-CA"),
        .init(label: "Deutsch · German", code: "de"),
        .init(label: "Deutsch (Schweiz)", code: "de-CH"),
        .init(label: "Ελληνικά · Greek", code: "el"),
        .init(label: "ગુજરાતી · Gujarati", code: "gu"),
        .init(label: "ગુજરાતી (ભારત) · Gujarati (India)", code: "gu-IN"),
        .init(label: "עברית · Hebrew", code: "he"),
        .init(label: "हिन्दी · Hindi", code: "hi"),
        .init(label: "Magyar · Hungarian", code: "hu"),
        .init(label: "Bahasa Indonesia", code: "id"),
        .init(label: "Italiano · Italian", code: "it"),
        .init(label: "日本語 · Japanese", code: "ja"),
        .init(label: "ಕನ್ನಡ · Kannada", code: "kn"),
        .init(label: "한국어 · Korean", code: "ko"),
        .init(label: "한국어 (대한민국) · Korean (South Korea)", code: "ko-KR"),
        .init(label: "Latviešu · Latvian", code: "lv"),
        .init(label: "Lietuvių · Lithuanian", code: "lt"),
        .init(label: "Македонски · Macedonian", code: "mk"),
        .init(label: "Bahasa Melayu · Malay", code: "ms"),
        .init(label: "मराठी · Marathi", code: "mr"),
        .init(label: "Norsk · Norwegian", code: "no"),
        .init(label: "فارسی · Persian", code: "fa"),
        .init(label: "Polski · Polish", code: "pl"),
        .init(label: "Português · Portuguese", code: "pt"),
        .init(label: "Português (Brasil)", code: "pt-BR"),
        .init(label: "Português (Portugal)", code: "pt-PT"),
        .init(label: "Română · Romanian", code: "ro"),
        .init(label: "Русский · Russian", code: "ru"),
        .init(label: "Српски · Serbian", code: "sr"),
        .init(label: "Slovenčina · Slovak", code: "sk"),
        .init(label: "Slovenščina · Slovenian", code: "sl"),
        .init(label: "Español · Spanish", code: "es"),
        .init(label: "Español (Latinoamérica)", code: "es-419"),
        .init(label: "Svenska · Swedish", code: "sv"),
        .init(label: "Svenska (Sverige)", code: "sv-SE"),
        .init(label: "Tagalog", code: "tl"),
        .init(label: "தமிழ் · Tamil", code: "ta"),
        .init(label: "తెలుగు · Telugu", code: "te"),
        .init(label: "ไทย · Thai", code: "th"),
        .init(label: "ไทย (ประเทศไทย) · Thai (Thailand)", code: "th-TH"),
        .init(label: "Türkçe · Turkish", code: "tr"),
        .init(label: "Українська · Ukrainian", code: "uk"),
        .init(label: "اردو · Urdu", code: "ur"),
        .init(label: "Tiếng Việt · Vietnamese", code: "vi"),
    ]

    static let recognitionOptions: [SpeecharaMeetingLanguageDescriptor] = {
        let autoAndEnglish = webRecognitionOptions.filter { $0.code == "multi" || $0.code == "en" }
        let remaining = webRecognitionOptions.filter { $0.code != "multi" && $0.code != "en" }
        return autoAndEnglish + remaining
    }()

    static let translationOptions = webRecognitionOptions.filter { $0.code != "multi" }

    static func descriptor(for code: String) -> SpeecharaMeetingLanguageDescriptor? {
        webRecognitionOptions.first { $0.code == code }
    }
}

struct SourceLanguageOption: RawRepresentable, CaseIterable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }

    static let multilingual = SourceLanguageOption(rawValue: "multi")
    static let english = SourceLanguageOption(rawValue: "en")
    static let russian = SourceLanguageOption(rawValue: "ru")
    static let german = SourceLanguageOption(rawValue: "de")
    static let spanish = SourceLanguageOption(rawValue: "es")
    static let french = SourceLanguageOption(rawValue: "fr")

    static let allCases = SpeecharaMeetingLanguageCatalog.recognitionOptions.map {
        SourceLanguageOption(rawValue: $0.code)
    }

    static func supported(code: String?) -> SourceLanguageOption? {
        guard let code else { return nil }
        return allCases.first { $0.rawValue == code }
    }

    var displayName: String {
        SpeecharaMeetingLanguageCatalog.descriptor(for: rawValue)?.label ?? rawValue
    }

    var deepgramLanguageCode: String { rawValue }

    var deepSeekLanguageName: String {
        self == .multilingual ? "the automatically detected meeting language" : displayName
    }

    var matchingTranslationLanguage: TranslationLanguageOption? {
        guard self != .multilingual else { return nil }
        return TranslationLanguageOption.supported(code: rawValue)
    }

    var summarizeButtonTitle: String { SL("Summarize") }
    var answerButtonTitle: String { SL("Suggest answer") }
    var protocolButtonTitle: String { SL("Meeting notes") }
    var answerPanelTitle: String { SL("Suggested answer") }
    var protocolPanelTitle: String { SL("Meeting notes") }
}

struct TranslationLanguageOption: RawRepresentable, CaseIterable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }

    static let english = TranslationLanguageOption(rawValue: "en")
    static let russian = TranslationLanguageOption(rawValue: "ru")
    static let german = TranslationLanguageOption(rawValue: "de")
    static let spanish = TranslationLanguageOption(rawValue: "es")
    static let french = TranslationLanguageOption(rawValue: "fr")

    static let allCases = SpeecharaMeetingLanguageCatalog.translationOptions.map {
        TranslationLanguageOption(rawValue: $0.code)
    }

    static func supported(code: String?) -> TranslationLanguageOption? {
        guard let code else { return nil }
        return allCases.first { $0.rawValue == code }
    }

    var displayName: String {
        SpeecharaMeetingLanguageCatalog.descriptor(for: rawValue)?.label ?? rawValue
    }

    var languageCode: String { rawValue }
    var deepSeekTargetLanguageName: String { displayName }
    var summarizeButtonTitle: String { SL("Summarize") }
    var answerButtonTitle: String { SL("Suggest answer") }
    var protocolButtonTitle: String { SL("Meeting notes") }
    var answerPanelTitle: String { SL("Suggested answer") }
    var protocolPanelTitle: String { SL("Meeting notes") }
}
