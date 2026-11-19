import CoreGraphics
import Foundation

private struct SpeakingNoteDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

enum SpeakingNoteLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case en, ru, es, fr, de

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return SL("English")
        case .ru: return SL("Russian")
        case .es: return SL("Spanish")
        case .fr: return SL("French")
        case .de: return SL("German")
        }
    }
}

enum SpeakingNoteMode: String, Codable, CaseIterable, Identifiable {
    case talkingPoints = "talking_points"
    case speech

    var id: String { rawValue }
}

enum SpeakingNoteTransformOperation: String, Encodable {
    case polish = "POLISH"
    case generateTitle = "GENERATE_TITLE"
    case generateSpeech = "GENERATE_SPEECH"
    case generateTalkingPoints = "GENERATE_TALKING_POINTS"
    case translate = "TRANSLATE"
}

/// A lossless representation of fields the current client does not understand yet.
enum SpeakingNoteJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: SpeakingNoteJSONValue])
    case array([SpeakingNoteJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: SpeakingNoteJSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([SpeakingNoteJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct SpeakingNotePoint: Codable, Equatable, Identifiable {
    var id: String
    var text: String
    var futureFields: [String: SpeakingNoteJSONValue]

    init(
        id: String = UUID().uuidString,
        text: String = "",
        futureFields: [String: SpeakingNoteJSONValue] = [:]
    ) {
        self.id = id
        self.text = text
        self.futureFields = futureFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpeakingNoteDynamicCodingKey.self)
        id = try container.decodeIfPresent(String.self, forKey: SpeakingNoteDynamicCodingKey(stringValue: "id")!) ?? UUID().uuidString
        text = try container.decodeIfPresent(String.self, forKey: SpeakingNoteDynamicCodingKey(stringValue: "text")!) ?? ""
        futureFields = [:]
        for key in container.allKeys where key.stringValue != "id" && key.stringValue != "text" {
            futureFields[key.stringValue] = try container.decode(SpeakingNoteJSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SpeakingNoteDynamicCodingKey.self)
        try container.encode(id, forKey: SpeakingNoteDynamicCodingKey(stringValue: "id")!)
        try container.encode(text, forKey: SpeakingNoteDynamicCodingKey(stringValue: "text")!)
        for (name, value) in futureFields {
            try container.encode(value, forKey: SpeakingNoteDynamicCodingKey(stringValue: name)!)
        }
    }
}

struct SpeakingNoteVariant: Codable, Equatable {
    var talkingPoints: [SpeakingNotePoint]
    var speech: String
    var futureFields: [String: SpeakingNoteJSONValue]

    init(
        talkingPoints: [SpeakingNotePoint] = [],
        speech: String = "",
        futureFields: [String: SpeakingNoteJSONValue] = [:]
    ) {
        self.talkingPoints = talkingPoints
        self.speech = speech
        self.futureFields = futureFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpeakingNoteDynamicCodingKey.self)
        talkingPoints = try container.decodeIfPresent([SpeakingNotePoint].self, forKey: SpeakingNoteDynamicCodingKey(stringValue: "talkingPoints")!) ?? []
        speech = try container.decodeIfPresent(String.self, forKey: SpeakingNoteDynamicCodingKey(stringValue: "speech")!) ?? ""
        futureFields = [:]
        for key in container.allKeys where key.stringValue != "talkingPoints" && key.stringValue != "speech" {
            futureFields[key.stringValue] = try container.decode(SpeakingNoteJSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SpeakingNoteDynamicCodingKey.self)
        try container.encode(talkingPoints, forKey: SpeakingNoteDynamicCodingKey(stringValue: "talkingPoints")!)
        try container.encode(speech, forKey: SpeakingNoteDynamicCodingKey(stringValue: "speech")!)
        for (name, value) in futureFields {
            try container.encode(value, forKey: SpeakingNoteDynamicCodingKey(stringValue: name)!)
        }
    }
}

struct SpeakingNoteContent: Codable, Equatable {
    var schemaVersion: Int
    var variants: [String: SpeakingNoteVariant]
    var futureFields: [String: SpeakingNoteJSONValue]

    init(
        schemaVersion: Int = 1,
        variants: [String: SpeakingNoteVariant] = [:],
        futureFields: [String: SpeakingNoteJSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.variants = variants
        self.futureFields = futureFields
    }

    subscript(language: SpeakingNoteLanguage) -> SpeakingNoteVariant {
        get { variants[language.rawValue] ?? SpeakingNoteVariant() }
        set { variants[language.rawValue] = newValue }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SpeakingNoteDynamicCodingKey.self)
        let schemaKey = SpeakingNoteDynamicCodingKey(stringValue: "schemaVersion")!
        let variantsKey = SpeakingNoteDynamicCodingKey(stringValue: "variants")!
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: schemaKey) ?? 1
        variants = try container.decodeIfPresent([String: SpeakingNoteVariant].self, forKey: variantsKey) ?? [:]
        futureFields = [:]
        for key in container.allKeys where key.stringValue != schemaKey.stringValue && key.stringValue != variantsKey.stringValue {
            futureFields[key.stringValue] = try container.decode(SpeakingNoteJSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SpeakingNoteDynamicCodingKey.self)
        try container.encode(schemaVersion, forKey: SpeakingNoteDynamicCodingKey(stringValue: "schemaVersion")!)
        try container.encode(variants, forKey: SpeakingNoteDynamicCodingKey(stringValue: "variants")!)
        for (name, value) in futureFields {
            try container.encode(value, forKey: SpeakingNoteDynamicCodingKey(stringValue: name)!)
        }
    }
}

struct SpeakingNoteListItem: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var activeLanguage: SpeakingNoteLanguage
    var activeMode: SpeakingNoteMode
    var revision: Int
    var lastUsedAt: String?
    var createdAt: String
    var updatedAt: String
}

struct SpeakingNote: Codable, Equatable, Identifiable {
    var id: String
    var workspaceId: String
    var title: String
    var activeLanguage: SpeakingNoteLanguage
    var activeMode: SpeakingNoteMode
    var content: SpeakingNoteContent
    var revision: Int
    var lastUsedAt: String?
    var createdAt: String
    var updatedAt: String
    var archivedAt: String?
    var deletedAt: String?

    var isLocal: Bool { id.hasPrefix("local-") }
    var activeVariant: SpeakingNoteVariant { content[activeLanguage] }
    var containsText: Bool {
        !activeVariant.speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || activeVariant.talkingPoints.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var listItem: SpeakingNoteListItem {
        SpeakingNoteListItem(
            id: id,
            title: title,
            activeLanguage: activeLanguage,
            activeMode: activeMode,
            revision: revision,
            lastUsedAt: lastUsedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func local(workspaceID: String) -> SpeakingNote {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return SpeakingNote(
            id: "local-\(UUID().uuidString)",
            workspaceId: workspaceID,
            title: "Untitled note",
            activeLanguage: .en,
            activeMode: .talkingPoints,
            content: SpeakingNoteContent(),
            revision: 1,
            lastUsedAt: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            archivedAt: nil,
            deletedAt: nil
        )
    }
}

struct MeetingSpeakingNoteSnapshot: Codable, Equatable {
    let meetingSessionId: String
    let speakingNoteId: String?
    let speakingNoteRevision: Int
    let title: String
    let activeLanguage: SpeakingNoteLanguage
    let activeMode: SpeakingNoteMode
    let content: SpeakingNoteContent
    let attachedAt: String
    let capturedAt: String
}

struct SpeakingNotesWindowState: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var collapsed: Bool
    var hidden: Bool

    static let defaultValue = SpeakingNotesWindowState(
        x: 420,
        y: 180,
        width: 520,
        height: 620,
        collapsed: false,
        hidden: true
    )
}

struct SpeakingNotesLocalDraft: Codable, Equatable {
    let authUserId: String
    var dirty: Bool
    var note: SpeakingNote?
    var updatedAt: String
    var window: SpeakingNotesWindowState
}
