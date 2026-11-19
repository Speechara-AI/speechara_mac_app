import crypto from 'node:crypto'
import fs from 'node:fs/promises'
import path from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath, pathToFileURL } from 'node:url'

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url))
const projectDirectory = path.resolve(scriptDirectory, '..')
const webProjectDirectory = process.env.SPEECHARA_WEB_REPO
  ? path.resolve(process.env.SPEECHARA_WEB_REPO)
  : path.resolve(projectDirectory, '..', 'speechara', 'speechara-app')
const webLocalesDirectory = path.join(webProjectDirectory, 'src/i18n/locales')
const localizationSourceFile = path.join(
  projectDirectory,
  'Speechara/Services/SpeecharaLocalization.swift',
)
const swiftSourceDirectory = path.join(projectDirectory, 'Speechara')
const outputFile = path.join(
  projectDirectory,
  'Speechara/Resources/SpeecharaInterfaceTranslations.json',
)
const cacheDirectory = path.join(
  projectDirectory,
  'build/interface-localization-cache',
)

const locales = [
  'ar', 'be', 'bg', 'bn', 'bs', 'ca', 'cs', 'da', 'de', 'el', 'es', 'et',
  'fa', 'fi', 'fr', 'gu', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'kn',
  'ko', 'lt', 'lv', 'mk', 'mr', 'ms', 'nl', 'no', 'pl', 'pt', 'ro', 'ru',
  'sk', 'sl', 'sr', 'sv', 'ta', 'te', 'th', 'tl', 'tr', 'uk', 'ur', 'vi',
  'zh',
]
const manualTranslations = {
  bs: {
    'Checking your Speechara account...': 'Provjeravamo vaš Speechara račun...',
  },
  fa: {
    'Speechara opened your default browser. Finish %@ sign-in there and the app will activate again automatically.':
      'Speechara مرورگر پیش‌فرض شما را باز کرد. ورود به %@ را در آنجا تکمیل کنید تا برنامه دوباره به‌طور خودکار فعال شود.',
  },
  fi: {
    'Enter the authenticator code for %@.':
      'Anna käyttäjän %@ todennussovelluskoodi.',
  },
  hi: {
    'Speechara opened your default browser. Finish %@ sign-in there and the app will activate again automatically.':
      'Speechara ने आपका डिफ़ॉल्ट ब्राउज़र खोल दिया है। वहाँ %@ साइन-इन पूरा करें और ऐप अपने-आप फिर सक्रिय हो जाएगा।',
  },
  hr: {
    'Checking your Speechara account...': 'Provjeravamo vaš Speechara račun...',
  },
  lt: {
    'Checking your Speechara account...': 'Tikrinama jūsų Speechara paskyra...',
    'Speechara opened your default browser. Finish %@ sign-in there and the app will activate again automatically.':
      'Speechara atidarė numatytąją naršyklę. Užbaikite prisijungimą prie %@ joje ir programa vėl bus automatiškai aktyvuota.',
  },
  pl: {
    'Checking your Speechara account...': 'Sprawdzanie konta Speechara...',
    'Speechara opened your default browser. Finish %@ sign-in there and the app will activate again automatically.':
      'Speechara otworzyła domyślną przeglądarkę. Dokończ w niej logowanie przez %@, a aplikacja automatycznie uaktywni się ponownie.',
    'We sent a code to %@.': 'Wysłaliśmy kod na adres %@.',
  },
  sl: {
    'Checking your Speechara account...': 'Preverjanje vašega računa Speechara...',
    'Speechara opened your default browser. Finish %@ sign-in there and the app will activate again automatically.':
      'Speechara je odprla vaš privzeti brskalnik. Tam dokončajte prijavo prek %@ in aplikacija se bo znova samodejno aktivirala.',
    'We sent a code to %@.': 'Kodo smo poslali na %@.',
  },
  uk: {
    '%@ is required.': 'Поле «%@» обов’язкове.',
    '%@ lines': '%@ рядків',
    '%@ min remaining': 'Залишилося %@ хв',
    '%@ sessions': '%@ сеансів',
    '%d of %d covered': 'Опрацьовано %d з %d',
    'Account': 'Обліковий запис',
    'Account and billing data are up to date.': 'Дані облікового запису й оплати актуальні.',
    'AI meeting notes failed, showing a local fallback instead.': 'Не вдалося створити нотатки зустрічі за допомогою ШІ. Натомість показано локальний варіант.',
    'AI summary failed, showing a local fallback instead.': 'Не вдалося створити підсумок за допомогою ШІ. Натомість показано локальний варіант.',
    'Allow microphone access': 'Дозволити доступ до мікрофона',
    'Allow microphone access and the audio-only listening flow will be ready.': 'Дозвольте доступ до мікрофона, щоб використовувати режим прослуховування лише аудіо.',
    'Profile': 'Профіль',
    'Language': 'Мова',
    'App language': 'Мова застосунку',
    'Assets': 'Ресурси',
    'Audio-only listening': 'Прослуховування лише аудіо',
    'Audio-only system capture': 'Захоплення лише системного аудіо',
    'Authenticator code': 'Код автентифікатора',
    'Back': 'Назад',
    'Billing': 'Оплата',
    'Building meeting notes...': 'Створення нотаток зустрічі...',
    'Building meeting protocol...': 'Створення протоколу зустрічі...',
    'By continuing, you allow Speechara to create a desktop session for your account.': 'Продовжуючи, ви дозволяєте Speechara створити сеанс застосунку для вашого облікового запису.',
    'Cancel': 'Скасувати',
    'Canceled': 'Скасовано',
    'Check for Updates...': 'Перевірити наявність оновлень...',
    'Clear subtitles': 'Очистити субтитри',
    'Collapse sidebar': 'Згорнути бічну панель',
    'Complete Apple sign-in in the system prompt.': 'Завершіть вхід через Apple у системному діалоговому вікні.',
    'Continue to 2FA': 'Перейти до 2FA',
    'Continue with Apple': 'Продовжити з Apple',
    'Continue with Google': 'Продовжити з Google',
    'Continue with Microsoft': 'Продовжити з Microsoft',
    'Continue Without Mic': 'Продовжити без мікрофона',
    'Copied': 'Скопійовано',
    'Copy': 'Копіювати',
    'Could not protect the local speaking note draft: %@': 'Не вдалося захистити локальну чернетку нотатки для виступу: %@',
    'Could not save speaking note. The local draft is safe: %@': 'Не вдалося зберегти нотатку для виступу. Локальна чернетка в безпеці: %@',
    'Current period end': 'Кінець поточного періоду',
    'Current plan': 'Поточний тариф',
    'Dark': 'Темна',
    'Default microphone': 'Мікрофон за замовчуванням',
    'Delete': 'Видалити',
    'Deleting…': 'Видалення…',
    'Duplicate': 'Дублювати',
    'Email': 'Електронна пошта',
    'Email sign in': 'Вхід через електронну пошту',
    'Empty talking point': 'Порожня теза',
    'Exit Focus': 'Вийти з режиму фокусування',
    'Expand Speechara': 'Розгорнути Speechara',
    'Expired': 'Термін дії минув',
    'Finish registration': 'Завершити реєстрацію',
    'Generate a summary for the text in this panel.': 'Створити підсумок тексту в цій панелі.',
    'Have an account?': 'Уже маєте обліковий запис?',
    'Hide completely': 'Приховати повністю',
    'Hide live transcript preview': 'Приховати попередній перегляд транскрипту наживо',
    'Hide panel': 'Приховати панель',
    'Hide speaking notes': 'Приховати нотатки для виступу',
    'Hide warning': 'Приховати попередження',
    'Keep Listening': 'Продовжити слухати',
    'Keep listening with all Speechara windows hidden.': 'Продовжувати прослуховування, приховавши всі вікна Speechara.',
    'Keep recording': 'Продовжити запис',
    'Light': 'Світла',
    'Listening language': 'Мова розпізнавання',
    'Listening stopped': 'Прослуховування зупинено',
    'Live draft': 'Чернетка наживо',
    'Live listening': 'Прослуховування наживо',
    'Live transcript': 'Транскрипт наживо',
    'Live transcript preview': 'Попередній перегляд транскрипту наживо',
    'Live transcription available': 'Транскрипція доступна',
    'Live transcription unavailable': 'Транскрипція недоступна',
    'Live translation': 'Синхронний переклад',
    'Load more': 'Завантажити ще',
    'Loading billing summary…': 'Завантаження даних про оплату…',
    'Loading more…': 'Завантаження…',
    'Loading session history…': 'Завантаження історії сеансів…',
    'Local draft': 'Локальна чернетка',
    'Manage your Speechara account, plan, and usage.': 'Керуйте обліковим записом Speechara, тарифом і використанням.',
    'Meeting notes': 'Нотатки зустрічі',
    'Meeting notes ready': 'Нотатки зустрічі готові',
    'Menu bar control': 'Керування з рядка меню',
    'Mic: Off': 'Мікрофон: вимкнено',
    'Mic: On': 'Мікрофон: увімкнено',
    'Microphone': 'Мікрофон',
    'Needs attention': 'Потребує уваги',
    'New': 'Нове',
    'No active plan': 'Немає активного тарифу',
    'No included minutes are available for this workspace.': 'Для цього робочого простору немає доступних хвилин.',
    'No included minutes are reported yet.': 'Доступні хвилини ще не вказані.',
    'No meeting notes yet.': 'Нотаток зустрічі поки немає.',
    'No microphone devices are available.': 'Немає доступних мікрофонів.',
    'No microphone devices available': 'Немає доступних мікрофонів',
    'No speaking note was attached to this meeting.': 'До цієї зустрічі не прикріплено нотатку для виступу.',
    'No subscription': 'Немає підписки',
    'No translation': 'Немає перекладу',
    'Off': 'Вимкнено',
    'Open': 'Відкрити',
    'Open billing in the web app': 'Відкрити оплату у вебзастосунку',
    'Open settings': 'Відкрити налаштування',
    'Open speaking notes library': 'Відкрити бібліотеку нотаток для виступу',
    'Open Speechara': 'Відкрити Speechara',
    'Optional for microphone mix-in and device testing.': 'Необов’язково. Використовується для додавання звуку з мікрофона й тестування пристроїв.',
    'Optional microphone input': 'Додатковий вхід із мікрофона',
    'Password': 'Пароль',
    'Passwords do not match.': 'Паролі не збігаються.',
    'Past due': 'Прострочено',
    'Permission setup': 'Налаштування дозволів',
    'Prepare new': 'Підготувати нову',
    'Prepare Speechara for live capture': 'Підготувати Speechara до захоплення аудіо наживо',
    'Preparing session': 'Підготовка сеансу',
    'Preview': 'Попередній перегляд',
    'Quick path': 'Швидкий спосіб',
    'Quit Speechara completely': 'Повністю завершити роботу Speechara',
    'Ready to listen': 'Готово до прослуховування',
    'Recording off': 'Запис вимкнено',
    'Recording on': 'Запис увімкнено',
    'Refresh list': 'Оновити список',
    'Rename note': 'Перейменувати нотатку',
    'Renew': 'Поновити',
    'Resize transcript and translation panels': 'Змінити розмір панелей транскрипту й перекладу',
    'Resize transcript panels': 'Змінити розмір панелей транскрипту',
    'Retry': 'Спробувати ще раз',
    'Retry billing': 'Повторити завантаження даних про оплату',
    'Retry Save': 'Повторити збереження',
    'revision %@': 'версія %@',
    'Saved audio': 'Збережене аудіо',
    'Search transcript, translation, summary, or meeting notes': 'Шукати в транскрипті, перекладі, підсумку або нотатках зустрічі',
    'Search transcript, translation, summary, or protocol': 'Шукати в транскрипті, перекладі, підсумку або протоколі',
    'Set up 2FA before finishing': 'Налаштувати 2FA перед завершенням',
    'Set up authenticator': 'Налаштувати автентифікатор',
    'Set your password': 'Установіть пароль',
    'Show mini window': 'Показувати міні-вікно',
    'Show Preview': 'Показати попередній перегляд',
    'Show sidebar': 'Показати бічну панель',
    'Side by side': 'Поруч',
    'Sign in to sync speaking notes.': 'Увійдіть, щоб синхронізувати нотатки для виступу.',
    'Sign in with email': 'Увійти за допомогою електронної пошти',
    'Sign out': 'Вийти',
    'Sign-in failed': 'Не вдалося ввійти',
    'Spanish': 'Іспанська',
    'Speaker %@': 'Доповідач %@',
    'Speaking notes': 'Нотатки для виступу',
    'Speaking notes request failed.': 'Не вдалося виконати запит щодо нотаток для виступу.',
    'Speechara asks for microphone input for the menu bar listening flow.': 'Speechara запитує доступ до мікрофона для прослуховування через рядок меню.',
    'Speechara captures system audio directly, without screen recording. Microphone access is optional for adding your own voice.': 'Speechara захоплює системний звук без запису екрана. Доступ до мікрофона необов’язковий і потрібен лише для додавання вашого голосу.',
    'Speechara opened your default browser. Finish %@ sign-in there and the app will activate again automatically.': 'Speechara відкрила браузер за замовчуванням. Завершіть у ньому вхід через %@ — застосунок активується автоматично.',
    'Speechara will ask macOS for microphone access the first time.': 'Під час першого запуску Speechara попросить macOS надати доступ до мікрофона.',
    'Stacked': 'Одна над одною',
    'Start a Listening Session': 'Почати сеанс прослуховування',
    'Start a new session or continue the previous one?': 'Почати новий сеанс чи продовжити попередній?',
    'Start and stop listening while Speechara stays in the top bar.': 'Починайте й зупиняйте прослуховування, поки Speechara залишається в рядку меню.',
    'Start Listening': 'Почати прослуховування',
    'Start listening to see the transcript here.': 'Почніть прослуховування, щоб побачити тут транскрипт.',
    'Start listening?': 'Почати прослуховування?',
    'Start New': 'Почати новий',
    'Start test': 'Почати тест',
    'Stop Listening': 'Зупинити прослуховування',
    'Stop test': 'Зупинити тест',
    'Subscription status': 'Стан підписки',
    'Suggest answer': 'Запропонувати відповідь',
    'Suggested answer': 'Запропонована відповідь',
    'Suggesting a natural answer...': 'Підготовка природної відповіді...',
    'Suggesting a translated answer...': 'Підготовка перекладеної відповіді...',
    'Suggesting answer...': 'Підготовка відповіді...',
    'Summarize': 'Підсумувати',
    'Summarizing transcript...': 'Створення підсумку транскрипту...',
    'Summarizing...': 'Створення підсумку...',
    'Summary': 'Підсумок',
    'Summary ready': 'Підсумок готовий',
    'Switch to Speech to view the full prepared script.': 'Перейдіть до режиму «Промова», щоб переглянути повний підготовлений текст.',
    'Switch to Talking points for a compact checklist.': 'Перейдіть до режиму «Тези», щоб відкрити компактний контрольний список.',
    'Switch transcript and translation layout': 'Змінити розташування транскрипту й перекладу',
    'Switch transcript layout': 'Змінити розташування транскрипту',
    'Switches the whole app between Light, Dark, or the current macOS appearance. Changes apply immediately.': 'Перемикає весь застосунок між світлою, темною й системною темами macOS. Зміни застосовуються відразу.',
    'Syncing account and billing…': 'Синхронізація облікового запису й даних про оплату…',
    'System': 'Системна',
    'system audio': 'системний звук',
    'The meeting remains active in history because its speaking note could not be saved and attached.': 'Зустріч залишається активною в історії, оскільки нотатку для виступу не вдалося зберегти й прикріпити.',
    'Theme': 'Тема',
    'These fields come from the auth profile endpoint.': 'Ці поля надходять з API профілю автентифікації.',
    'This note changed on another device. Your local draft is safe. Reopen the note to review the server copy, or press Retry Save to overwrite after merging.': 'Цю нотатку змінено на іншому пристрої. Локальна чернетка в безпеці. Відкрийте нотатку знову, щоб переглянути серверну версію, або натисніть «Повторити збереження», щоб перезаписати її після об’єднання.',
    'This will remove “%@” from your history.': '«%@» буде видалено з вашої історії.',
    'Transcript': 'Транскрипт',
    'Translate': 'Перекласти',
    'Translation is off for this session.': 'Переклад вимкнено для цього сеансу.',
    'Translation off': 'Переклад вимкнено',
    'Translation on': 'Переклад увімкнено',
    'Translation: Off': 'Переклад: вимкнено',
    'Trialing': 'Пробний період',
    'Turn microphone off. Right-click to choose a microphone.': 'Вимкнути мікрофон. Клацніть правою кнопкою, щоб вибрати мікрофон.',
    'Turn microphone on. Right-click to choose a microphone.': 'Увімкнути мікрофон. Клацніть правою кнопкою, щоб вибрати мікрофон.',
    'Update %@': 'Оновити до %@',
    'Usage this period': 'Використання за цей період',
    'Use Google, Microsoft, Apple, or a Speechara email/password account.': 'Використовуйте Google, Microsoft, Apple або обліковий запис Speechara з електронною поштою та паролем.',
    'Use Test to verify the selected microphone before adding it to the live transcript.': 'Скористайтеся кнопкою «Тест», щоб перевірити вибраний мікрофон, перш ніж додавати його звук до транскрипту наживо.',
    'Used %@ min out of %@ min. %@ min remain in the current billing period.': 'Використано %@ хв із %@ хв. У поточному розрахунковому періоді залишилося %@ хв.',
    'Used %@ min out of %@ min. The billing limit has been reached.': 'Використано %@ хв із %@ хв. Ліміт поточного розрахункового періоду вичерпано.',
    'Verify and sign in': 'Підтвердити й увійти',
    'Verify your email': 'Підтвердьте електронну адресу',
    'View options': 'Параметри відображення',
    'Waiting for Apple...': 'Очікування Apple...',
    'Waiting for Google...': 'Очікування Google...',
    'Waiting for Google…': 'Очікування Google…',
    'Waiting for Microsoft...': 'Очікування Microsoft...',
    'Waiting for speech...': 'Очікування мовлення...',
    'We sent a code to %@.': 'Ми надіслали код на адресу %@.',
    'Without the microphone, Speechara will not capture what you say.': 'Без мікрофона Speechara не зможе записати те, що ви говорите.',
    'You can continue straight into the app and start a listening session without additional permission prompts.': 'Ви можете одразу перейти до застосунку й почати прослуховування без додаткових запитів дозволів.',
    'You can skip this once. Speechara will ask for microphone access later only if you enable microphone mix-in.': 'Цей крок можна пропустити. Speechara запросить доступ до мікрофона пізніше, лише якщо ви ввімкнете додавання звуку з мікрофона.',
    'Your login expired. Sign in again to continue.': 'Термін дії сеансу минув. Увійдіть знову, щоб продовжити.',
    'Your name': 'Ваше ім’я',
  },
}
const reviewedTranslations = {
  ar: {
    'History': 'السجل',
    'Theme': 'المظهر',
    'Light': 'فاتح',
    'Dark': 'داكن',
    'App language': 'لغة التطبيق',
  },
  be: {
    'Account': 'Уліковы запіс',
    'Billing': 'Аплата',
    'Light': 'Светлая',
    'Dark': 'Цёмная',
    'App language': 'Мова праграмы',
    'Close': 'Закрыць',
  },
  bg: {
    'Billing': 'Плащане',
    'Light': 'Светла',
    'Dark': 'Тъмна',
    'Sign out': 'Изход',
  },
  bn: {
    'Account': 'অ্যাকাউন্ট',
    'Light': 'হালকা',
    'Dark': 'গাঢ়',
  },
  bs: {
    'Account': 'Nalog',
    'Light': 'Svijetla',
    'Dark': 'Tamna',
  },
  ca: {
    'Light': 'Clar',
    'Dark': 'Fosc',
    'Language': 'Idioma',
  },
  cs: {
    'Light': 'Světlý',
    'Dark': 'Tmavý',
    'Sign out': 'Odhlásit se',
  },
  de: {
    'Close': 'Schließen',
  },
  el: {
    'History': 'Ιστορικό',
    'Light': 'Φωτεινό',
    'Dark': 'Σκούρο',
    'Sign out': 'Αποσύνδεση',
  },
  es: {
    'Settings': 'Configuración',
    'Sign out': 'Cerrar sesión',
  },
  et: {
    'Theme': 'Kujundus',
    'Light': 'Hele',
    'Dark': 'Tume',
  },
  fa: {
    'Theme': 'پوسته',
    'Light': 'روشن',
    'Dark': 'تیره',
  },
  fi: {
    'Light': 'Vaalea',
    'Dark': 'Tumma',
  },
  fr: {
    'Settings': 'Paramètres',
    'App language': 'Langue de l’application',
    'Sign out': 'Se déconnecter',
  },
  gu: {
    'Light': 'હળવી',
    'Dark': 'ઘેરી',
  },
  he: {
    'Theme': 'ערכת נושא',
    'Light': 'בהיר',
    'Dark': 'כהה',
    'Sign out': 'התנתקות',
  },
  hi: {
    'Light': 'हल्का',
    'Dark': 'गहरा',
  },
  hr: {
    'Account': 'Korisnički račun',
    'Light': 'Svijetla',
    'Dark': 'Tamna',
  },
  hu: {
    'History': 'Előzmények',
    'Settings': 'Beállítások',
    'Light': 'Világos',
    'Dark': 'Sötét',
    'App language': 'Alkalmazás nyelve',
    'Sign out': 'Kijelentkezés',
  },
  id: {
    'History': 'Riwayat',
    'Light': 'Terang',
    'Dark': 'Gelap',
  },
  it: {
    'History': 'Cronologia',
    'Account': 'Account',
    'Light': 'Chiaro',
    'Dark': 'Scuro',
  },
  ja: {
    'History': '履歴',
    'Light': 'ライト',
    'Dark': 'ダーク',
  },
  ko: {
    'History': '기록',
    'Light': '라이트',
    'Dark': '다크',
  },
  lt: {
    'Account': 'Paskyra',
    'Light': 'Šviesi',
    'Dark': 'Tamsi',
  },
  lv: {
    'Light': 'Gaiša',
    'Dark': 'Tumša',
    'App language': 'Lietotnes valoda',
  },
  mk: {
    'Light': 'Светла',
    'Dark': 'Темна',
    'Sign out': 'Одјави се',
  },
  ms: {
    'Light': 'Cerah',
    'Dark': 'Gelap',
  },
  nl: {
    'Account': 'Account',
    'Sign out': 'Afmelden',
  },
  no: {
    'Dark': 'Mørk',
  },
  pl: {
    'Light': 'Jasny',
    'Dark': 'Ciemny',
  },
  pt: {
    'History': 'Histórico',
    'Light': 'Claro',
    'Dark': 'Escuro',
  },
  ro: {
    'Settings': 'Setări',
    'Billing': 'Facturare',
    'Theme': 'Temă',
    'Light': 'Luminos',
    'Dark': 'Întunecat',
    'App language': 'Limba aplicației',
    'Sign out': 'Deconectare',
  },
  sk: {
    'Account': 'Účet',
    'Light': 'Svetlý',
    'Dark': 'Tmavý',
    'Sign out': 'Odhlásiť sa',
  },
  sl: {
    'Light': 'Svetla',
    'Dark': 'Temna',
    'Sign out': 'Odjava',
  },
  sr: {
    'Workspace': 'Радни простор',
    'Profile': 'Профил',
    'History': 'Историја',
    'Settings': 'Подешавања',
    'Account': 'Налог',
    'Billing': 'Наплата',
    'Theme': 'Тема',
    'Light': 'Светла',
    'Dark': 'Тамна',
    'Language': 'Језик',
    'App language': 'Језик апликације',
    'Sign out': 'Одјави се',
    'Close': 'Затвори',
  },
  sv: {
    'History': 'Historik',
    'Account': 'Konto',
    'Light': 'Ljust',
    'Dark': 'Mörkt',
    'Language': 'Språk',
    'Off': 'Av',
    'Open': 'Öppna',
    'Close': 'Stäng',
  },
  ta: {
    'Theme': 'தோற்றம்',
    'Light': 'வெளிர்',
    'Dark': 'கருமை',
    'Sign out': 'வெளியேறு',
  },
  te: {
    'Profile': 'ప్రొఫైల్',
    'Theme': 'థీమ్',
    'Light': 'లైట్',
    'Dark': 'డార్క్',
    'Sign out': 'సైన్ అవుట్',
  },
  th: {
    'Workspace': 'พื้นที่ทำงาน',
    'Theme': 'ธีม',
    'Light': 'สว่าง',
    'Dark': 'มืด',
    'Sign out': 'ออกจากระบบ',
  },
  tl: {
    'Profile': 'Profile',
    'Settings': 'Mga Setting',
    'Account': 'Account',
    'Billing': 'Pagsingil',
    'Light': 'Maliwanag',
    'Dark': 'Madilim',
    'Sign out': 'Mag-sign out',
    'Close': 'Isara',
  },
  tr: {
    'Active': 'Aktif',
    'Cancel': 'İptal',
    'Continue': 'Devam et',
    'Copy': 'Kopyala',
    'Email': 'E-posta',
    'Finish registration': 'Kaydı tamamla',
    'Input': 'Giriş',
    'Name': 'Ad',
    'Off': 'Kapalı',
    'Open': 'Aç',
    'Password': 'Şifre',
    'Profile': 'Profil',
    'History': 'Geçmiş',
    'Account': 'Hesap',
    'Light': 'Açık',
    'Dark': 'Koyu',
    'Language': 'Dil',
    'Recording on': 'Kayıt açık',
    'Summary': 'Özet',
    'Summary ready': 'Özet hazır',
    'Sign out': 'Çıkış',
    'Translation off': 'Çeviri kapalı',
    'Translation on': 'Çeviri açık',
    'Update': 'Güncelle',
    'Updates': 'Güncellemeler',
  },
  uk: {
    'Close': 'Закрити',
    '%@ translation': 'Переклад: %@',
    '%@ translation is unavailable: %@': 'Переклад мовою %@ недоступний: %@',
    '%@ translation was paused: %@': 'Переклад мовою %@ призупинено: %@',
    'Add a talking point': 'Додайте тезу',
    'Add talking point': 'Додати тезу',
    'Allow microphone access so Speechara can listen from the menu bar without requesting screen recording.': 'Дозвольте доступ до мікрофона, щоб Speechara могла слухати через рядок меню без запиту на запис екрана.',
    'Automatically show the floating listening window while a session is active.': 'Автоматично показувати плаваюче вікно прослуховування під час активного сеансу.',
    'Checking your Speechara account...': 'Перевірка облікового запису Speechara...',
    'Choose how Speechara looks and reads. Changes apply immediately.': 'Налаштуйте вигляд і мову Speechara. Зміни застосовуються відразу.',
    'Copy entire transcript': 'Копіювати весь транскрипт',
    'Copy entire translation': 'Копіювати весь переклад',
    'Could not attach the speaking note to this meeting: %@': 'Не вдалося прикріпити нотатку для виступу до цієї зустрічі: %@',
    'Current plan, billing period, and live transcription usage.': 'Поточний тариф, розрахунковий період і використання транскрипції наживо.',
    'Detected automatically': 'Розпізнано автоматично',
    'Draft a suggested reply to the latest question in this transcript.': 'Створити чернетку відповіді на останнє запитання в транскрипті.',
    'Drag window': 'Перетягнути вікно',
    'Exit': 'Вийти',
    'If you previously denied access, turn it back on in System Settings and return here.': 'Якщо ви раніше заборонили доступ, увімкніть його в Системних параметрах і поверніться сюди.',
    'Input: %@': 'Вхідна мова: %@',
    'Listening… Transcript will appear here.': 'Прослуховування… Транскрипт з’явиться тут.',
    'Live transcript with timestamped speech blocks.': 'Транскрипт наживо з часовими позначками для кожного фрагмента мовлення.',
    'Live translation and assist': 'Синхронний переклад і допомога',
    'Loading full session…': 'Завантаження повного сеансу…',
    'Looks at the latest transcript and suggests a natural response you can say on the call.': 'Аналізує останній транскрипт і пропонує природну відповідь для розмови.',
    'Meeting audio is active': 'Аудіо зустрічі активне',
    'Meeting ended?': 'Зустріч завершилася?',
    'Meeting notes available': 'Нотатки зустрічі доступні',
    'Meeting notes missing': 'Нотаток зустрічі немає',
    'Microphone access is active in this launch.': 'Доступ до мікрофона активний до завершення роботи застосунку.',
    'Microphone input': 'Вхід із мікрофона',
    'Microphone input is active for this launch.': 'Вхід із мікрофона активний до завершення роботи застосунку.',
    'Microphone is off. Your replies will not be included in the transcript.': 'Мікрофон вимкнено. Ваші репліки не потраплять до транскрипту.',
    'Microphone is on. Waiting for speech...': 'Мікрофон увімкнено. Очікування мовлення...',
    'Microphone live': 'Мікрофон активний',
    'Microphone mix-in': 'Додавання звуку з мікрофона',
    'New Session': 'Новий сеанс',
    'No answer suggestion yet.': 'Запропонованої відповіді ще немає.',
    'No authenticated account is available in the current desktop session.': 'У поточному сеансі застосунку немає автентифікованого облікового запису.',
    'No summary yet.': 'Підсумку ще немає.',
    'Open a recent note or prepare a new one before the meeting.': 'Відкрийте нещодавню нотатку або підготуйте нову перед зустріччю.',
    'Opening…': 'Відкриття…',
    'Password must be at least 8 characters.': 'Пароль має містити щонайменше 8 символів.',
    'Password must include a symbol.': 'Пароль має містити спеціальний символ.',
    'Prepare your first talking points or speech.': 'Підготуйте свої перші тези або промову.',
    'Preparing meeting notes...': 'Створення нотаток зустрічі...',
    'Primary AI action: draft a reply to the latest question.': 'Основна дія ШІ: створити відповідь на останнє запитання.',
    'Quit and reopen': 'Завершити роботу й відкрити знову',
    'Reply draft missing': 'Чернетки відповіді немає',
    'Reply draft ready': 'Чернетка відповіді готова',
    'Resend': 'Надіслати повторно',
    'Restoring your session…': 'Відновлення сеансу…',
    'Review your saved meetings, transcripts, translations, summaries, and follow-up notes.': 'Переглядайте збережені зустрічі, транскрипти, переклади, підсумки й нотатки для подальших дій.',
    'Save full M4A recording': 'Зберегти повний запис M4A',
    'Saved meeting sessions will appear here as soon as they are available in the backend.': 'Збережені сеанси зустрічей з’являться тут, щойно стануть доступними на сервері.',
    'Secondary AI actions': 'Додаткові дії ШІ',
    'Select microphone': 'Вибрати мікрофон',
    'Signal detected. Keep speaking.': 'Сигнал виявлено. Продовжуйте говорити.',
    'Speak now. Waiting for signal...': 'Говоріть. Очікування сигналу...',
    'Speechara asks for microphone input only when microphone mix-in or testing needs it.': 'Speechara запитує доступ до мікрофона лише для додавання вашого голосу або тестування.',
    'Speechara checks updates from updates.speechara.ai and will ask before installing a new version.': 'Speechara перевіряє оновлення на updates.speechara.ai і запитує підтвердження перед установленням нової версії.',
    'Speechara is still listening.': 'Speechara продовжує слухати.',
    'Speechara listens through the selected microphone without asking for screen recording access.': 'Speechara слухає через вибраний мікрофон, не запитуючи доступу до запису екрана.',
    'Speechara listens to system audio without asking for screen recording access.': 'Speechara слухає системний звук без запиту доступу до запису екрана.',
    'Speechara will listen through this input device.': 'Speechara отримуватиме звук із цього пристрою введення.',
    'Summary generated, but could not be saved: %@': 'Підсумок створено, але не вдалося зберегти: %@',
    'Summary missing': 'Підсумку немає',
    'System + microphone live': 'Системний звук і мікрофон активні',
    'System audio starts without screen recording. Microphone access can be enabled later.': 'Системний звук захоплюється без запису екрана. Доступ до мікрофона можна ввімкнути пізніше.',
    'Talking points': 'Тези',
    'The meeting window looks closed.': 'Схоже, вікно зустрічі закрито.',
    'The speaking notes server returned an invalid response.': 'Сервер нотаток для виступу повернув некоректну відповідь.',
    'The Speechara backend URL is invalid.': 'Некоректна URL-адреса сервера Speechara.',
    'The translation stays secondary to the live transcript and fills in only when final text is ready.': 'Переклад відображається як додаткова панель до транскрипту наживо й оновлюється після появи остаточного тексту.',
    'This page loads saved meeting sessions from the backend and shows a compact overview. Open any card to inspect the full transcript, translation, summary, protocol, and suggested reply.': 'На цій сторінці показано збережені сеанси зустрічей із сервера. Відкрийте картку, щоб переглянути транскрипт, переклад, підсумок, протокол і запропоновану відповідь.',
    'Translation will appear as you speak.': 'Переклад з’являтиметься під час мовлення.',
    'Translation will appear here as final transcript chunks arrive.': 'Переклад з’являтиметься тут після надходження остаточних фрагментів транскрипту.',
    'Turn On Microphone': 'Увімкнути мікрофон',
    'Verification code': 'Код підтвердження',
    'Verify code': 'Підтвердити код',
    'Waiting for audio': 'Очікування аудіо',
    'You can skip this once, but Speechara will ask for microphone access before it can listen.': 'Цей крок можна пропустити, але перед початком прослуховування Speechara попросить доступ до мікрофона.',
  },
  ur: {
    'Profile': 'پروفائل',
    'Billing': 'بلنگ',
    'Theme': 'تھیم',
    'Light': 'روشن',
    'Dark': 'گہرا',
    'Sign out': 'سائن آؤٹ',
    'Close': 'بند کریں',
  },
  vi: {
    'Workspace': 'Không gian làm việc',
    'Settings': 'Cài đặt',
    'Theme': 'Giao diện',
    'Light': 'Sáng',
    'Dark': 'Tối',
    'Sign out': 'Đăng xuất',
  },
  zh: {
    'Profile': '个人资料',
    'History': '历史记录',
    'Light': '浅色',
    'Dark': '深色',
    'Sign out': '退出登录',
  },
}
const requestedLocales = process.argv.slice(2).filter((argument) => !argument.startsWith('--'))
const targetLocales = requestedLocales.length ? requestedLocales : locales
const shouldRepairFallbacks = process.argv.includes('--repair')
for (const locale of targetLocales) {
  if (!locales.includes(locale)) throw new Error(`Unsupported locale: ${locale}`)
}

