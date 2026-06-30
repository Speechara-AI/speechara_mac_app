# Speechara: detection of active meetings and meeting end prompts

Technical specification for implementing the same behavior in the Windows app.

## Goal

The app runs in the system tray and passively watches supported meeting apps. When a meeting is detected and Speechara is not listening yet, the app shows a prompt suggesting that the user start listening. When Speechara is already listening and the meeting appears to have ended, the app shows a prompt suggesting that the user stop listening.

This feature is not speech recognition and does not require analyzing meeting content. The detector only combines:

- supported meeting app process discovery;
- visible meeting-window detection;
- per-process audio-output activity;
- cooldowns and grace periods to avoid noisy prompts.

## Supported meeting apps

Current macOS implementation supports:

- Zoom;
- Cisco Webex.

Each detected process is normalized into an internal `MeetingApp` enum:

- `zoom`, display name `Zoom`;
- `webex`, display name `Cisco Webex`.

Windows implementation should start with the same list and keep the app matcher extensible.

### Process matching

Match a running process to a supported meeting app by executable name, product name, company name, or installed package identity.

Recommended Windows matching:

- Zoom: process name or file metadata contains `zoom`;
- Webex: process name or file metadata contains `webex` or `cisco`.

Examples:

- `Zoom.exe`, `Zoom Workplace`;
- `Webex.exe`, `CiscoCollabHost.exe`, other Cisco Webex helper processes if they own the meeting window or audio session.

If several helper processes exist, prefer the process that owns the visible meeting window or the active audio session.

## Detection sources

A detected meeting has one of two sources.

### 1. Window signal

This is the strongest signal. It means a supported meeting app owns a visible window whose title looks like an actual meeting.

Window must be:

- visible/on screen;
- a normal top-level app window;
- at least `360 x 220` px.

Zoom meeting title is accepted when it contains one of:

- `zoom meeting`;
- `zoom webinar`;
- `webinar`;
- `waiting room`;
- `meeting id`;
- standalone word `meeting` when the owner/process name contains `zoom`.

Webex meeting title is accepted when it contains one of:

- `webex meeting`;
- `meeting information`;
- `meeting details`;
- `personal room`;
- `webex call`;
- standalone word `meeting` when the owner/process name contains `webex`.

Ignore known non-meeting titles:

- empty title;
- `webex`;
- `cisco webex`;
- `zoom`;
- `zoom workplace`;
- `set a status`;
- `messaging`;
- `meetings`;
- any title containing `search, meet and call`.

### 2. Audio-output signal

This signal means a supported meeting app process is currently producing system audio. It is used when there is no reliable meeting-window title, but the app is outputting sound.

On macOS this is implemented through CoreAudio per-process output state. On Windows, implement the equivalent through WASAPI audio sessions:

1. Use `IMMDeviceEnumerator` to get the default render endpoint.
2. Activate `IAudioSessionManager2`.
3. Enumerate sessions through `IAudioSessionEnumerator`.
4. For each session, get `IAudioSessionControl2`.
5. Read `GetProcessId()` and map it back to a supported meeting process.
6. Use `IAudioMeterInformation::GetPeakValue()` or another reliable per-session activity indicator to decide whether the process is outputting audio.

Recommended Windows threshold:

- treat audio as active when session peak is above a small threshold, for example `0.005-0.02`, depending on empirical tests;
- require several consecutive polls before confirming if using volume peak instead of a binary output-state API.

The macOS behavior requires audio-only detections to remain stable for `6 seconds` before showing a start prompt. Keep the same stabilization period on Windows.

## Polling

Run a background detector while the app is alive in the tray.

Current timings:

- polling interval: `2 seconds`;
- timer leeway/jitter tolerance: about `250 ms`;
- audio-only confirmation interval: `6 seconds`;
- meeting-end grace interval: `60 seconds`;
- dismiss cooldown: `10 minutes`;
- repeated presentation cooldown: `2 minutes`.

The detector should be lightweight. Do not capture audio or record meeting content for this feature.

## Detected meeting model

Use a model equivalent to:

