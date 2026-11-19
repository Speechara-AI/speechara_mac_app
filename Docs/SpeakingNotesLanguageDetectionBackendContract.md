# Speaking Notes language detection: backend contract

## Decision

The macOS client detects the language locally with Apple's `NaturalLanguage` framework. This is the primary path: it has no network latency or inference cost, and note text does not leave the device.

The backend operation below is an optional fallback for clients without a reliable on-device detector and for ambiguous input. It must not reuse `transformSpeakingNote`: detection is read-only, must not create a revision, and must not require the note to have been saved first.

## GraphQL schema

```graphql
extend type Mutation {
  detectSpeakingNoteLanguage(
    input: DetectSpeakingNoteLanguageInput!
  ): SpeakingNoteLanguageDetection!
}

input DetectSpeakingNoteLanguageInput {
  text: String!
  candidateLanguages: [String!]
}

type SpeakingNoteLanguageDetection {
  language: String
  confidence: Float!
  reliable: Boolean!
  alternatives: [SpeakingNoteLanguageCandidate!]!
  detector: String!
}

type SpeakingNoteLanguageCandidate {
  language: String!
  confidence: Float!
}
```

Although semantically read-only, this is a mutation because it may consume a rate-limited inference resource. It is exposed through the existing authenticated `/graphql` endpoint.

## Request semantics

- `text` is UTF-8, trimmed server-side, with a maximum of 8,000 Unicode characters.
- `candidateLanguages` is optional. If omitted, the Speaking Notes default is `['en', 'ru', 'es', 'fr', 'de']`.
- Language values are lowercase BCP 47 primary language subtags. The initial supported set is `en`, `ru`, `es`, `fr`, and `de`.
- Empty input and unsupported candidate codes return the existing GraphQL validation error shape with code `INVALID_SPEAKING_NOTE`.
- Normal authenticated rate limits apply; a rejected request uses code `RATE_LIMITED`.
- Detection never creates, updates, or attaches a speaking note and never changes its revision.
- Raw `text` must not be stored, included in analytics, or written to application logs.

## Response semantics

- `language` is `null` when the detector cannot make a supported guess.
- `confidence` is normalized to `0...1`; it is `0` when `language` is `null`.
- `reliable` is the server's decision that the result is safe to apply automatically.
- `alternatives` is sorted by descending confidence and contains only requested candidates.
- `detector` is a non-sensitive implementation/version identifier such as `cld3-v1`.

Example:

```graphql
mutation DetectSpeakingNoteLanguage($input: DetectSpeakingNoteLanguageInput!) {
  detectSpeakingNoteLanguage(input: $input) {
    language
    confidence
    reliable
    alternatives { language confidence }
    detector
  }
}
```

```json
{
  "input": {
    "text": "Привет, я хочу рассказать о своих обновлениях.",
    "candidateLanguages": ["en", "ru", "es", "fr", "de"]
  }
}
```

```json
{
  "data": {
    "detectSpeakingNoteLanguage": {
      "language": "ru",
      "confidence": 0.99,
      "reliable": true,
      "alternatives": [
        { "language": "ru", "confidence": 0.99 }
      ],
      "detector": "cld3-v1"
    }
  }
}
```

## Implementation guidance

Prefer a deterministic language-identification model such as CLD3 or fastText. GPT should be a last-resort fallback only: it adds cost and latency to a classification task and creates additional privacy considerations.

The client should call this operation only when it has enough text to classify and its local result is absent or unreliable. A manual language selection always wins. The client must only move content automatically when the destination variant is empty and the source is the note's only non-empty variant.

## Acceptance criteria

1. Russian, English, Spanish, French, and German samples return the matching supported code.
2. Short or mixed-language input may return `reliable: false` and is never applied automatically.
3. Detection does not mutate a note, increment a revision, or require a note ID.
4. Raw note text is absent from persistence, logs, traces, and analytics.
5. P95 latency for non-GPT detection is below 300 ms under normal load.