const require = createRequire(import.meta.url)
const ts = require(path.join(webProjectDirectory, 'node_modules/typescript'))

const importTypeScriptModule = async (file) => {
  const source = await fs.readFile(file, 'utf8')
  const javascript = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2023,
    },
    fileName: file,
  }).outputText
  const moduleUrl = `data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`
  return (await import(moduleUrl)).default
}

const flattenStrings = (value, currentPath = [], result = []) => {
  if (typeof value === 'string') {
    result.push({ path: currentPath.join('.'), value })
    return result
  }
  if (value && typeof value === 'object') {
    for (const [key, child] of Object.entries(value)) {
      flattenStrings(child, [...currentPath, key], result)
    }
  }
  return result
}

const swiftUnescape = (value) =>
  value
    .replaceAll('\\"', '"')
    .replaceAll('\\n', '\n')
    .replaceAll('\\t', '\t')
    .replaceAll('\\\\', '\\')

const collectSwiftFiles = async (directory) => {
  const entries = await fs.readdir(directory, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const itemPath = path.join(directory, entry.name)
    if (entry.isDirectory()) {
      files.push(...(await collectSwiftFiles(itemPath)))
    } else if (entry.isFile() && entry.name.endsWith('.swift')) {
      files.push(itemPath)
    }
  }
  return files
}

