import Foundation
import NaturalLanguage

struct SpeakingNoteLanguageDetection: Equatable, Sendable {
    let language: SpeakingNoteLanguage
    let confidence: Double
    let isReliable: Bool
}

struct SpeakingNoteLanguageDetector: Sendable {
    private static let minimumLetterCount = 8
    private static let maximumSampleLength = 8_000

    func detect(in text: String) -> SpeakingNoteLanguageDetection? {
        let sample = String(text.prefix(Self.maximumSampleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = sample.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard scalars.count >= Self.minimumLetterCount else { return nil }

        // The system recognizer is already very good for Russian, but this
        // deterministic check makes short Cyrillic notes reliable as well.
        let cyrillicCount = scalars.reduce(into: 0) { count, scalar in
            if (0x0400...0x052F).contains(scalar.value) { count += 1 }
        }
        if cyrillicCount >= 4, Double(cyrillicCount) / Double(scalars.count) >= 0.5 {
            return SpeakingNoteLanguageDetection(language: .ru, confidence: 0.99, isReliable: true)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let supportedHypotheses = recognizer
            .languageHypotheses(withMaximum: SpeakingNoteLanguage.allCases.count)
            .compactMap { language, confidence -> (SpeakingNoteLanguage, Double)? in
                guard let supportedLanguage = Self.supportedLanguage(for: language) else { return nil }
                return (supportedLanguage, confidence)
            }
            .sorted { $0.1 > $1.1 }

        guard let best = supportedHypotheses.first else { return nil }
        let runnerUpConfidence = supportedHypotheses.dropFirst().first?.1 ?? 0
        let isReliable = best.1 >= 0.55 && best.1 - runnerUpConfidence >= 0.12
        return SpeakingNoteLanguageDetection(
            language: best.0,
            confidence: best.1,
            isReliable: isReliable
        )
    }

    private static func supportedLanguage(for language: NLLanguage) -> SpeakingNoteLanguage? {
        switch language {
        case .english: return .en
        case .russian: return .ru
        case .spanish: return .es
        case .french: return .fr
        case .german: return .de
        default: return nil
        }
    }
}
