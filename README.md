# Video Spaceship (Swift)

A fully native Swift macOS application for high-performance screen recording with webcam overlay, audio mixing, and cloud uploads.

This project is a complete rewrite of the original [Video Spaceship Tauri app](https://github.com/davidsolheim/videospaceship-app) in native Swift, using modern Apple frameworks like SwiftUI, ScreenCaptureKit, and AVFoundation for maximum performance and deep OS integration.

## Features

- **Native Performance**: Built with Swift and SwiftUI for a fast, responsive, and resource-efficient experience.
- **High-Quality Recording**: Utilizes `ScreenCaptureKit` for high-fidelity screen recording at 60 FPS.
- **Picture-in-Picture (PiP)**: Overlay your webcam with customizable shapes, borders, and background effects (blur/remove).
- **Audio Mixing**: Capture microphone and system audio.
- **Hardware-Accelerated Encoding**: Compresses video using H.264/HEVC with hardware acceleration for a balance of quality and speed.
- **Local & Cloud Storage**: Save recordings locally or upload them securely to the cloud.
- **Modern UI**: A clean and intuitive interface built with SwiftUI.

## Project Structure

The project is organized into the following directories:

- `VideoSpaceship/App`: The main application entry point, AppDelegate, and scene configuration.
- `VideoSpaceship/Core`: Core application logic, including `RecordingManager`, `VideoProcessor`, and `AppState`.
- `VideoSpaceship/Features`: Self-contained feature modules (e.g., `Onboarding`, `Player`).
- `VideoSpaceship/UI`: SwiftUI views, components, and modifiers.
- `VideoSpaceship/Resources`: Asset catalog, fonts, and other resources.
- `VideoSpaceship/Services`: Services for interacting with external systems, like `AuthenticationManager` and `RecordingStorage`.
- `VideoSpaceship/Models`: Data models used throughout the application (e.g., `Recording`, `User`).
- `VideoSpaceship/Utilities`: Helper functions and extensions.

## Building and Running

This project is built using the Swift Package Manager.

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 14 or later

### Instructions

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/davidsolheim/video-spaceship-swift.git
    cd video-spaceship-swift
    ```

2.  **Open in Xcode:**

    You can open the `Package.swift` file directly in Xcode:

    ```bash
    xed .
    ```

3.  **Build and Run:**

    Select the `VideoSpaceship` target and your Mac as the run destination, then click the "Run" button (or press `Cmd+R`).

4.  **Command Line Build:**

    You can also build and run the application from the command line:

    ```bash
    swift build
    swift run
    ```

## Technical Details

- **UI Framework**: SwiftUI
- **Recording Engine**: `ScreenCaptureKit` for screen and system audio, `AVFoundation` for camera and microphone.
- **Video Composition**: `AVFoundation` and `CoreImage` for Picture-in-Picture (PiP) composition.
- **Video Processing**: `AVFoundation` and `VideoToolbox` for hardware-accelerated H.264/HEVC compression.
- **Authentication**: `Security` framework (Keychain) for secure token storage.
- **Dependencies**: 
    - `swift-async-algorithms`: For advanced asynchronous operations.
    - `swift-log`: For structured logging.



## Advanced Features (v2)

This version includes the full feature set from the roadmap, including:

- **Floating Control Bar**: A persistent on-screen panel for controlling recordings.
- **Recording Recovery**: Automatic recovery of interrupted or crashed recordings.
- **Region Selection**: Select a custom area of the screen to record.
- **Global Hotkeys**: System-wide keyboard shortcuts for all major actions.
- **Video Editing**: Basic trimming and cutting capabilities.
- **Visual Enhancements**: Cursor highlighting, click effects, and keystroke display.
- **Share Links**: Generate password-protected, expiring links for cloud recordings.
- **Team Collaboration**: Shared workspaces and team member management.
- **Platform Integrations**: Direct uploads to YouTube, Vimeo, Google Drive, and Dropbox.
- **Auto-Transcription**: On-device transcription with SRT/VTT export.
- **Smart Chapters**: Automatic chapter detection based on scene changes, silence, and topics.
- **Silence Removal**: Automatically remove dead air from recordings.

## Testing

A comprehensive testing plan is in place to ensure the quality and reliability of the application. See [TESTING.md](TESTING.md) for details on unit, integration, UI, and performance testing.