const collectMacKeys = async () => {
  const keys = new Set()
  const localizationSource = await fs.readFile(localizationSourceFile, 'utf8')

  // The curated dictionaries are the canonical inventory for SwiftUI strings
  // that rely on Bundle localization rather than explicit SL()/SLF() calls.
  const dictionaryKeyPattern = /^\s{12}"((?:\\.|[^"\\])+)":/gm
  for (const match of localizationSource.matchAll(dictionaryKeyPattern)) {
    keys.add(swiftUnescape(match[1]))
  }

  const explicitLocalizationPattern = /\bSLF?\(\s*"((?:\\.|[^"\\])*)"/g
  const swiftUIInitializerPattern = /\b(?:Text|Button|Label|Picker|Toggle|TextField|SecureField|GroupBox|ProgressView)\(\s*"((?:\\.|[^"\\])*)"/g
  const swiftUIModifierPattern = /\.(?:help|accessibilityLabel|accessibilityHint|navigationTitle|alert|confirmationDialog)\(\s*"((?:\\.|[^"\\])*)"/g
  const userFacingNamedArgumentPattern = /\b(?:title|help|prompt)\s*:\s*"((?:\\.|[^"\\])*)"/g
  for (const file of await collectSwiftFiles(swiftSourceDirectory)) {
    if (file === outputFile) continue
    const source = await fs.readFile(file, 'utf8')
    for (const pattern of [
      explicitLocalizationPattern,
      swiftUIInitializerPattern,
      swiftUIModifierPattern,
      userFacingNamedArgumentPattern,
    ]) {
      for (const match of source.matchAll(pattern)) {
        keys.add(swiftUnescape(match[1]))
      }
    }
  }

  return [...keys]
    .map((key) => key.trim())
    .filter((key) => key && !key.includes('\\('))
    .sort((left, right) => left.localeCompare(right, 'en'))
}

