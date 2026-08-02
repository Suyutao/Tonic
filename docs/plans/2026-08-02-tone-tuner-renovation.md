# Tone Tuner Renovation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn Tone Tuner into a focused, reliable iPhone tuner and metronome by removing invisible practice-history storage, making audio lifecycle and failure states explicit, and making the primary flows usable with Dynamic Type and accessibility settings.

**Architecture:** Keep the two existing SwiftUI tabs, but give both audio engines a shared lifecycle contract: explicit idle, starting, running, interrupted, failed, and stopped states. The tuner and metronome views own presentation while services own AVAudioSession setup, interruption recovery, and teardown. Remove SwiftData entirely because the selected product direction is an immediate-use tool, not a practice log.

**Tech Stack:** SwiftUI, AVFoundation, iOS 17 deployment target, Swift Testing or XCTest for pure pitch/state logic, Xcode Simulator plus a physical iPhone for microphone and audio-route validation.

---

## Product decisions

- Keep exactly two top-level destinations: 调音器 and 节拍器.
- Remove `PracticeSession` persistence and the model container. No silent data collection remains.
- Keep A4 reference pitch as a small menu with a visible selected state. Preserve the current three presets unless later testing shows a need for arbitrary values.
- Treat the pitch graph as optional secondary information. The first implementation should remove it from the default tuner surface; reintroduce it only if a concrete user task requires historical stability feedback.
- Use system controls and labels for actions. A control may retain an icon, but its accessibility name and visible state must be explicit.
- Leading Apple principles: Purpose, Agency, Responsibility, Flexibility, and Craft. Delight comes from immediate, trustworthy audio feedback rather than decoration.

## Task 1: Remove unused practice storage

**Files:**
- Delete: `ToneTuner/Models/PracticeSession.swift`
- Modify: `ToneTuner/ToneTunerApp.swift`
- Modify: `ToneTuner/Views/MetronomeView.swift`
- Modify: `ToneTuner.xcodeproj/project.pbxproj`

1. Remove the `SwiftData` import and `.modelContainer(for:)` from `ToneTunerApp`.
2. Remove `@Environment(\.modelContext)`, `startedAt`, `stopAndRecord`, and the `PracticeSession` insertion from `MetronomeView`.
3. Make stopping the metronome only stop audio and clear the local playback state.
4. Remove the model source reference from the Xcode project file and delete the model file.
5. Build the app for the iOS Simulator and verify the app launches without a model-container migration or schema error.

## Task 2: Define audio lifecycle and error reporting

**Files:**
- Modify: `ToneTuner/Services/PitchDetector.swift`
- Modify: `ToneTuner/Services/MetronomeEngine.swift`
- Create: `ToneTuner/Services/AudioSessionCoordinator.swift`
- Modify: `ToneTuner/Views/TunerView.swift`
- Modify: `ToneTuner/Views/MetronomeView.swift`

1. Add a small service-level state enum covering `idle`, `starting`, `running`, `interrupted`, `failed(String)`, and `stopped`.
2. Move shared `AVAudioSession` activation/deactivation and category changes into `AudioSessionCoordinator`; keep tuner input and metronome output configuration separate.
3. Observe `AVAudioSession.interruptionNotification`, `routeChangeNotification`, and media-services-reset notifications.
4. On interruption or route loss, stop or pause the engine, publish the resulting state, and expose a recover action. Never leave `isPlaying` or `isRunning` true when the engine is no longer producing audio.
5. Replace silent `catch` blocks with a user-facing error enum that distinguishes microphone unavailable, audio session unavailable, and engine start failure.
6. In the views, show a concise inline status near the primary action. Use a clear retry action for recoverable failures.
7. Stop the tuner when its view leaves the hierarchy and when the scene becomes inactive/backgrounded. Stop the metronome on the same lifecycle transition.
8. Releasing an engine must remove the installed input tap, deactivate the audio session when no tool is active, and reset published values.

## Task 3: Fix microphone permission flow

**Files:**
- Modify: `ToneTuner/Views/TunerView.swift`
- Modify: `ToneTuner/Services/PitchDetector.swift`

1. Request microphone access only from the start action, after the interface explains that the microphone is needed to identify the note.
2. Treat `.denied` and restricted/unavailable cases distinctly in the published state.
3. Replace the close-only alert with an explanation and a button that opens `UIApplication.openSettingsURLString`; keep Cancel as the non-destructive option.
4. After returning from Settings, refresh the permission state and allow the same primary action to retry without restarting the app.
5. Test first request, Allow, Don’t Allow, denial followed by Settings, and permission revoked while the app is suspended.