```text
DetectedMeeting
  meetingApp: zoom | webex
  appName: string
  processId: integer
  windowTitle: string?
  isAudioOutputActive: bool
  detectionSource: windowSignal | audioOutput
  key: "{meetingApp}:{processId}"
```

The `key` is used for prompt cooldowns and dismiss tracking.

## Start-listening prompt behavior

Show this prompt only when Speechara does not already have an active listening session.

Flow:

1. Every `2 seconds`, scan for a meeting.
2. If no meeting is found, clear pending audio-only first-seen state.
3. If the meeting was found by window signal, it can be presented immediately.
4. If the meeting was found only by audio output, remember first-seen timestamp and wait until it has been continuously observed for `6 seconds`.
5. Before showing the prompt, check cooldowns:
   - if user dismissed this meeting key less than `10 minutes` ago, do not show;
   - if this meeting key was already presented less than `2 minutes` ago, do not show;
   - if the same prompt is already visible, do not duplicate it.
6. Show a small top-right prompt.

Prompt content:

- title: `Meeting detected`;
- app name: detected display name, for example `Zoom` or `Cisco Webex`;
- optional subtitle when audio is active: `Meeting audio is active`;
- primary action: `Start Listening`;
- close action: `x`.

Start action:

- authenticate/refresh session if required by the app;
- start a listening session using the user's default "start with microphone" setting;
- open the mini listening window;
- close the prompt.

Dismiss action:

- store `dismissedMeetings[meeting.key] = now`;
- close the prompt.

## Meeting-end prompt behavior

Show this prompt only when Speechara already has an active listening session and system audio or microphone listening is active.

Do not show while the listening engine is busy starting/stopping.

Flow:

1. Every `2 seconds`, scan for a meeting.
2. If a start-listening prompt is visible, close it.
3. If a meeting is detected:
   - store it as `activeMeeting`;
   - update `activeMeetingLastSeenAt = now`;
   - close any visible end prompt for the same meeting, because the meeting is active again.
4. If no meeting is detected:
   - if there is no previous `activeMeeting`, do nothing;
   - if less than `60 seconds` passed since `activeMeetingLastSeenAt`, do nothing;
   - after `60 seconds`, show the meeting-end prompt, subject to cooldowns.
5. Before showing the prompt, check cooldowns:
   - if user dismissed this end prompt less than `10 minutes` ago, do not show;
   - if this end prompt was already presented less than `2 minutes` ago, do not show;
   - if the same end prompt is already visible, do not duplicate it.

Prompt content:

- title: `Meeting ended?`;
- app name: detected display name;
- subtitle: `Speechara is still listening.`;
- secondary action: `Keep Listening`;
- primary/destructive action: `Stop Listening`;
- close action: same as `Keep Listening`.

Stop action:

- stop the active Speechara listening session;
- clear active meeting tracking;
- close the prompt.

Keep Listening action:

- store `dismissedEndPrompts[meeting.key] = now`;
- set `activeMeetingLastSeenAt = now` so the next possible end prompt waits another grace period/cooldown;
- close the prompt.

## Tray behavior

The app must keep running after all windows are closed.

Tray icon behavior:

- idle: show Speechara icon;
- active listening: show Speechara icon plus active indication.

Current macOS UI adds:

- red dot;
- `Listening` text near the menu-bar icon.

Windows can adapt this to tray conventions:

- tray icon overlay/badge if available;
- tooltip text `Listening`;
- tray context menu state.

Tray context menu should include at least:

- `Start Listening` or `Stop Listening`;
- `Open Speechara`;
- disabled status item: `Ready to listen`, `Listening`, `Listening stopped`, or `Preparing session`;
- microphone selection if supported;
- settings;
- quit.

## Prompt placement and style

Current macOS implementation uses a floating non-activating panel:

- always above normal windows, near status bar level;
- visible on all spaces/full-screen auxiliary;
- positioned top-right of the visible work area;
- start prompt size: about `520 x 106`;
- end prompt size: about `540 x 116`.

Windows equivalent:

- use a borderless topmost notification window or native toast with app actions;
- preferred position: top-right of the current work area, with about `24 px` right margin and `18 px` top margin;
- do not steal focus from the active app;
- allow click actions;
- avoid showing duplicates.