const placeholderPattern = /%(?:\d+\$)?(?:@|d|ld|lld|f|\.\d+f)|%%|\{\{[^}]+\}\}|https?:\/\/\S+/g
const protectedTokenPattern = /Speechara|%(?:\d+\$)?(?:@|d|ld|lld|f|\.\d+f)|%%|\{\{[^}]+\}\}|https?:\/\/\S+/g
const protectedTokenSplitPattern = /(Speechara|%(?:\d+\$)?(?:@|d|ld|lld|f|\.\d+f)|%%|\{\{[^}]+\}\}|https?:\/\/\S+)/g
const protectedTokenWholePattern = /^(?:Speechara|%(?:\d+\$)?(?:@|d|ld|lld|f|\.\d+f)|%%|\{\{[^}]+\}\}|https?:\/\/\S+)$/
const placeholders = (value) => (value.match(placeholderPattern) ?? []).sort()
const hasMatchingPlaceholders = (source, translation) =>
  JSON.stringify(placeholders(source)) === JSON.stringify(placeholders(translation))

const hasPathologicalRepetition = (source, translation) => {
  if (translation.length > Math.max(120, source.length * 5)) return true
  const words = translation.toLocaleLowerCase().match(/[\p{L}\p{M}]+/gu) ?? []
  if (words.length < 4) return false
  const counts = new Map()
  let consecutiveCount = 1
  for (let index = 0; index < words.length; index += 1) {
    counts.set(words[index], (counts.get(words[index]) ?? 0) + 1)
    if (index > 0 && words[index] === words[index - 1]) {
      consecutiveCount += 1
      if (consecutiveCount >= 3) return true
    } else {
      consecutiveCount = 1
    }
  }
  return Math.max(...counts.values()) / words.length > 0.65
}

