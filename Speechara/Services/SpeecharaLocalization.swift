import Foundation
import ObjectiveC.runtime

enum SpeecharaAppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"
    case german = "de"
    case spanish = "es"
    case french = "fr"

    var id: String { rawValue }

    var localeIdentifier: String { rawValue }

    var pickerDisplayName: String {
        switch self {
        case .english:
            return "English"
        case .russian:
            return "Русский"
        case .german:
            return "Deutsch"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        }
    }

    static func resolvedDefault(from preferredLanguages: [String] = Locale.preferredLanguages) -> SpeecharaAppLanguage {
        for identifier in preferredLanguages {
            let lowercased = identifier.lowercased()

            if lowercased.hasPrefix("ru") {
                return .russian
            }

            if lowercased.hasPrefix("de") {
                return .german
            }

            if lowercased.hasPrefix("es") {
                return .spanish
            }

            if lowercased.hasPrefix("fr") {
                return .french
            }

            if lowercased.hasPrefix("en") {
                return .english
            }
        }

        return .english
    }
}

final class SpeecharaLocalizationStore: ObservableObject {
    static let shared = SpeecharaLocalizationStore()

    private static let defaultsKey = "speechara.uiLanguage"
    private static var didInstallBundleOverride = false

    @Published private(set) var language: SpeecharaAppLanguage

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let savedLanguage = defaults.string(forKey: Self.defaultsKey),
           let resolvedLanguage = SpeecharaAppLanguage(rawValue: savedLanguage) {
            language = resolvedLanguage
        } else {
            language = SpeecharaAppLanguage.resolvedDefault()
        }
    }

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    func installBundleOverrideIfNeeded() {
        guard !Self.didInstallBundleOverride else {
            return
        }

        guard let originalMethod = class_getInstanceMethod(Bundle.self, #selector(Bundle.localizedString(forKey:value:table:))),
              let swizzledMethod = class_getInstanceMethod(Bundle.self, #selector(Bundle.speechara_localizedString(forKey:value:table:))) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
        Self.didInstallBundleOverride = true
    }

    func setLanguage(_ language: SpeecharaAppLanguage) {
        guard self.language != language else {
            return
        }

        self.language = language
        defaults.set(language.rawValue, forKey: Self.defaultsKey)
    }

    func localized(_ key: String) -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return key
        }

        return Self.translations[language]?[trimmedKey] ?? key
    }

    func localizedFormat(_ key: String, _ arguments: [CVarArg]) -> String {
        let format = localized(key)
        return String(format: format, locale: locale, arguments: arguments)
    }

    func localizedLanguageName(for languageOption: SpeecharaAppLanguage) -> String {
        switch language {
        case .english:
            switch languageOption {
            case .english: return "English"
            case .russian: return "Russian"
            case .german: return "German"
            case .spanish: return "Spanish"
            case .french: return "French"
            }
        case .russian:
            switch languageOption {
            case .english: return "Английский"
            case .russian: return "Русский"
            case .german: return "Немецкий"
            case .spanish: return "Испанский"
            case .french: return "Французский"
            }
        case .german:
            switch languageOption {
            case .english: return "Englisch"
            case .russian: return "Russisch"
            case .german: return "Deutsch"
            case .spanish: return "Spanisch"
            case .french: return "Französisch"
            }
        case .spanish:
            switch languageOption {
            case .english: return "Inglés"
            case .russian: return "Ruso"
            case .german: return "Alemán"
            case .spanish: return "Español"
            case .french: return "Francés"
            }
        case .french:
            switch languageOption {
            case .english: return "Anglais"
            case .russian: return "Russe"
            case .german: return "Allemand"
            case .spanish: return "Espagnol"
            case .french: return "Français"
            }
        }
    }

    private static let translations: [SpeecharaAppLanguage: [String: String]] = [
        .russian: [
            "Settings": "Настройки",
            "Settings...": "Настройки...",
            "Appearance": "Оформление",
            "Theme": "Тема",
            "Language": "Язык",
            "App language": "Язык приложения",
            "Choose how Speechara looks and reads. Changes apply immediately.": "Выберите тему и язык интерфейса Speechara. Изменения применяются сразу.",
            "Switches the whole app between Light, Dark, or the current macOS appearance. Changes apply immediately.": "Переключает всё приложение между светлой, тёмной и системной темой. Изменения применяются сразу.",
            "Changes the entire app UI between English, Russian, German, Spanish, and French.": "Переключает весь интерфейс приложения между английским, русским, немецким, испанским и французским языками.",
            "System": "Системная",
            "Light": "Светлая",
            "Dark": "Тёмная",
            "Workspace": "Рабочая зона",
            "Profile": "Профиль",
            "History": "История",
            "Sign out": "Выйти",
            "Sign In": "Вход",
            "Use Google, Microsoft, Apple, or a Speechara email/password account.": "Используйте Google, Microsoft, Apple или аккаунт Speechara с email/паролем.",
            "Connect your Google account to unlock the full Speechara desktop workflow.": "Подключите аккаунт Google, чтобы открыть полный desktop-сценарий Speechara.",
            "Waiting for Google…": "Ожидание Google…",
            "Continue with Google": "Продолжить с Google",
            "Waiting for Apple...": "Ожидание Apple...",
            "Continue with Apple": "Продолжить с Apple",
            "Complete Apple sign-in in the system prompt.": "Завершите вход через Apple в системном окне.",
            "Cancel sign-in": "Отменить вход",
            "By continuing, you allow Speechara to create a desktop session for your account.": "Продолжая, вы разрешаете Speechara создать desktop-сессию для вашего аккаунта.",
            "Your login expired. Sign in again to continue.": "Сессия истекла. Войдите снова, чтобы продолжить.",
            "Auth settings": "Настройки авторизации",
            "Restoring your session…": "Восстанавливаем сессию…",
            "Show Preview": "Показать превью",
            "New Session": "Новая сессия",
            "Focus Mode": "Фокус-режим",
            "Exit Focus": "Выйти из фокуса",
            "Saved audio": "Сохранённое аудио",
            "Off": "Выкл",
            "Input": "Вход",
            "Translation": "Перевод",
            "Live transcript preview": "Превью транскрипта",
            "Hide live transcript preview": "Скрыть превью транскрипта",
            "Live transcript": "Транскрипт",
            "Suggested response": "Подсказка ответа",
            "Copy": "Копировать",
            "Copy transcript": "Скопировать транскрипт",
            "Transcribe": "Транскрипт",
            "Translate": "Перевод",
            "Summarize": "Сделать саммари",
            "Clear subtitles": "Очистить субтитры",
            "Hide panel": "Скрыть панель",
            "Open": "Открыть",
            "Opening…": "Открываем…",
            "Load more": "Загрузить ещё",
            "Loading more…": "Загружаем ещё…",
            "Retry": "Повторить",
            "Refresh list": "Обновить список",
            "No history yet": "Истории пока нет",
            "Saved meeting sessions will appear here as soon as they are available in the backend.": "Сохранённые сессии появятся здесь, как только станут доступны в backend.",
            "This page loads saved meeting sessions from the backend and shows a compact overview. Open any card to inspect the full transcript, translation, summary, protocol, and suggested reply.": "Эта страница загружает сохранённые сессии из backend и показывает краткий обзор. Откройте карточку, чтобы увидеть полный транскрипт, перевод, саммари, протокол и подсказку ответа.",
            "Search transcript, translation, summary, or protocol": "Искать по транскрипту, переводу, саммари или протоколу",
            "Loading session history…": "Загружаем историю сессий…",
            "Preview text is not available yet.": "Превью текста пока недоступно.",
            "Translation on": "Перевод включён",
            "Translation off": "Перевод выключен",
            "Recording on": "Запись включена",
            "Recording off": "Запись выключена",
            "Summary ready": "Саммари готово",
            "Summary missing": "Саммари нет",
            "Protocol ready": "Протокол готов",
            "Protocol missing": "Протокол отсутствует",
            "Reply draft ready": "Черновик ответа готов",
            "Reply draft missing": "Черновика ответа нет",
            "Transcript": "Транскрипт",
            "Translation will appear here as final transcript chunks arrive.": "Перевод появится здесь, когда начнут приходить финальные фрагменты транскрипта.",
            "Translation is not available.": "Перевод недоступен.",
            "Transcript is not available.": "Транскрипт недоступен.",
            "Summary": "Саммари",
            "Protocol": "Протокол",
            "Suggested reply": "Подсказка ответа",
            "Metadata": "Метаданные",
            "Assets": "Результаты",
            "Completed": "Завершено",
            "Active": "Активно",
            "No translation": "Без перевода",
            "Untitled": "Без названия",
            "%@ words": "%@ слов",
            "%@ lines": "%@ строк",
            "%@ sessions": "%@ сессий",
            "revision %@": "ревизия %@",
            "Loading full session…": "Загружаем полную сессию…",
            "Account": "Аккаунт",
            "These fields come from the auth profile endpoint.": "Эти поля приходят из auth endpoint профиля.",
            "No authenticated account is available in the current desktop session.": "В текущей desktop-сессии нет активного аккаунта.",
            "Name": "Имя",
            "Email": "Почта",
            "Billing": "Биллинг",
            "Current plan, billing period, and live transcription usage.": "Текущий тариф, расчётный период и использование live transcription.",
            "Cancels at period end": "Отменится в конце периода",
            "Current plan": "Текущий тариф",
            "Current period end": "Конец текущего периода",
            "Subscription status": "Статус подписки",
            "Transcription access": "Доступ к транскрибации",
            "Refresh profile": "Обновить профиль",
            "Syncing account and billing…": "Синхронизируем аккаунт и биллинг…",
            "Account and billing data are up to date.": "Данные аккаунта и биллинга актуальны.",
            "Account synced, but billing is unavailable right now: %@": "Аккаунт синхронизирован, но биллинг сейчас недоступен: %@",
            "Loading billing summary…": "Загружаем сводку биллинга…",
            "Retry billing": "Повторить загрузку биллинга",
            "Usage this period": "Использование за период",
            "Live transcription available": "Онлайн-транскрибация доступна",
            "Live transcription unavailable": "Онлайн-транскрибация недоступна",
            "%@ min / %@ min": "%@ мин / %@ мин",
            "%@ min remaining": "Осталось %@ мин",
            "No active plan": "Нет активного тарифа",
            "No subscription": "Нет подписки",
            "Trialing": "Пробный период",
            "Past due": "Просрочено",
            "Canceled": "Отменено",
            "Expired": "Истекло",
            "Used %@ min out of %@ min. %@ min remain in the current billing period.": "Использовано %@ мин из %@ мин. В текущем периоде осталось %@ мин.",
            "Used %@ min out of %@ min. The billing limit has been reached.": "Использовано %@ мин из %@ мин. Лимит биллинга достигнут.",
            "No included minutes are reported yet.": "Включённые минуты пока не переданы.",
            "No included minutes are available for this workspace.": "Для этого workspace нет доступных включённых минут.",
            "Start Listening": "Начать прослушивание",
            "Stop Listening": "Остановить прослушивание",
            "Start listening?": "Начать прослушивание?",
            "Start a new session or continue the previous one?": "Начать новую сессию или продолжить предыдущую?",
            "Start New": "Начать новую",
            "Continue": "Продолжить",
            "Listening": "Слушает",
            "Meeting detected": "Обнаружен митинг",
            "Meeting audio is active": "Аудио митинга активно",
            "Meeting ended?": "Митинг завершён?",
            "Speechara is still listening.": "Speechara всё ещё слушает.",
            "The meeting window looks closed.": "Похоже, окно митинга закрыто.",
            "Finish recording": "Закончить запись",
            "Keep recording": "Продолжить запись",
            "Keep Listening": "Продолжить",
            "system audio": "системный звук",
            "Ready to listen": "Готово к прослушиванию",
            "Preparing session": "Подготавливаем сессию",
            "System + microphone live": "Система + микрофон активны",
            "Live listening": "Идёт прослушивание",
            "Microphone live": "Микрофон активен",
            "Listening stopped": "Прослушивание остановлено",
            "Waiting for speech...": "Ожидание речи...",
            "Generate a summary for the text in this panel.": "Сгенерировать саммари для текста в этой панели.",
            "Create a full structured meeting protocol from this transcript.": "Создать полный структурированный протокол встречи по этому транскрипту.",
            "Draft a suggested reply to the latest question in this transcript.": "Подготовить подсказку ответа на последний вопрос из этого транскрипта.",
            "Looks at the latest transcript and suggests a natural response you can say on the call.": "Смотрит на последний фрагмент транскрипта и предлагает естественный ответ, который можно сказать на звонке.",
            "The translation stays secondary to the live transcript and fills in only when final text is ready.": "Перевод остаётся вторичным к транскрипту и заполняется только после появления финального текста.",
            "Create a full structured meeting protocol in the selected translation language.": "Создать полный структурированный протокол встречи на выбранном языке перевода.",
            "Summarizing transcript...": "Создаём саммари транскрипта...",
            "No summary yet.": "Саммари пока нет.",
            "AI summary failed, showing a local fallback instead.": "AI-саммари не удалось, показываем локальный fallback.",
            "Summary generated, but could not be saved: %@": "Саммари создано, но не удалось сохранить: %@",
            "Building meeting protocol...": "Создаём протокол встречи...",
            "No protocol yet.": "Протокола пока нет.",
            "Suggesting a natural answer...": "Подготавливаем естественный ответ...",
            "Suggesting a translated answer...": "Подготавливаем переведённый ответ...",
            "No answer suggestion yet.": "Подсказки ответа пока нет.",
            "Decrease text size": "Уменьшить размер текста",
            "Increase text size": "Увеличить размер текста",
            "Turn microphone off. Right-click to choose a microphone.": "Выключить микрофон. Нажмите правой кнопкой, чтобы выбрать микрофон.",
            "Turn microphone on. Right-click to choose a microphone.": "Включить микрофон. Нажмите правой кнопкой, чтобы выбрать микрофон.",
            "No microphone devices available": "Нет доступных микрофонов",
            "Select microphone": "Выбрать микрофон",
            "Refresh microphones": "Обновить микрофоны",
            "Open Speechara": "Открыть Speechara",
            "Quit Speechara completely": "Полностью закрыть Speechara",
            "Grant access to continue": "Разрешите доступ, чтобы продолжить",
            "Update": "Обновить",
            "Update %@": "Обновить до %@",
            "Install available update": "Установить доступное обновление",
            "Prepare Speechara for live capture": "Подготовьте Speechara к live-захвату",
            "Microphone input": "Вход с микрофона",
            "Optional microphone input": "Опциональный вход с микрофона",
            "Start a Listening Session": "Начать сессию прослушивания",
            "Choose the input language and microphone, save the session as M4A, and turn translation on only when you need it.": "Выберите язык входа и микрофон, сохранение M4A и включайте перевод только когда он нужен.",
            "Choose the input language, decide whether to mix in your microphone, save the session as M4A, and turn translation on only when you need it.": "Выберите язык входа, решите, подмешивать ли микрофон, настройте сохранение M4A и включайте перевод только когда он нужен.",
            "Microphone": "Микрофон",
            "Microphone mix-in": "Подмешивание микрофона",
            "Speechara will listen through this input device.": "Speechara будет слушать через это устройство ввода.",
            "Add your own voice through the selected input device.": "Добавляет ваш голос через выбранное устройство ввода.",
            "Speechara captures system audio directly, without screen recording. Microphone access is optional for adding your own voice.": "Speechara захватывает системный звук напрямую, без записи экрана. Доступ к микрофону нужен только если вы хотите добавить свой голос.",
            "Allow microphone access so Speechara can listen from the menu bar without requesting screen recording.": "Разрешите доступ к микрофону, чтобы Speechara слушала из верхней панели без запроса записи экрана.",
            "Lets Speechara capture live audio from the selected microphone for transcription.": "Позволяет Speechara захватывать live-аудио с выбранного микрофона для транскрибации.",
            "Lets Speechara add your own voice from the selected microphone when microphone mix-in is enabled.": "Позволяет Speechara добавлять ваш голос с выбранного микрофона, когда включено подмешивание микрофона.",
            "What turns on after setup": "Что включится после настройки",
            "Audio-only listening": "Прослушивание только аудио",
            "Audio-only system capture": "Захват системного звука",
            "Speechara listens through the selected microphone without asking for screen recording access.": "Speechara слушает через выбранный микрофон и не просит доступ к записи экрана.",
            "Speechara listens to system audio without asking for screen recording access.": "Speechara слушает системный звук без запроса доступа к записи экрана.",
            "Menu bar control": "Управление из верхней панели",
            "Start and stop listening while Speechara stays in the top bar.": "Запускайте и останавливайте прослушивание, пока Speechara остаётся в верхней панели.",
            "Quick path": "Быстрый путь",
            "Needed for audio-only listening and device testing.": "Нужно для прослушивания только аудио и проверки устройства.",
            "Optional for microphone mix-in and device testing.": "Опционально для подмешивания микрофона и проверки устройства.",
            "You can skip this once, but Speechara will ask for microphone access before it can listen.": "Можно пропустить сейчас, но Speechara попросит доступ к микрофону перед началом прослушивания.",
            "You can skip this once. Speechara will ask for microphone access later only if you enable microphone mix-in.": "Можно пропустить сейчас. Speechara попросит доступ к микрофону позже только если вы включите подмешивание микрофона.",
            "Microphone access is active in this launch.": "Доступ к микрофону активен в этом запуске.",
            "Allow microphone access and the audio-only listening flow will be ready.": "Разрешите доступ к микрофону, и сценарий прослушивания только аудио будет готов.",
            "System audio starts without screen recording. Microphone access can be enabled later.": "Системный звук запускается без записи экрана. Доступ к микрофону можно включить позже.",
            "Speechara asks for microphone input for the menu bar listening flow.": "Speechara запрашивает вход с микрофона для прослушивания из верхней панели.",
            "Speechara asks for microphone input only when microphone mix-in or testing needs it.": "Speechara запрашивает микрофон только для подмешивания голоса или проверки устройства.",
            "Continue later": "Продолжить позже"
        ],
        .german: [
            "Settings": "Einstellungen",
            "Settings...": "Einstellungen...",
            "Appearance": "Darstellung",
            "Theme": "Thema",
            "Language": "Sprache",
            "App language": "App-Sprache",
            "Choose how Speechara looks and reads. Changes apply immediately.": "Wählen Sie Aussehen und Sprache von Speechara. Änderungen werden sofort angewendet.",
            "Switches the whole app between Light, Dark, or the current macOS appearance. Changes apply immediately.": "Schaltet die gesamte App zwischen Hell, Dunkel oder dem aktuellen macOS-Erscheinungsbild um. Änderungen werden sofort angewendet.",
            "Changes the entire app UI between English, Russian, German, Spanish, and French.": "Stellt die gesamte App-Oberfläche auf Englisch, Russisch, Deutsch, Spanisch oder Französisch um.",
            "System": "System",
            "Light": "Hell",
            "Dark": "Dunkel",
            "Workspace": "Arbeitsbereich",
            "Profile": "Profil",
            "History": "Verlauf",
            "Sign out": "Abmelden",
            "Sign In": "Anmelden",
            "Use Google, Microsoft, Apple, or a Speechara email/password account.": "Verwenden Sie Google, Microsoft, Apple oder ein Speechara-E-Mail-/Passwortkonto.",
            "Connect your Google account to unlock the full Speechara desktop workflow.": "Verbinden Sie Ihr Google-Konto, um den vollständigen Speechara-Desktop-Workflow zu nutzen.",
            "Waiting for Google…": "Warten auf Google…",
            "Continue with Google": "Mit Google fortfahren",
            "Waiting for Apple...": "Warten auf Apple...",
            "Continue with Apple": "Mit Apple fortfahren",
            "Complete Apple sign-in in the system prompt.": "Schliessen Sie die Apple-Anmeldung im Systemdialog ab.",
            "Cancel sign-in": "Anmeldung abbrechen",
            "By continuing, you allow Speechara to create a desktop session for your account.": "Wenn Sie fortfahren, erlauben Sie Speechara, eine Desktop-Sitzung für Ihr Konto zu erstellen.",
            "Auth settings": "Anmeldeeinstellungen",
            "Restoring your session…": "Sitzung wird wiederhergestellt…",
            "Show Preview": "Vorschau anzeigen",
            "New Session": "Neue Sitzung",
            "Focus Mode": "Fokusmodus",
            "Exit Focus": "Fokus beenden",
            "Saved audio": "Gespeichertes Audio",
            "Off": "Aus",
            "Input": "Eingabe",
            "Translation": "Übersetzung",
            "Live transcript preview": "Live-Transkriptvorschau",
            "Hide live transcript preview": "Live-Transkriptvorschau ausblenden",
            "Live transcript": "Live-Transkript",
            "Suggested response": "Vorgeschlagene Antwort",
            "Copy": "Kopieren",
            "Copy transcript": "Transkript kopieren",
            "Transcribe": "Transkript",
            "Translate": "Übersetzung",
            "Summarize": "Zusammenfassen",
            "Billing": "Abrechnung",
            "Start Listening": "Starten",
            "Stop Listening": "Stoppen",
            "Listening": "Hört zu",
            "Meeting ended?": "Meeting beendet?",
            "Speechara is still listening.": "Speechara hört noch zu.",
            "The meeting window looks closed.": "Das Meetingfenster scheint geschlossen zu sein.",
            "Finish recording": "Aufzeichnung beenden",
            "Keep recording": "Weiter aufnehmen",
            "Keep Listening": "Weiter zuhören",
            "Ready to listen": "Bereit zum Zuhören",
            "Preparing session": "Sitzung wird vorbereitet",
            "System + microphone live": "System + Mikrofon aktiv",
            "Live listening": "Live-Zuhören",
            "Microphone live": "Mikrofon aktiv",
            "Listening stopped": "Zuhören gestoppt",
            "Open": "Öffnen",
            "Opening…": "Wird geöffnet…",
            "Load more": "Mehr laden",
            "Loading more…": "Lädt mehr…",
            "Retry": "Erneut versuchen",
            "Hide panel": "Panel ausblenden",
            "Summary": "Zusammenfassung",
            "Summarizing transcript...": "Transkript wird zusammengefasst...",
            "No summary yet.": "Noch keine Zusammenfassung.",
            "AI summary failed, showing a local fallback instead.": "AI-Zusammenfassung fehlgeschlagen, lokale Ersatzfassung wird angezeigt.",
            "Summary generated, but could not be saved: %@": "Zusammenfassung erstellt, konnte aber nicht gespeichert werden: %@",
            "Protocol": "Protokoll",
            "Suggested reply": "Antwortvorschlag",
            "Completed": "Abgeschlossen",
            "Active": "Aktiv",
            "No translation": "Keine Übersetzung",
            "Untitled": "Ohne Titel",
            "%@ words": "%@ Wörter",
            "%@ lines": "%@ Zeilen",
            "%@ sessions": "%@ Sitzungen",
            "revision %@": "Revision %@",
            "Name": "Name",
            "Email": "E-Mail",
            "Refresh profile": "Profil aktualisieren",
            "Current plan": "Aktueller Tarif",
            "Current period end": "Aktuelles Periodenende",
            "Subscription status": "Abostatus",
            "Transcription access": "Transkriptionszugriff",
            "Show saved recording in Finder": "Gespeicherte Aufnahme im Finder anzeigen",
            "Decrease text size": "Textgröße verkleinern",
            "Increase text size": "Textgröße vergrößern",
            "No microphone devices available": "Keine Mikrofone verfügbar",
            "Select microphone": "Mikrofon auswählen",
            "Refresh microphones": "Mikrofone aktualisieren",
            "Quit Speechara completely": "Speechara vollständig beenden",
            "Clear subtitles": "Untertitel löschen",
            "Waiting for speech...": "Warten auf Sprache...",
            "Prepare Speechara for live capture": "Speechara für Live-Erfassung vorbereiten",
            "Microphone input": "Mikrofoneingang",
            "Start a Listening Session": "Zuhörsitzung starten",
            "Choose the input language and microphone, save the session as M4A, and turn translation on only when you need it.": "Wählen Sie Eingabesprache und Mikrofon, speichern Sie die Sitzung als M4A und aktivieren Sie Übersetzung nur bei Bedarf.",
            "Microphone": "Mikrofon",
            "Speechara will listen through this input device.": "Speechara hört über dieses Eingabegerät zu.",
            "Allow microphone access so Speechara can listen from the menu bar without requesting screen recording.": "Erlauben Sie den Mikrofonzugriff, damit Speechara über die Menüleiste zuhören kann, ohne Bildschirmaufnahme anzufordern.",
            "Lets Speechara capture live audio from the selected microphone for transcription.": "Ermöglicht Speechara, Live-Audio vom ausgewählten Mikrofon für die Transkription zu erfassen.",
            "What turns on after setup": "Was nach der Einrichtung aktiviert wird",
            "Audio-only listening": "Nur Audio hören",
            "Speechara listens through the selected microphone without asking for screen recording access.": "Speechara hört über das ausgewählte Mikrofon zu, ohne Zugriff auf Bildschirmaufnahme anzufordern.",
            "Menu bar control": "Menüleistensteuerung",
            "Start and stop listening while Speechara stays in the top bar.": "Starten und stoppen Sie das Zuhören, während Speechara in der Menüleiste bleibt.",
            "Quick path": "Schnellstart",
            "Needed for audio-only listening and device testing.": "Erforderlich für Nur-Audio-Zuhören und Gerätetests.",
            "You can skip this once, but Speechara will ask for microphone access before it can listen.": "Sie können dies einmal überspringen, aber Speechara fragt vor dem Zuhören nach Mikrofonzugriff.",
            "Microphone access is active in this launch.": "Mikrofonzugriff ist in diesem Start aktiv.",
            "Allow microphone access and the audio-only listening flow will be ready.": "Erlauben Sie den Mikrofonzugriff, dann ist der Nur-Audio-Ablauf bereit.",
            "Speechara asks for microphone input for the menu bar listening flow.": "Speechara fragt nach Mikrofoneingang für das Zuhören über die Menüleiste.",
            "Continue later": "Später fortfahren",
            "Setup %@%%": "Einrichtung %@%%",
            "Restart required": "Neustart erforderlich",
            "Permission setup": "Berechtigungen einrichten",
            "Allow access": "Zugriff erlauben",
            "Open settings": "Einstellungen öffnen",
            "Allowed": "Erlaubt",
            "Approved": "Genehmigt",
            "Not requested": "Nicht angefordert",
            "Needs attention": "Benötigt Aufmerksamkeit",
            "Not approved": "Nicht genehmigt",
            "Restart needed": "Neustart nötig",
            "Quit and reopen": "Beenden und neu öffnen",
            "Open Speechara": "Speechara öffnen",
            "Grant access to continue": "Zugriff gewähren, um fortzufahren",
            "Update": "Aktualisieren",
            "Update %@": "Auf %@ aktualisieren",
            "Install available update": "Verfügbares Update installieren"
        ],
        .spanish: [
            "Settings": "Configuración",
            "Settings...": "Configuración...",
            "Appearance": "Apariencia",
            "Theme": "Tema",
            "Language": "Idioma",
            "App language": "Idioma de la app",
            "Choose how Speechara looks and reads. Changes apply immediately.": "Elige cómo se ve y se lee Speechara. Los cambios se aplican al instante.",
            "Switches the whole app between Light, Dark, or the current macOS appearance. Changes apply immediately.": "Cambia toda la app entre claro, oscuro o la apariencia actual de macOS. Los cambios se aplican al instante.",
            "Changes the entire app UI between English, Russian, German, Spanish, and French.": "Cambia toda la interfaz de la app entre inglés, ruso, alemán, español y francés.",
            "System": "Sistema",
            "Light": "Claro",
            "Dark": "Oscuro",
            "Workspace": "Espacio de trabajo",
            "Profile": "Perfil",
            "History": "Historial",
            "Sign out": "Cerrar sesión",
            "Sign In": "Iniciar sesión",
            "Use Google, Microsoft, Apple, or a Speechara email/password account.": "Usa Google, Microsoft, Apple o una cuenta de Speechara con correo y contraseña.",
            "Waiting for Google…": "Esperando a Google…",
            "Continue with Google": "Continuar con Google",
            "Waiting for Apple...": "Esperando a Apple...",
            "Continue with Apple": "Continuar con Apple",
            "Complete Apple sign-in in the system prompt.": "Completa el inicio de sesión con Apple en el aviso del sistema.",
            "Show Preview": "Mostrar vista previa",
            "New Session": "Nueva sesión",
            "Focus Mode": "Modo enfoque",
            "Exit Focus": "Salir del enfoque",
            "Saved audio": "Audio guardado",
            "Off": "Desactivado",
            "Input": "Entrada",
            "Translation": "Traducción",
            "Live transcript preview": "Vista previa de la transcripción",
            "Hide live transcript preview": "Ocultar vista previa",
            "Live transcript": "Transcripción en vivo",
            "Suggested response": "Respuesta sugerida",
            "Copy": "Copiar",
            "Copy transcript": "Copiar transcripción",
            "Transcribe": "Transcripción",
            "Translate": "Traducción",
            "Summarize": "Resumir",
            "Open": "Abrir",
            "Opening…": "Abriendo…",
            "Load more": "Cargar más",
            "Loading more…": "Cargando más…",
            "Retry": "Reintentar",
            "Summary": "Resumen",
            "Summarizing transcript...": "Resumiendo transcripción...",
            "No summary yet.": "Aún no hay resumen.",
            "AI summary failed, showing a local fallback instead.": "Falló el resumen con AI; se muestra una alternativa local.",
            "Summary generated, but could not be saved: %@": "El resumen se generó, pero no se pudo guardar: %@",
            "Protocol": "Protocolo",
            "Suggested reply": "Respuesta sugerida",
            "Completed": "Completado",
            "Active": "Activo",
            "No translation": "Sin traducción",
            "Untitled": "Sin título",
            "%@ words": "%@ palabras",
            "%@ lines": "%@ líneas",
            "%@ sessions": "%@ sesiones",
            "revision %@": "revisión %@",
            "Billing": "Facturación",
            "Name": "Nombre",
            "Email": "Correo",
            "Refresh profile": "Actualizar perfil",
            "Start Listening": "Empezar a escuchar",
            "Stop Listening": "Detener escucha",
            "Listening": "Escuchando",
            "Meeting ended?": "¿La reunión terminó?",
            "Speechara is still listening.": "Speechara sigue escuchando.",
            "The meeting window looks closed.": "Parece que la ventana de la reunión se cerró.",
            "Finish recording": "Finalizar grabación",
            "Keep recording": "Seguir grabando",
            "Keep Listening": "Seguir escuchando",
            "Ready to listen": "Listo para escuchar",
            "Preparing session": "Preparando sesión",
            "Waiting for speech...": "Esperando voz...",
            "Show saved recording in Finder": "Mostrar grabación guardada en Finder",
            "Decrease text size": "Reducir tamaño del texto",
            "Increase text size": "Aumentar tamaño del texto",
            "No microphone devices available": "No hay micrófonos disponibles",
            "Select microphone": "Seleccionar micrófono",
            "Refresh microphones": "Actualizar micrófonos",
            "Quit Speechara completely": "Cerrar Speechara por completo",
            "Clear subtitles": "Borrar subtítulos",
            "Hide panel": "Ocultar panel",
            "Prepare Speechara for live capture": "Preparar Speechara para captura en vivo",
            "Microphone input": "Entrada de micrófono",
            "Start a Listening Session": "Iniciar una sesión de escucha",
            "Choose the input language and microphone, save the session as M4A, and turn translation on only when you need it.": "Elige el idioma de entrada y el micrófono, guarda la sesión como M4A y activa la traducción solo cuando la necesites.",
            "Microphone": "Micrófono",
            "Speechara will listen through this input device.": "Speechara escuchará a través de este dispositivo de entrada.",
            "Allow microphone access so Speechara can listen from the menu bar without requesting screen recording.": "Permite el acceso al micrófono para que Speechara escuche desde la barra de menú sin pedir grabación de pantalla.",
            "Lets Speechara capture live audio from the selected microphone for transcription.": "Permite que Speechara capture audio en vivo del micrófono seleccionado para transcripción.",
            "What turns on after setup": "Qué se activa después de configurar",
            "Audio-only listening": "Escucha solo de audio",
            "Speechara listens through the selected microphone without asking for screen recording access.": "Speechara escucha a través del micrófono seleccionado sin pedir acceso a grabación de pantalla.",
            "Menu bar control": "Control desde la barra de menú",
            "Start and stop listening while Speechara stays in the top bar.": "Inicia y detén la escucha mientras Speechara permanece en la barra superior.",
            "Quick path": "Ruta rápida",
            "Needed for audio-only listening and device testing.": "Necesario para escucha solo de audio y prueba del dispositivo.",
            "You can skip this once, but Speechara will ask for microphone access before it can listen.": "Puedes omitirlo una vez, pero Speechara pedirá acceso al micrófono antes de poder escuchar.",
            "Microphone access is active in this launch.": "El acceso al micrófono está activo en este inicio.",
            "Allow microphone access and the audio-only listening flow will be ready.": "Permite el acceso al micrófono y el flujo de escucha solo de audio estará listo.",
            "Speechara asks for microphone input for the menu bar listening flow.": "Speechara solicita entrada de micrófono para la escucha desde la barra de menú.",
            "Continue later": "Continuar más tarde",
            "Setup %@%%": "Configuración %@%%",
            "Restart required": "Se requiere reinicio",
            "Permission setup": "Configurar permisos",
            "Allow access": "Permitir acceso",
            "Open settings": "Abrir ajustes",
            "Allowed": "Permitido",
            "Approved": "Aprobado",
            "Not requested": "No solicitado",
            "Needs attention": "Requiere atención",
            "Not approved": "No aprobado",
            "Restart needed": "Reinicio necesario",
            "Quit and reopen": "Cerrar y volver a abrir",
            "Open Speechara": "Abrir Speechara",
            "Grant access to continue": "Concede acceso para continuar",
            "Update": "Actualizar",
            "Update %@": "Actualizar a %@",
            "Install available update": "Instalar actualización disponible"
        ],
        .french: [
            "Settings": "Réglages",
            "Settings...": "Réglages...",
            "Appearance": "Apparence",
            "Theme": "Thème",
            "Language": "Langue",
            "App language": "Langue de l’app",
            "Choose how Speechara looks and reads. Changes apply immediately.": "Choisissez l’apparence et la langue de Speechara. Les changements s’appliquent immédiatement.",
            "Switches the whole app between Light, Dark, or the current macOS appearance. Changes apply immediately.": "Bascule toute l’app entre clair, sombre ou l’apparence actuelle de macOS. Les changements s’appliquent immédiatement.",
            "Changes the entire app UI between English, Russian, German, Spanish, and French.": "Change toute l’interface de l’app entre l’anglais, le russe, l’allemand, l’espagnol et le français.",
            "System": "Système",
            "Light": "Clair",
            "Dark": "Sombre",
            "Workspace": "Espace de travail",
            "Profile": "Profil",
            "History": "Historique",
            "Sign out": "Se déconnecter",
            "Sign In": "Se connecter",
            "Use Google, Microsoft, Apple, or a Speechara email/password account.": "Utilisez Google, Microsoft, Apple ou un compte Speechara avec e-mail et mot de passe.",
            "Waiting for Google…": "En attente de Google…",
            "Continue with Google": "Continuer avec Google",
            "Waiting for Apple...": "En attente d'Apple...",
            "Continue with Apple": "Continuer avec Apple",
            "Complete Apple sign-in in the system prompt.": "Terminez la connexion Apple dans l'invite système.",
            "Show Preview": "Afficher l’aperçu",
            "New Session": "Nouvelle session",
            "Focus Mode": "Mode focus",
            "Exit Focus": "Quitter le focus",
            "Saved audio": "Audio enregistré",
            "Off": "Désactivé",
            "Input": "Entrée",
            "Translation": "Traduction",
            "Live transcript preview": "Aperçu du transcript en direct",
            "Hide live transcript preview": "Masquer l’aperçu en direct",
            "Live transcript": "Transcript en direct",
            "Suggested response": "Réponse suggérée",
            "Copy": "Copier",
            "Copy transcript": "Copier le transcript",
            "Transcribe": "Transcript",
            "Translate": "Traduction",
            "Summarize": "Résumer",
            "Open": "Ouvrir",
            "Opening…": "Ouverture…",
            "Load more": "Charger plus",
            "Loading more…": "Chargement…",
            "Retry": "Réessayer",
            "Summary": "Résumé",
            "Summarizing transcript...": "Résumé du transcript...",
            "No summary yet.": "Aucun résumé pour le moment.",
            "AI summary failed, showing a local fallback instead.": "Le résumé AI a échoué, affichage d’une version locale.",
            "Summary generated, but could not be saved: %@": "Le résumé a été généré, mais n’a pas pu être enregistré : %@",
            "Protocol": "Protocole",
            "Suggested reply": "Réponse suggérée",
            "Completed": "Terminé",
            "Active": "Actif",
            "No translation": "Sans traduction",
            "Untitled": "Sans titre",
            "%@ words": "%@ mots",
            "%@ lines": "%@ lignes",
            "%@ sessions": "%@ sessions",
            "revision %@": "révision %@",
            "Billing": "Facturation",
            "Name": "Nom",
            "Email": "E-mail",
            "Refresh profile": "Actualiser le profil",
            "Start Listening": "Démarrer l’écoute",
            "Stop Listening": "Arrêter l’écoute",
            "Listening": "Écoute",
            "Meeting ended?": "Réunion terminée ?",
            "Speechara is still listening.": "Speechara écoute toujours.",
            "The meeting window looks closed.": "La fenêtre de réunion semble fermée.",
            "Finish recording": "Terminer l’enregistrement",
            "Keep recording": "Continuer l’enregistrement",
            "Keep Listening": "Continuer l’écoute",
            "Ready to listen": "Prêt à écouter",
            "Preparing session": "Préparation de la session",
            "Waiting for speech...": "En attente de la parole...",
            "Show saved recording in Finder": "Afficher l’enregistrement dans le Finder",
            "Decrease text size": "Réduire la taille du texte",
            "Increase text size": "Augmenter la taille du texte",
            "No microphone devices available": "Aucun microphone disponible",
            "Select microphone": "Choisir le microphone",
            "Refresh microphones": "Actualiser les microphones",
            "Quit Speechara completely": "Quitter Speechara complètement",
            "Clear subtitles": "Effacer les sous-titres",
            "Hide panel": "Masquer le panneau",
            "Prepare Speechara for live capture": "Préparer Speechara pour la capture en direct",
            "Microphone input": "Entrée microphone",
            "Start a Listening Session": "Démarrer une session d’écoute",
            "Choose the input language and microphone, save the session as M4A, and turn translation on only when you need it.": "Choisissez la langue d’entrée et le microphone, enregistrez la session en M4A et activez la traduction seulement quand vous en avez besoin.",
            "Microphone": "Microphone",
            "Speechara will listen through this input device.": "Speechara écoutera via ce périphérique d’entrée.",
            "Allow microphone access so Speechara can listen from the menu bar without requesting screen recording.": "Autorisez l’accès au microphone afin que Speechara puisse écouter depuis la barre de menus sans demander l’enregistrement d’écran.",
            "Lets Speechara capture live audio from the selected microphone for transcription.": "Permet à Speechara de capturer l’audio en direct du microphone sélectionné pour la transcription.",
            "What turns on after setup": "Ce qui s’active après la configuration",
            "Audio-only listening": "Écoute audio seule",
            "Speechara listens through the selected microphone without asking for screen recording access.": "Speechara écoute via le microphone sélectionné sans demander l’accès à l’enregistrement d’écran.",
            "Menu bar control": "Contrôle depuis la barre de menus",
            "Start and stop listening while Speechara stays in the top bar.": "Démarrez et arrêtez l’écoute pendant que Speechara reste dans la barre supérieure.",
            "Quick path": "Parcours rapide",
            "Needed for audio-only listening and device testing.": "Nécessaire pour l’écoute audio seule et le test de l’appareil.",
            "You can skip this once, but Speechara will ask for microphone access before it can listen.": "Vous pouvez ignorer cette étape une fois, mais Speechara demandera l’accès au microphone avant de pouvoir écouter.",
            "Microphone access is active in this launch.": "L’accès au microphone est actif dans ce lancement.",
            "Allow microphone access and the audio-only listening flow will be ready.": "Autorisez l’accès au microphone et le flux d’écoute audio seule sera prêt.",
            "Speechara asks for microphone input for the menu bar listening flow.": "Speechara demande l’entrée microphone pour l’écoute depuis la barre de menus.",
            "Continue later": "Continuer plus tard",
            "Setup %@%%": "Configuration %@%%",
            "Restart required": "Redémarrage requis",
            "Permission setup": "Configuration des autorisations",
            "Allow access": "Autoriser l’accès",
            "Open settings": "Ouvrir les réglages",
            "Allowed": "Autorisé",
            "Approved": "Approuvé",
            "Not requested": "Non demandé",
            "Needs attention": "Attention requise",
            "Not approved": "Non approuvé",
            "Restart needed": "Redémarrage nécessaire",
            "Quit and reopen": "Quitter et rouvrir",
            "Open Speechara": "Ouvrir Speechara",
            "Grant access to continue": "Accorder l’accès pour continuer",
            "Update": "Mettre à jour",
            "Update %@": "Mettre à jour vers %@",
            "Install available update": "Installer la mise à jour disponible"
        ],
    ]
}

func SL(_ key: String) -> String {
    SpeecharaLocalizationStore.shared.localized(key)
}

func SLF(_ key: String, _ arguments: CVarArg...) -> String {
    SpeecharaLocalizationStore.shared.localizedFormat(key, arguments)
}

extension Bundle {
    @objc fileprivate func speechara_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let fallback = speechara_localizedString(forKey: key, value: value, table: tableName)

        guard bundlePath == Bundle.main.bundlePath else {
            return fallback
        }

        let translated = SpeecharaLocalizationStore.shared.localized(key)
        return translated == key ? fallback : translated
    }
}
