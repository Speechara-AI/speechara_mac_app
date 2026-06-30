# Speechara macOS Version History

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