If using native Windows toast notifications, ensure action callbacks can start/stop listening and cooldown state is updated on dismiss.

## State machine

```text
Idle / not listening
  poll detects no meeting
    stay idle
  poll detects meeting by window
    show Start Listening prompt, subject to cooldowns
  poll detects meeting by audio only
    wait until stable for 6s, then show Start Listening prompt

Start prompt visible
  user clicks Start Listening
    start listening, close prompt, enter Listening
  user dismisses
    close prompt, suppress same meeting key for 10min
  app starts listening elsewhere
    close prompt, enter Listening

Listening
  poll detects meeting
    remember activeMeeting and lastSeenAt
  poll no longer detects meeting for <60s
    keep listening silently
  poll no longer detects meeting for >=60s
    show Meeting End prompt, subject to cooldowns

End prompt visible
  user clicks Stop Listening
    stop listening, clear activeMeeting, close prompt, enter Idle
  user clicks Keep Listening or closes
    close prompt, suppress same end prompt for 10min
  meeting becomes detectable again
    close prompt, keep Listening
```

## Windows implementation notes

Recommended components:

- `System.Windows.Forms.NotifyIcon` or WinUI/WPF tray integration for system tray.
- `EnumWindows`, `IsWindowVisible`, `GetWindowText`, `GetWindowRect`, `GetWindowThreadProcessId` for visible-window detection.
- `Process.GetProcesses()` plus process metadata for supported app discovery.
- WASAPI Core Audio COM interfaces for per-process audio session detection:
  - `IMMDeviceEnumerator`;
  - `IMMDevice`;
  - `IAudioSessionManager2`;
  - `IAudioSessionEnumerator`;
  - `IAudioSessionControl2`;
  - `IAudioMeterInformation`.

Implementation detail:

- Audio sessions may be owned by child/helper processes. Maintain a process tree map so a Webex/Zoom helper process can be associated with the parent meeting app if necessary.
- Some apps may keep silent audio sessions alive. Prefer actual meter activity over only session existence.
- Use hysteresis:
  - active after N consecutive active polls or after the same audio session is active for `6 seconds`;
  - inactive only after no valid meeting window and no active audio for the `60 second` grace period.

## Privacy and permissions

This feature should not require microphone access and should not record or inspect audio content.

It only needs:

- list of running processes;
- visible window titles and bounds;
- audio session/process activity metadata.

The user-facing privacy statement can say that Speechara watches supported meeting apps and their audio activity to suggest starting or stopping listening.

## Acceptance criteria

1. With Speechara running only in the tray and no active session, starting a Zoom/Webex meeting window shows `Meeting detected`.
2. With no reliable meeting window title but Zoom/Webex producing audio, the prompt appears only after about `6 seconds` of stable audio activity.
3. Dismissing the start prompt suppresses prompts for the same app/process for `10 minutes`.
4. Starting listening from the prompt starts a normal Speechara listening session and opens the mini listening UI.
5. While Speechara is listening, closing/leaving the meeting does not immediately prompt.
6. If the meeting remains undetected for `60 seconds`, the app shows `Meeting ended?`.
7. `Keep Listening` suppresses the end prompt for the same app/process for `10 minutes`.
8. `Stop Listening` stops the active Speechara session.
9. Reappearing meeting audio/window closes any visible end prompt and updates the last-seen timestamp.
10. The detector does not record audio or send meeting metadata to backend services as part of this feature.

## Reference to macOS implementation

The current implementation is located in:

- `Speechara/SpeecharaApp.swift`
  - `MeetingApp`;
  - `DetectedMeeting`;
  - `MeetingDetectionStore`;
  - `SpeecharaMeetingDetectedPanelView`;
  - `SpeecharaMeetingEndedPanelView`.

Important constants:

```text
pollingInterval = 2s
audioOutputConfirmationInterval = 6s
meetingEndGraceInterval = 60s
dismissCooldown = 10min
presentCooldown = 2min
minimumMeetingWindowSize = 360x220
```