## Task 4: Rebuild the tuner surface around the primary task

**Files:**
- Modify: `ToneTuner/Views/TunerView.swift`
- Modify: `ToneTuner/Views/TunerDial.swift`
- Modify: `ToneTuner/Views/ToneTunerSurface.swift`

1. Keep the hierarchy as note name, frequency, cents offset, gauge, and one start/stop action.
2. Remove `PitchHistoryGraph` from the default screen and delete its unused implementation unless later testing gives it a specific responsibility.
3. Replace fixed text sizes and fixed vertical assumptions with semantic fonts and layout constraints that survive accessibility sizes.
4. Give the gauge a bounded Dynamic Type treatment: keep the visual instrument compact, expose the live reading as separate scalable text, and ensure the gauge never becomes the only source of information.
5. Use a `ScrollView` or a compact alternate layout for small-height landscape devices; verify the primary action remains above the system Tab Bar.
6. Keep the reference-pitch menu in the navigation toolbar in portrait and place it in a safe, non-overlapping area in landscape. Add a checkmark or `Picker` selection state.
7. Confirm the start/stop button has at least a 44-point hit target, an accessibility label, a state-specific value, and a hint that changes when permission is denied.
8. Validate light appearance, dark appearance, Increased Contrast, Reduce Motion, and Dynamic Type from default through accessibility-extra-extra-extra-large.

## Task 5: Rebuild the metronome interaction states

**Files:**
- Modify: `ToneTuner/Views/MetronomeView.swift`
- Modify: `ToneTuner/Services/MetronomeEngine.swift`

1. Keep BPM, tempo slider, time-signature picker, and one play/stop action as the complete primary surface.
2. Ensure tempo and time-signature changes have a predictable application point. If changes apply at the next bar, show that state in the interface; otherwise apply them immediately and reschedule the beat safely.
3. Make the active beat indicator supplemental: expose current beat and time signature as accessible text so color and animation are not required.
4. Add an explicit interrupted/failed state and a retry action.
5. Respect Reduce Motion by removing nonessential beat animation while retaining audio and text feedback.
6. Validate that stopping is immediate, starting always begins on beat one, and returning from background never presents a false playing state.

## Task 6: Localize and clarify product copy

**Files:**
- Modify: `ToneTuner.xcodeproj/project.pbxproj`
- Create: `ToneTuner/Localizable.xcstrings`
- Modify: `ToneTuner/Views/ContentView.swift`
- Modify: `ToneTuner/Views/TunerView.swift`
- Modify: `ToneTuner/Views/MetronomeView.swift`

1. Move user-facing strings into String Catalog entries for Simplified Chinese and English.
2. Localize `NSMicrophoneUsageDescription` in the generated Info.plist settings or an equivalent localized InfoPlist resource.
3. Use terminology consistently: “开始调音 / 停止调音”, “开始 / 停止”, “等待声音”, and “麦克风不可用”.
4. Keep accessibility labels and hints in the same localization system as visible text.
5. Build with both language settings and inspect permission, error, empty, running, and interrupted states.

## Task 7: Add testable seams and verification

**Files:**
- Create: `ToneTunerTests/PitchReadingTests.swift`
- Create: `ToneTunerTests/AudioStateTests.swift`
- Modify: `ToneTuner.xcodeproj/project.pbxproj`

1. Add a test target if the project does not already contain one.
2. Test note-name and cents calculations for A4 at 432, 440, and 442 Hz, boundary values around +/-5 cents, and negative MIDI notes.
3. Test service state transitions for start success, permission denial, engine failure, interruption, recovery, and stop.
4. Run the test target before UI verification and keep audio hardware calls behind injectable boundaries so tests do not require a microphone.
5. Build Debug and Release for the iOS Simulator with code signing disabled.
6. On a physical iPhone, verify microphone permission, wired/Bluetooth route changes, phone calls or Siri interruption, lock/background behavior, and switching between tabs.
7. Capture portrait, landscape, dark-mode, Increased Contrast, Reduce Motion, and largest Dynamic Type screenshots. Completion requires no clipped text, no obscured primary action, truthful audio state, and successful recovery after interruption.

## Suggested implementation order

1. Remove SwiftData and practice records.
2. Introduce audio lifecycle/state reporting.
3. Fix permission and Settings recovery.
4. Simplify and resize the tuner surface.
5. Correct metronome state and interruption behavior.
6. Add localization.
7. Add tests and perform device/screenshot verification.

Plan status: ready for implementation. This file was written locally; the project directory is not a Git repository, so no commit was created.