const shouldTranslate = (value) =>
  /[A-Za-z]/.test(value) &&
  !/^(?:https?:\/\/|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,})/.test(value) &&
  !/^[A-Z\d_./:@ -]+$/.test(value)

const protectMachineTranslationTokens = (source) => {
  const tokens = []
  const text = source.replace(protectedTokenPattern, (token) => {
    const index = tokens.length
    tokens.push(token)
    return `\uE000${index}\uE001`
  })
  return {
    text,
    restore: (translation) => {
      let restored = translation
      tokens.forEach((token, index) => {
        restored = restored.replaceAll(`\uE000${index}\uE001`, token)
      })
      return restored
    },
  }
}

const createBatches = (entries, maxCharacters = 2500) => {
  const batches = []
  let batch = []
  let length = 0
  for (const entry of entries) {
    const nextLength = entry.source.length + (batch.length ? 1 : 0)
    if (batch.length && length + nextLength > maxCharacters) {
      batches.push(batch)
      batch = []
      length = 0
    }
    batch.push(entry)
    length += nextLength
  }
  if (batch.length) batches.push(batch)
  return batches
}

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds))

const bingUserAgent =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/151.0.4129.59'
const bingLanguageCodes = {
  no: 'nb',
  sr: 'sr-Cyrl',
  tl: 'fil',
  zh: 'zh-Hans',
}
const bingEPTLanguages = new Set([
  'ar', 'bn', 'bs', 'bg', 'ca', 'zh-Hans', 'hr', 'cs', 'da', 'nl', 'en',
  'et', 'fil', 'fi', 'fr', 'de', 'el', 'gu', 'he', 'hi', 'hu', 'id', 'it',
  'ja', 'kn', 'ko', 'lv', 'lt', 'ms', 'mr', 'nb', 'fa', 'pl', 'pt', 'ro',
  'ru', 'sr-Cyrl', 'sk', 'sl', 'es', 'sv', 'ta', 'te', 'th', 'tr', 'uk',
  'ur', 'vi',
])
let bingConfiguration
let bingRequestCount = 0

