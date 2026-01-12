# Video Spaceship Swift - Architecture Documentation

## Overview

Video Spaceship Swift is a native macOS application built entirely in Swift, designed for high-performance screen recording with advanced features like Picture-in-Picture webcam overlay, real-time background effects, and hardware-accelerated video processing.

## Architecture Principles

The application follows a modular, layered architecture that separates concerns and promotes maintainability. The architecture is built around the following principles:

### 1. **Native Performance First**

The application leverages Apple's native frameworks to achieve maximum performance and efficiency. By using `ScreenCaptureKit` for screen recording, `AVFoundation` for media processing, and `VideoToolbox` for hardware-accelerated encoding, the application can record at 60 FPS with minimal CPU overhead.

### 2. **SwiftUI-Driven UI**

The entire user interface is built with SwiftUI, providing a modern, declarative approach to UI development. This enables rapid iteration, automatic support for Dark Mode, and seamless integration with macOS system features.

### 3. **Reactive State Management**

The application uses Combine and SwiftUI's `@Published` properties to manage state reactively. This ensures that the UI automatically updates in response to state changes, reducing boilerplate code and preventing inconsistencies.

### 4. **Async/Await Concurrency**

All asynchronous operations use Swift's modern async/await concurrency model, making the code more readable and less prone to callback-related bugs.

## Core Components

### RecordingManager

The `RecordingManager` is the central orchestrator for all recording operations. It manages the lifecycle of recording sessions, coordinates between different recorders (screen, camera, audio), and handles the composition of the final video.

**Key Responsibilities:**
- Device discovery and selection
- Recording lifecycle management (start, pause, resume, stop)
- Coordination between screen, camera, and audio recorders
- Video composition and post-processing
- Error handling and recovery

### ScreenRecorder

The `ScreenRecorder` uses Apple's `ScreenCaptureKit` framework to capture screen content at high frame rates with minimal performance impact. It supports capturing entire displays or individual windows.

**Key Features:**
- 60 FPS screen capture at Retina resolution
- System audio capture
- Cursor visibility control
- Hardware-accelerated encoding

### CameraRecorder

The `CameraRecorder` captures video from the user's webcam using `AVFoundation`. It includes support for real-time background effects using Apple's Vision framework for person segmentation.

**Key Features:**
- High-quality camera capture
- Real-time background blur
- Real-time background removal
- Person segmentation using Vision framework

### AudioRecorder

The `AudioRecorder` captures audio from microphones and system audio. It supports multiple audio sources and can mix them together.

**Key Features:**
- Microphone capture
- System audio capture (via ScreenCaptureKit)
- Multi-source audio mixing
- Volume control per source

### VideoCompositor

The `VideoCompositor` combines the screen recording, camera feed, and audio into a single video file. It applies the Picture-in-Picture overlay with customizable styling.

**Key Features:**
- Real-time video composition
- PiP overlay with shapes (circle, rounded rectangle, square)
- Border, glow, and shadow effects
- Configurable position and size

### VideoProcessor

The `VideoProcessor` handles post-recording video processing, including compression and format conversion. It uses `AVFoundation` and `VideoToolbox` for hardware-accelerated encoding.

**Key Features:**
- H.264 and HEVC encoding
- Hardware acceleration
- Quality presets (low, medium, high, lossless)
- Progress tracking
- Thumbnail extraction

## Data Flow

The application follows a unidirectional data flow pattern:

1. **User Action** → User interacts with the UI (e.g., clicks "Start Recording")
2. **State Update** → The action triggers a state change in the `RecordingManager`
3. **Side Effect** → The state change triggers a side effect (e.g., starting the recording)
4. **State Propagation** → The updated state is propagated to the UI via `@Published` properties
5. **UI Update** → SwiftUI automatically re-renders the affected views

## Storage Architecture

The application supports two storage modes: local and cloud.

### Local Storage

Recordings are saved to a user-specified directory on the local file system. The `RecordingStorage` service manages the file operations and maintains a list of recordings in `UserDefaults`.

### Cloud Storage

Recordings can be uploaded to a cloud backend via a REST API. The upload process uses presigned URLs for secure, direct-to-S3 uploads. The `RecordingStorage` service handles the upload lifecycle, including progress tracking and error recovery.

## Authentication

The application uses OAuth-based authentication with token storage in the macOS Keychain. The `AuthenticationManager` handles the authentication flow, token validation, and session management.

**Authentication Flow:**
1. User clicks "Sign In"
2. App opens the authentication URL in the default browser
3. User completes authentication on the web
4. Browser redirects to a custom URL scheme (`videospaceship://auth`)
5. App receives the authentication token via the deep link
6. Token is validated and stored in Keychain

## Video Processing Pipeline

The video processing pipeline consists of several stages:

1. **Capture**: Screen, camera, and audio are captured in parallel
2. **Composition**: Camera feed is composited onto the screen recording with PiP styling
3. **Encoding**: The composite video is encoded in real-time to a temporary file
4. **Post-Processing**: The video is compressed and optimized for storage/upload
5. **Storage**: The final video is saved locally or uploaded to the cloud

## Performance Optimizations

### Hardware Acceleration

The application uses hardware-accelerated encoding wherever possible. `VideoToolbox` is used for H.264 and HEVC encoding, offloading the work to the GPU and reducing CPU usage.

### Asynchronous Processing

All video processing operations are performed asynchronously to avoid blocking the main thread. This ensures that the UI remains responsive even during intensive operations.

### Memory Management

The application uses `AVAssetWriter` with pixel buffer pools to minimize memory allocations during recording. Sample buffers are processed in a streaming fashion to avoid loading entire videos into memory.

### Background Effects

Person segmentation for background effects is performed at a reduced resolution and frame rate to balance quality and performance. The segmentation mask is cached and reused across frames when possible.

## Error Handling

The application uses Swift's `Result` type and structured error handling to manage errors gracefully. All errors are logged and presented to the user with actionable messages.

**Error Recovery Strategies:**
- **Recording Interruption**: Partial recordings are saved to disk and can be recovered
- **Upload Failure**: Failed uploads are queued and retried automatically
- **Permission Denial**: Users are prompted to grant necessary permissions

## Future Enhancements

The architecture is designed to support future enhancements, including:

- **Editing**: A timeline-based editor for trimming and annotating recordings
- **Live Streaming**: Real-time streaming to platforms like YouTube and Twitch
- **AI Features**: Auto-transcription, smart chapters, and silence removal
- **Team Collaboration**: Shared workspaces and team recording libraries

## Conclusion

Video Spaceship Swift is built on a solid architectural foundation that prioritizes performance, maintainability, and extensibility. By leveraging Apple's native frameworks and modern Swift language features, the application delivers a fast, reliable, and delightful user experience.
