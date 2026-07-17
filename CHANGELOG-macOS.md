# Speechara macOS Version History

## 1.1.0 - 2026-07-17

### Added
- Added synchronized live draft translation that appears together with the interim transcript and is replaced by the final corrected translation.
- Added automatic recovery for interrupted transcription and translation connections without stopping the active meeting session.
- Added session continuation prompts and microphone guidance when listening starts.

### Changed
- Moved interim speech directly into the main transcript and translation panels, with draft text shown in a secondary color until finalized.
- Separated live and final translation processing so final corrections cannot block the current live translation.
- Kept transcription and translation focused on the newest speech while preserving finalized meeting content.
- Made the floating mini window available only during active listening and only when the main Speechara window is minimized or fully covered.

### Fixed
- Fixed transcription and translation backlogs that could continue processing minutes after a meeting ended.
- Fixed live translation stalls, skipped phrases, stale responses, and automatic recovery after timeouts or socket disconnects.
- Fixed the main and floating Speechara windows appearing at the same time.
- Fixed floating-window detection when Speechara is covered by browsers, Microsoft Word, or Webex.
- Fixed a crash when starting listening from the meeting-detected notification.

## 1.0.17 - 2026-07-07

### Added
- Added live pipeline diagnostics for Deepgram audio streaming and live translation queues.
- Added an optional setting to disable the floating mini window.
- Added billing actions for updating Free plans and renewing expired plans during the beta period.

### Changed
- Kept live transcription near real time by bounding audio and translation backlogs under downstream slowdowns.
- Replaced the translation language toolbar abbreviation with a translation icon.
- Expanded interface localization coverage across workspace, profile, history, settings, authentication, and billing views.

### Fixed
- Fixed mini-window transcript and translation autoscroll.
- Fixed the mini window appearing when changing the app interface language.
- Fixed text clipping at the bottom of mini-window transcript panels.
- Fixed the microphone-off warning so it appears only when the microphone is disabled during an active session.
- Localized previously English-only New and Focus controls in non-English interfaces.

## 1.0.16 - 2026-07-01

### Fixed
- Enabled the Sparkle installer launcher service for sandboxed macOS updates.
- Added the required Sparkle installer communication entitlements.
- Preserved Sparkle helper signing requirements in Developer ID release builds.

## 1.0.15 - 2026-06-30

### Fixed
- Restored the sidebar Update button when a newer Sparkle update is available.
- Added a delayed startup update refresh so Sparkle can report available updates after launch.

## 1.0.14 - 2026-06-30

### Fixed
- Notarized and stapled the DMG container for website downloads.
- Published the update under a fresh versioned URL to avoid CDN cache drift.

## 1.0.13 - 2026-06-30

### Fixed
- Refreshed the macOS update package under a new versioned URL.
- Signed the DMG container in addition to the notarized app bundle.

## 1.0.12 - 2026-06-30

### Fixed
- Reposted the macOS update as a signed and notarized website release.
- Refreshed Sparkle update metadata so installed apps can update to the latest build.

## 1.0.11 - 2026-06-03

### Fixed
- Restored Sparkle in the macOS release target after the emergency 1.0.10 launch fix.
- Restored signed Sparkle appcast generation for future in-app updates.
- Added the Sparkle feed URL and public EdDSA key back to the macOS app bundle.

## 1.0.10 - 2026-06-03

### Fixed
- Fixed a macOS launch failure after updating to 1.0.9.
- Removed a restricted Apple Sign In entitlement from the Developer ID build until a matching distribution provisioning profile is configured.
- Removed the embedded Xcode development provisioning profile from Developer ID release packages.

## 1.0.9 - 2026-06-03

### Added
- Added Sign in with Apple authorization through the Speechara auth service.

### Changed
- Improved meeting and call history behavior.
- Moved the app settings button to the left sidebar.
- Refined the settings window.

### Fixed
- Fixed minor bugs and polish issues.

## 1.0.8 - 2026-06-03

### Fixed
- Restored the branded DMG installer window with the drag-to-Applications layout.
- Made DMG publishing avoid Finder volume-name collisions with older mounted Speechara installers.
- Preserved Finder layout metadata when compressing the final release DMG.

### Changed
- Published the latest macOS update as a signed and notarized Developer ID release.

## 1.0.6 - 2026-06-02

### Added
- Added an in-app Update button that appears in the sidebar when Sparkle detects a newer version.

### Changed
- Published macOS updates through the custom updates domain.

## 1.0.5 - 2026-06-02

### Fixed
- Improved the DMG installer presentation for website downloads.

## 1.0.4 - 2026-06-02

### Changed
- Switched macOS update publishing to signed and notarized DMG artifacts.
- Added stable website download metadata for the latest macOS build.

## 1.0.0 - 2026-05-28

### Added
- Initial Speechara macOS release.
- Live transcription workspace with Russian translation output.
- AI actions for summarizing, protocol generation, and suggested answers.
