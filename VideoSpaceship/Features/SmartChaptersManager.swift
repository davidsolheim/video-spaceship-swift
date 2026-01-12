import Foundation
import AVFoundation
import CoreImage
import Vision
import NaturalLanguage

class SmartChaptersManager: ObservableObject {
    static let shared = SmartChaptersManager()
    
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    
    private init() {}
    
    // MARK: - Chapter Detection
    
    func detectChapters(
        for recording: Recording,
        transcription: Transcription? = nil
    ) async throws -> [Chapter] {
        isAnalyzing = true
        analysisProgress = 0
        
        defer {
            isAnalyzing = false
        }
        
        var chapters: [Chapter] = []
        
        // Method 1: Scene change detection
        let sceneChapters = try await detectSceneChanges(videoURL: recording.url)
        chapters.append(contentsOf: sceneChapters)
        
        analysisProgress = 0.33
        
        // Method 2: Silence detection
        let silenceChapters = try await detectSilence(videoURL: recording.url)
        chapters.append(contentsOf: silenceChapters)
        
        analysisProgress = 0.66
        
        // Method 3: Topic segmentation (if transcription available)
        if let transcription = transcription {
            let topicChapters = detectTopicChanges(transcription: transcription)
            chapters.append(contentsOf: topicChapters)
        }
        
        analysisProgress = 1.0
        
        // Merge and deduplicate chapters
        chapters = mergeChapters(chapters)
        
        return chapters
    }
    
    // MARK: - Scene Change Detection
    
    private func detectSceneChanges(videoURL: URL) async throws -> [Chapter] {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        var chapters: [Chapter] = []
        var previousImage: CIImage?
        
        // Sample every 2 seconds
        let sampleInterval: Double = 2.0
        let totalSamples = Int(duration.seconds / sampleInterval)
        
        for i in 0..<totalSamples {
            let time = CMTime(seconds: Double(i) * sampleInterval, preferredTimescale: 600)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let ciImage = CIImage(cgImage: cgImage)
                
                if let previous = previousImage {
                    let difference = calculateImageDifference(previous, ciImage)
                    
                    // If difference is significant, mark as scene change
                    if difference > 0.3 {
                        chapters.append(Chapter(
                            id: UUID(),
                            title: "Scene \(chapters.count + 1)",
                            startTime: time.seconds,
                            type: .sceneChange
                        ))
                    }
                }
                
                previousImage = ciImage
            } catch {
                // Skip failed frames
                continue
            }
        }
        
