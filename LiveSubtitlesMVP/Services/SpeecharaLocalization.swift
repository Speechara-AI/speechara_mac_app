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
            "Connect your Google account to unlock the full Speechara desktop workflow.": "Подключите аккаунт Google, чтобы открыть полный desktop-сценарий Speechara.",
            "Waiting for Google…": "Ожидание Google…",
            "Continue with Google": "Продолжить с Google",
            "Cancel sign-in": "Отменить вход",
            "By continuing, you allow Speechara to create a desktop session for your account.": "Продолжая, вы разрешаете Speechara создать desktop-сессию для вашего аккаунта.",
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
            "Prepare Speechara for live capture": "Подготовьте Speechara к live-захвату",
            "Enable the two macOS permissions that unlock system audio, microphone mix-in, and the full live transcription flow.": "Включите два разрешения macOS, которые открывают системный звук, микрофон и полный сценарий live-транскрибации.",
            "What turns on after setup": "Что включится после настройки",
            "Quick path": "Быстрый путь",
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
            "Connect your Google account to unlock the full Speechara desktop workflow.": "Verbinden Sie Ihr Google-Konto, um den vollständigen Speechara-Desktop-Workflow zu nutzen.",
            "Waiting for Google…": "Warten auf Google…",
            "Continue with Google": "Mit Google fortfahren",
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
            "Billing": "Abrechnung",
            "Start Listening": "Starten",
            "Stop Listening": "Stoppen",
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
            "Clear subtitles": "Untertitel löschen",
            "Waiting for speech...": "Warten auf Sprache...",
            "Prepare Speechara for live capture": "Speechara für Live-Erfassung vorbereiten",
            "Enable the two macOS permissions that unlock system audio, microphone mix-in, and the full live transcription flow.": "Aktivieren Sie die zwei macOS-Berechtigungen für Systemaudio, Mikrofon-Mix und den vollständigen Live-Transkriptionsablauf.",
            "What turns on after setup": "Was nach der Einrichtung aktiviert wird",
            "Quick path": "Schnellstart",
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
            "Grant access to continue": "Zugriff gewähren, um fortzufahren"
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
            "Waiting for Google…": "Esperando a Google…",
            "Continue with Google": "Continuar con Google",
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
            "Open": "Abrir",
            "Opening…": "Abriendo…",
            "Load more": "Cargar más",
            "Loading more…": "Cargando más…",
            "Retry": "Reintentar",
            "Summary": "Resumen",
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
            "Ready to listen": "Listo para escuchar",
            "Preparing session": "Preparando sesión",
            "Waiting for speech...": "Esperando voz...",
            "Show saved recording in Finder": "Mostrar grabación guardada en Finder",
            "Decrease text size": "Reducir tamaño del texto",
            "Increase text size": "Aumentar tamaño del texto",
            "No microphone devices available": "No hay micrófonos disponibles",
            "Clear subtitles": "Borrar subtítulos",
            "Hide panel": "Ocultar panel",
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
            "Grant access to continue": "Concede acceso para continuar"
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
            "Waiting for Google…": "En attente de Google…",
            "Continue with Google": "Continuer avec Google",
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
            "Open": "Ouvrir",
            "Opening…": "Ouverture…",
            "Load more": "Charger plus",
            "Loading more…": "Chargement…",
            "Retry": "Réessayer",
            "Summary": "Résumé",
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
            "Ready to listen": "Prêt à écouter",
            "Preparing session": "Préparation de la session",
            "Waiting for speech...": "En attente de la parole...",
            "Show saved recording in Finder": "Afficher l’enregistrement dans le Finder",
            "Decrease text size": "Réduire la taille du texte",
            "Increase text size": "Augmenter la taille du texte",
            "No microphone devices available": "Aucun microphone disponible",
            "Clear subtitles": "Effacer les sous-titres",
            "Hide panel": "Masquer le panneau",
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
            "Grant access to continue": "Accorder l’accès pour continuer"
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
