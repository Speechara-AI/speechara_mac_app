# Speechara

Minimal native macOS SwiftUI MVP for a future live subtitles and translation tool.

## What this MVP does

- Shows a single macOS window built with SwiftUI.
- Requests macOS screen and system audio recording permission when needed.
- Requests microphone permission when you turn the microphone on during a live session.
- Opens a pre-start setup sheet before each listening session.
- Streams captured audio to Deepgram over WebSocket for live transcription using the selected source language.
- Can mix optional live microphone audio into the same transcription stream while the session is already running.
- Sends only final transcript chunks to DeepSeek for contextual translation when translation is enabled.
- Optionally saves a compressed `.m4a` file into `~/Downloads/Speechara/` when local audio saving is enabled for the session.
- Shows a live subtitle preview plus committed transcript lines and translated text in the UI.
- Displays the latest saved M4A path in the UI.

## Project structure

```text
Speechara.xcodeproj/        Xcode project
Speechara/
  SpeecharaApp.swift        App entry point
  Views/
    ContentView.swift              Main window UI
  ViewModels/
    SubtitleViewModel.swift        UI state, capture lifecycle, and Deepgram events
  Services/
    AudioSampleBufferConverter.swift Shared CMSampleBuffer -> PCM helpers
    AudioChunkEncoder.swift        Converts captured audio to 16 kHz mono linear16 chunks
    DeepSeekTranslationService.swift Stateless chat-completions translator with session history
    DeepgramLiveTranscriptionService.swift WebSocket client for Deepgram live results
    LocalAudioRecordingService.swift Writes optional local recordings from the mixed audio stream
    M4AAudioFileWriter.swift       Writes optional local M4A recordings during capture
    MicrophoneCaptureService.swift Captures microphone audio with AVAudioEngine
    MixedAudioStreamMixer.swift    Mixes system and microphone audio into one live stream
    SystemAudioCaptureService.swift ScreenCaptureKit setup and capture lifecycle
README.md
```

## How to open and run in Xcode

1. Install the full Xcode app on macOS if it is not installed yet.
2. Open `Speechara.xcodeproj` in Xcode.
3. Select the `Speechara` scheme.
4. Press `Cmd+R` or use `Product > Run`.

To enable live transcription in local development, add this environment variable in your Run scheme:

```text
DEEPGRAM_API_KEY=your_deepgram_key_here
DEEPSEEK_API_KEY=your_deepseek_key_here
```

For permission-sensitive local testing, the Debug build now also installs a stable copy to:

```bash
~/Applications/Speechara.app
```

That fixed path is the recommended app to launch when testing screen/system audio permissions, because macOS TCC can behave inconsistently with temporary app bundles inside Xcode `DerivedData`.

Optional terminal helpers:

```bash
open /Users/alexdem/projects/MacOsApp/Speechara.xcodeproj
```

If terminal builds point to Command Line Tools instead of full Xcode, switch the active developer directory after installing Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

After one successful Debug build in Xcode, you can launch the stable installed copy with:

```bash
open ~/Applications/Speechara.app
```

The stable installed copy is useful for macOS permissions, but it will not inherit Xcode scheme environment variables. For Deepgram testing, launch from the Xcode scheme that contains `DEEPGRAM_API_KEY`.
The DeepSeek translation feature also requires launching from the Xcode scheme that contains `DEEPSEEK_API_KEY`.

## How to build a standard DMG installer

To produce a drag-to-install `.dmg` that includes the app on the left and an `Applications` shortcut on the right, run:

```bash
./Scripts/create_dmg.sh
```

From Xcode you can also select the shared `Package DMG` scheme and press `Product > Build` (`Cmd+B`). That scheme builds the Release app, packages the DMG, and then reveals the finished file in Finder without opening the image.

The script builds the `Release` app, generates a simple installer background, configures the Finder window layout, and writes the final artifact to:

```bash
build/dmg/Speechara.dmg
```

Useful options:

```bash
./Scripts/create_dmg.sh --unsigned
./Scripts/create_dmg.sh --app /absolute/path/to/Speechara.app --skip-build
./Scripts/create_dmg.sh --no-layout
./Scripts/create_dmg.sh --reveal
```

Notes:

- `--no-layout` is useful in headless CI because the standard Finder layout step uses `osascript`.
- Even without the custom layout step, the generated image still contains the `Applications` shortcut for manual drag-and-drop install.
- For external distribution, sign and notarize the `.app` before shipping the DMG so Gatekeeper warnings stay minimal.

## Next development steps

1. Separate system and microphone speakers in the transcript so overlapping dialogue is easier to read.
2. Persist final transcript and translation segments with timestamps instead of only plain text lines.
3. Move the Deepgram and DeepSeek keys out of the Xcode scheme into Keychain or temporary-token auth for safer local distribution.