const bingCode = (locale) => bingLanguageCodes[locale] ?? locale
const maximumBatchLength = (locale) =>
  bingEPTLanguages.has(bingCode(locale)) ? 2000 : 700

const fetchBingConfiguration = async () => {
  const response = await fetch('https://bing.com/translator', {
    headers: { 'user-agent': bingUserAgent },
    redirect: 'follow',
    signal: AbortSignal.timeout(30_000),
  })
  if (!response.ok) throw new Error(`Could not open Bing Translator: HTTP ${response.status}`)
  const page = await response.text()
  const abuseMatch = page.match(/params_AbusePreventionHelper\s*=\s*(\[[^\]]+\])/)
  const IG = page.match(/IG:"([^"]+)"/)?.[1]
  const IID = page.match(/data-iid="([^"]+)"/)?.[1]
  if (!abuseMatch || !IG || !IID) throw new Error('Could not read Bing Translator configuration')
  const [key, token, expiry] = JSON.parse(abuseMatch[1])
  const host = new URL(response.url).host
  bingConfiguration = { IG, IID, key, token, expiry, fetchedAt: Date.now(), host }
  bingRequestCount = 0
  return bingConfiguration
}

const requestTranslation = async (text, locale, attempt = 1) => {
  try {
    if (
      !bingConfiguration ||
      Date.now() - bingConfiguration.fetchedAt > bingConfiguration.expiry
    ) {
      await fetchBingConfiguration()
    }
    const configuration = bingConfiguration
    const targetCode = bingCode(locale)
    const useEPT = bingEPTLanguages.has(targetCode) && text.length <= 3000
    bingRequestCount += 1
    const parameters = new URLSearchParams({
      isVertical: '1',
      IG: configuration.IG,
      IID: configuration.IID,
    })
    if (useEPT) {
      parameters.set('SFX', String(bingRequestCount))
      parameters.set('ref', 'TThis')
      parameters.set('edgepdftranslator', '1')
    }
    const body = new URLSearchParams({
      fromLang: 'en',
      text,
      to: targetCode,
      token: configuration.token,
      key: String(configuration.key),
      tryFetchingGenderDebiasedTranslations: 'true',
    })
    const response = await fetch(
      `https://${configuration.host}/ttranslatev3?${parameters}`,
      {
        body,
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
          referer: `https://${configuration.host}/translator`,
          'user-agent': bingUserAgent,
        },
        method: 'POST',
        signal: AbortSignal.timeout(30_000),
      },
    )
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const payload = await response.json()
    if (payload.ShowCaptcha) throw new Error('Bing Translator requested a captcha')
    const translated = payload?.[0]?.translations?.[0]?.text
    if (!translated) throw new Error(`Unexpected Bing Translator response: ${JSON.stringify(payload).slice(0, 240)}`)
    await delay(180)
    return translated
  } catch (error) {
    if (attempt >= 8) throw error
    process.stderr.write(
      `${locale}: translation request failed (attempt ${attempt}): ${error.message}\n`,
    )
    bingConfiguration = undefined
    await delay(Math.min(60_000, 2_000 * 2 ** (attempt - 1)))
    return requestTranslation(text, locale, attempt + 1)
  }
}