        return chapters
    }
    
    private func calculateImageDifference(_ image1: CIImage, _ image2: CIImage) -> Double {
        // Simple difference calculation using histogram comparison
        let context = CIContext()
        
        guard let histogram1 = image1.applyingFilter("CIAreaHistogram"),
              let histogram2 = image2.applyingFilter("CIAreaHistogram") else {
            return 0
        }
        
        // Extract histogram data and compare
        // This is a simplified version - in production, you'd use more sophisticated comparison
        return 0.5 // Placeholder
    }
    
    // MARK: - Silence Detection
    
    private func detectSilence(videoURL: URL) async throws -> [Chapter] {
        let asset = AVAsset(url: videoURL)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()
        
        var chapters: [Chapter] = []
        var currentTime: Double = 0
        var silenceStart: Double?
        let sampleRate: Double = 44100.0
        let silenceThreshold: Float = 0.01
        let minSilenceDuration: Double = 2.0
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                
                data.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                }
                
                // Analyze audio level
                let samples = data.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
                let avgLevel = calculateAverageLevel(samples: Array(samples))
                
                if avgLevel < silenceThreshold {
                    if silenceStart == nil {
                        silenceStart = currentTime
                    }
                } else {
                    if let start = silenceStart {
                        let duration = currentTime - start
                        if duration >= minSilenceDuration {
                            chapters.append(Chapter(
                                id: UUID(),
                                title: "Chapter \(chapters.count + 1)",
                                startTime: currentTime,
                                type: .silence
                            ))
                        }
                        silenceStart = nil
                    }
                }
                
                currentTime += Double(samples.count) / sampleRate
            }
        }
        
        return chapters
    }
    
    private func calculateAverageLevel(samples: [Int16]) -> Float {
        let sum = samples.reduce(0.0) { $0 + abs(Float($1)) }
        return sum / Float(samples.count) / Float(Int16.max)
    }
    
    // MARK: - Topic Segmentation
    
    private func detectTopicChanges(transcription: Transcription) -> [Chapter] {
        var chapters: [Chapter] = []
        
        // Use NaturalLanguage framework for topic detection
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = transcription.text
        
        // Split text into sentences
        let sentences = transcription.text.components(separatedBy: ". ")
        var currentTopic: String?
        var topicStartTime: TimeInterval = 0
        
        for (index, sentence) in sentences.enumerated() {
            tagger.string = sentence
            
            // Extract keywords
            var keywords: [String] = []
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
                if tag == .noun || tag == .verb {
                    keywords.append(String(sentence[range]))
                }
                return true
            }
            
            // Determine if topic has changed
            let topic = keywords.prefix(3).joined(separator: " ")
            
            if let current = currentTopic, current != topic {
                // Topic changed - create chapter
                let segment = transcription.segments[min(index, transcription.segments.count - 1)]
                chapters.append(Chapter(
                    id: UUID(),
                    title: current,
                    startTime: topicStartTime,
                    type: .topic
                ))
                topicStartTime = segment.startTime
            }
            
            currentTopic = topic
        }
        
        return chapters
    }
    
    // MARK: - Chapter Merging
    
    private func mergeChapters(_ chapters: [Chapter]) -> [Chapter] {
        // Sort by start time
        let sorted = chapters.sorted { $0.startTime < $1.startTime }
        
        var merged: [Chapter] = []
        var lastTime: TimeInterval = 0
        let minGap: TimeInterval = 10.0 // Minimum 10 seconds between chapters
        
        for chapter in sorted {
            if chapter.startTime - lastTime >= minGap {
                merged.append(chapter)
                lastTime = chapter.startTime
            }
        }
        
        // Rename chapters sequentially
        for (index, _) in merged.enumerated() {
            merged[index].title = "Chapter \(index + 1)"
        }
        
        return merged
    }
}

// MARK: - Models

struct Chapter: Identifiable, Codable {
    let id: UUID
    var title: String
    let startTime: TimeInterval
    let type: ChapterType
    
    var formattedTime: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum ChapterType: String, Codable {
    case sceneChange = "Scene Change"
    case silence = "Silence"
    case topic = "Topic"
    case manual = "Manual"
}

// MARK: - Chapter Editor View

import SwiftUI

struct ChapterEditorView: View {
    let recording: Recording
    @State private var chapters: [Chapter] = []
    @State private var isAnalyzing = false
    
    @StateObject private var manager = SmartChaptersManager.shared
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Chapters")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    generateChapters()
                } label: {
                    if isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Auto-Generate", systemImage: "sparkles")
                    }
                }
                .disabled(isAnalyzing)
                
                Button {
                    addManualChapter()
                } label: {
                    Label("Add Chapter", systemImage: "plus")
                }
            }
            .padding()
            
            if chapters.isEmpty {
                Text("No chapters yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(chapters) { chapter in
                        ChapterRow(chapter: chapter)
                    }
                    .onDelete { indexSet in
                        chapters.remove(atOffsets: indexSet)
                    }
                }
            }
            
            HStack {
                Button("Export") {
                    exportChapters()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func generateChapters() {
        isAnalyzing = true
        
        Task {
            do {
                // Try to get transcription first
                let transcription = try? await transcriptionManager.transcribe(recording: recording)
                
                chapters = try await manager.detectChapters(
                    for: recording,
                    transcription: transcription
                )
            } catch {
                AppState.shared.showError("Failed to generate chapters: \(error.localizedDescription)")
            }
            
            isAnalyzing = false
        }
    }
    
    private func addManualChapter() {
        let chapter = Chapter(
            id: UUID(),
            title: "New Chapter",
            startTime: 0,
            type: .manual
        )
        chapters.append(chapter)
    }
    
    private func exportChapters() {
        // Export chapters as JSON or text file
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        if let data = try? encoder.encode(chapters),
           let json = String(data: data, encoding: .utf8) {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "\(recording.title)_chapters.json"
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                try? json.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct ChapterRow: View {
    let chapter: Chapter
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(chapter.title)
                    .font(.headline)
                
                HStack {
                    Text(chapter.formattedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(chapter.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