const translateProtectedSourceIndividually = async (source, locale) => {
  const parts = source.split(protectedTokenSplitPattern)
  const translatedParts = []
  for (const part of parts) {
    if (!part || protectedTokenWholePattern.test(part) || !/[A-Za-z]/.test(part)) {
      translatedParts.push(part)
      continue
    }
    const leadingWhitespace = part.match(/^\s*/)?.[0] ?? ''
    const trailingWhitespace = part.match(/\s*$/)?.[0] ?? ''
    const content = part.trim()
    translatedParts.push(
      content
        ? `${leadingWhitespace}${await requestTranslation(content, locale)}${trailingWhitespace}`
        : part,
    )
  }
  return translatedParts.join('')
}

const translateBatch = async (batch, locale) => {
  // Keep the framing attached to content: Bing drops delimiter-only lines but
  // preserves numbered-list prefixes while translating the text after them.
  const protectedEntries = batch.map((entry) =>
    protectMachineTranslationTokens(entry.source),
  )
  const source = protectedEntries
    .map((entry, index) => `[${index}] ${entry.text}`)
    .join('\n')
  const translated = await requestTranslation(source, locale)
  const parsedValues = new Map()
  const numberedValuePattern = /\[(\d+)\]\s*([\s\S]*?)(?=\[\d+\]\s*|$)/g
  for (const match of translated.matchAll(numberedValuePattern)) {
    parsedValues.set(Number(match[1]), match[2].trim())
  }
  const values = batch.map((_, index) => {
    const value = parsedValues.get(index)
    return value === undefined ? undefined : protectedEntries[index].restore(value)
  })
  if (values.some((value) => value === undefined)) {
    process.stderr.write(
      `${locale}: numbered-line mismatch for ${batch.length} strings; splitting batch\n`,
    )
    if (batch.length === 1) return [translated]
    const middle = Math.ceil(batch.length / 2)
    return [
      ...(await translateBatch(batch.slice(0, middle), locale)),
      ...(await translateBatch(batch.slice(middle), locale)),
    ]
  }
  return values
}

const safeTranslation = (source, translated) => {
  const candidate = translated.trim()
  if (!candidate || !hasMatchingPlaceholders(source, candidate)) return source
  if (source.includes('Speechara') && !candidate.includes('Speechara')) return source
  if (hasPathologicalRepetition(source, candidate)) return source
  return candidate
}

const sourceKeys = await collectMacKeys()
const sourceHash = crypto
  .createHash('sha256')
  .update(JSON.stringify(sourceKeys))
  .digest('hex')
const webEnglish = flattenStrings(
  await importTypeScriptModule(path.join(webLocalesDirectory, 'en.ts')),
)

const translateLocale = async (locale) => {
  const cacheFile = path.join(cacheDirectory, `${locale}.json`)
  let previousTranslations = {}
  try {
    const cached = JSON.parse(await fs.readFile(cacheFile, 'utf8'))
    if (cached.sourceHash === sourceHash || shouldRepairFallbacks) {
      if (shouldRepairFallbacks) {
        for (const source of sourceKeys) cached.translations[source] ??= source
        const fallbackSources = sourceKeys.filter(
          (source) =>
            shouldTranslate(source) && cached.translations[source] === source,
        )
        for (const source of fallbackSources) {
          const translation = await translateProtectedSourceIndividually(
            source,
            locale,
          )
          cached.translations[source] = safeTranslation(source, translation)
        }
        cached.sourceHash = sourceHash
        await fs.writeFile(cacheFile, JSON.stringify(cached, null, 2))
        const remainingCount = sourceKeys.filter(
          (source) =>
            shouldTranslate(source) && cached.translations[source] === source,
        ).length
        process.stdout.write(
          `${locale}: repaired ${fallbackSources.length - remainingCount} fallback(s), ${remainingCount} remain\n`,
        )
      }
      process.stdout.write(`${locale}: cache hit (${sourceKeys.length} strings)\n`)
      return Object.fromEntries(
        Object.entries(cached.translations).map(([source, translation]) => [
          source,
          hasPathologicalRepetition(source, translation) ? source : translation,
        ]),
      )
    }
    previousTranslations = cached.translations ?? {}
  } catch {}

  const webTarget = new Map(
    flattenStrings(
      await importTypeScriptModule(path.join(webLocalesDirectory, `${locale}.ts`)),
    ).map((entry) => [entry.path, entry.value]),
  )
  const webValueTranslations = new Map()
  for (const entry of webEnglish) {
    const target = webTarget.get(entry.path)
    if (target && !webValueTranslations.has(entry.value)) {
      webValueTranslations.set(entry.value, target)
    }
  }

  const translations = {}
  const missing = []
  let reusedCount = 0
  let cachedCount = 0
  for (const source of sourceKeys) {
    if (!shouldTranslate(source)) {
      translations[source] = source
      continue
    }
    const cachedTranslation = previousTranslations[source]
    if (
      typeof cachedTranslation === 'string' &&
      safeTranslation(source, cachedTranslation) !== source
    ) {
      translations[source] = cachedTranslation
      cachedCount += 1
      continue
    }
    const webTranslation = webValueTranslations.get(source)
    if (webTranslation && webTranslation !== source) {
      translations[source] = safeTranslation(source, webTranslation)
      if (translations[source] !== source) {
        reusedCount += 1
        continue
      }
    }
    missing.push({ source })
  }

  for (const batch of createBatches(missing, maximumBatchLength(locale))) {
    const translatedValues = await translateBatch(batch, locale)
    translatedValues.forEach((translation, index) => {
      const source = batch[index].source
      translations[source] = safeTranslation(source, translation)
    })
  }

  for (const source of sourceKeys) translations[source] ??= source
  await fs.mkdir(cacheDirectory, { recursive: true })
  await fs.writeFile(
    cacheFile,
    JSON.stringify({ sourceHash, translations }, null, 2),
  )
  const fallbackCount = sourceKeys.filter(
    (source) => translations[source] === source && shouldTranslate(source),
  ).length
  process.stdout.write(
    `${locale}: ${cachedCount} reused from cache, ${reusedCount} reused from web, ${missing.length} generated, ${fallbackCount} English fallback(s)\n`,
  )
  return translations
}

if (process.argv.includes('--analyze')) {
  const exactWebMatches = sourceKeys.filter((source) =>
    webEnglish.some((entry) => entry.value === source),
  )
  process.stdout.write(
    `${sourceKeys.length} Mac UI strings; ${exactWebMatches.length} exact web matches; ${sourceKeys.length - exactWebMatches.length} Mac-specific strings.\n`,
  )
  process.exit(0)
}

const generated = {}
const workerCount = Math.min(2, targetLocales.length)
let nextLocaleIndex = 0
await Promise.all(
  Array.from({ length: workerCount }, async () => {
    while (nextLocaleIndex < targetLocales.length) {
      const locale = targetLocales[nextLocaleIndex]
      nextLocaleIndex += 1
      generated[locale] = await translateLocale(locale)
    }
  }),
)

const orderedTranslations = Object.fromEntries(
  targetLocales.map((locale) => [
    locale,
    Object.fromEntries(
      sourceKeys.map((source) => [
        source,
        reviewedTranslations[locale]?.[source] ??
          manualTranslations[locale]?.[source] ??
          generated[locale][source] ??
          source,
      ]),
    ),
  ]),
)
await fs.mkdir(path.dirname(outputFile), { recursive: true })
await fs.writeFile(outputFile, `${JSON.stringify(orderedTranslations, null, 2)}\n`)
process.stdout.write(
  `Wrote ${outputFile} with ${targetLocales.length} locales and ${sourceKeys.length} source strings.\n`,
)
