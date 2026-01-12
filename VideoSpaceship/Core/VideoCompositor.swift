import Foundation
import AVFoundation
import CoreImage
import CoreMedia

class VideoCompositor {
    private let mode: RecordingMode
    private let pipSettings: PiPSettings
    
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private let outputURL: URL
    private var startTime: CMTime?
    private var frameCount: Int64 = 0
    
    private let ciContext = CIContext()
    private let compositorQueue = DispatchQueue(label: "com.videospaceship.compositor", qos: .userInitiated)
    
    init(mode: RecordingMode, pipSettings: PiPSettings) {
        self.mode = mode
        self.pipSettings = pipSettings
        
        // Create output file
        let tempDir = FileManager.default.temporaryDirectory
        self.outputURL = tempDir.appendingPathComponent("composite_\(UUID().uuidString).mov")
    }
    
    func start(screenRecorder: ScreenRecorder?, cameraRecorder: CameraRecorder?, audioRecorder: AudioRecorder?) async throws {
        // Setup asset writer
        try setupAssetWriter()
        
        // Setup callbacks
        cameraRecorder?.onSampleBuffer = { [weak self] sampleBuffer in
            self?.processCameraSample(sampleBuffer)
        }
        
        audioRecorder?.onSampleBuffer = { [weak self] sampleBuffer in
            self?.processAudioSample(sampleBuffer)
        }
    }
    
    func finalize() async -> URL? {
        await finishWriting()
        return outputURL
    }
    
    // MARK: - Asset Writer Setup
    
    private func setupAssetWriter() throws {
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Video settings - high quality H.264
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 15_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]
        
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true
        
        // Pixel buffer attributes
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        if let videoWriterInput = videoWriterInput, assetWriter?.canAdd(videoWriterInput) == true {
            assetWriter?.add(videoWriterInput)
        }
        
        // Audio settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256000
        ]
        
        audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioWriterInput?.expectsMediaDataInRealTime = true
        
        if let audioWriterInput = audioWriterInput, assetWriter?.canAdd(audioWriterInput) == true {
            assetWriter?.add(audioWriterInput)
        }
        
        assetWriter?.startWriting()
    }
    
    // MARK: - Sample Processing
    
    private func processCameraSample(_ sampleBuffer: CMSampleBuffer) {
        compositorQueue.async { [weak self] in
            self?.compositeFrame(cameraSample: sampleBuffer)
        }
    }
    
    private func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let audioWriterInput = audioWriterInput else { return }
        
        if startTime == nil {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            startTime = timestamp
            assetWriter?.startSession(atSourceTime: timestamp)
        }
        
        if audioWriterInput.isReadyForMoreMediaData {
            audioWriterInput.append(sampleBuffer)
        }
    }
    
    // MARK: - Frame Composition
    
    private func compositeFrame(cameraSample: CMSampleBuffer) {
        guard let pixelBufferAdaptor = pixelBufferAdaptor else { return }
        guard let videoWriterInput = videoWriterInput else { return }
        guard videoWriterInput.isReadyForMoreMediaData else { return }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(cameraSample)
        
        if startTime == nil {
            startTime = timestamp
            assetWriter?.startSession(atSourceTime: timestamp)
        }
        
        // Get camera pixel buffer
        guard let cameraPixelBuffer = CMSampleBufferGetImageBuffer(cameraSample) else { return }
        
        // Create composite pixel buffer
        guard let compositePixelBuffer = pixelBufferAdaptor.pixelBufferPool?.createPixelBuffer() else { return }
        
        // Composite the frame
        compositeFrameBuffers(
            camera: cameraPixelBuffer,
            output: compositePixelBuffer
        )
        
        // Append to writer
        pixelBufferAdaptor.append(compositePixelBuffer, withPresentationTime: timestamp)
        frameCount += 1
    }
    
    private func compositeFrameBuffers(camera: CVPixelBuffer, output: CVPixelBuffer) {
        let cameraImage = CIImage(cvPixelBuffer: camera)
        
        // Calculate PiP frame
        let outputSize = CGSize(width: CVPixelBufferGetWidth(output), height: CVPixelBufferGetHeight(output))
        let pipFrame = calculatePiPFrame(in: outputSize)
        
        // Scale and position camera
        let scaleX = pipFrame.width / cameraImage.extent.width
        let scaleY = pipFrame.height / cameraImage.extent.height
        let scaledCamera = cameraImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: pipFrame.origin.x, y: pipFrame.origin.y))
        
        // Apply shape mask
        let maskedCamera = applyShapeMask(to: scaledCamera, in: pipFrame)
        
        // Apply border and effects
        let styledCamera = applyPiPStyling(to: maskedCamera, in: pipFrame)
        
        // Render to output buffer
        ciContext.render(styledCamera, to: output)
    }
    
    private func calculatePiPFrame(in outputSize: CGSize) -> CGRect {
        let pipWidth = outputSize.width * pipSettings.size.scale
        let pipHeight = pipWidth / pipSettings.aspectRatio
        
        let padding: CGFloat = 40
        
        let x: CGFloat
        let y: CGFloat
        
        switch pipSettings.position {
        case .topLeft:
            x = padding
            y = outputSize.height - pipHeight - padding
        case .topRight:
            x = outputSize.width - pipWidth - padding
            y = outputSize.height - pipHeight - padding
        case .bottomLeft:
            x = padding
            y = padding
        case .bottomRight:
            x = outputSize.width - pipWidth - padding
            y = padding
        }
        
        return CGRect(x: x, y: y, width: pipWidth, height: pipHeight)
    }
    
    private func applyShapeMask(to image: CIImage, in frame: CGRect) -> CIImage {
        let maskImage: CIImage
        
        switch pipSettings.shape {
        case .circle:
            maskImage = createCircleMask(size: frame.size)
        case .roundedRectangle:
            maskImage = createRoundedRectMask(size: frame.size, cornerRadius: pipSettings.cornerRadius)
        case .square:
            return image
        }
        
        let maskFilter = CIFilter(name: "CIBlendWithMask")!
        maskFilter.setValue(image, forKey: kCIInputImageKey)
        maskFilter.setValue(CIImage(color: .clear).cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
        maskFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)
        
        return maskFilter.outputImage ?? image
    }
    
    private func createCircleMask(size: CGSize) -> CIImage {
        let renderer = CIContext()
        let minDimension = min(size.width, size.height)
        let rect = CGRect(x: 0, y: 0, width: minDimension, height: minDimension)
        
        // Create circle mask using Core Graphics
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(CGColor(gray: 1, alpha: 1))
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        
        return CIImage(image: image) ?? CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
    }
    
    private func createRoundedRectMask(size: CGSize, cornerRadius: CGFloat) -> CIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius)
            context.cgContext.setFillColor(CGColor(gray: 1, alpha: 1))
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()
        }
        
        return CIImage(image: image) ?? CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
    }
    
    private func applyPiPStyling(to image: CIImage, in frame: CGRect) -> CIImage {
        var styledImage = image
        
        // Apply border
        if pipSettings.borderWidth > 0 {
            // Border is applied as a stroke around the mask
            // This is a simplified version - full implementation would draw border
        }
        
        // Apply glow
        if pipSettings.glowEnabled {
            let glowFilter = CIFilter(name: "CIGaussianBlur")!
            glowFilter.setValue(image, forKey: kCIInputImageKey)
            glowFilter.setValue(10.0, forKey: kCIInputRadiusKey)
            
            if let glowImage = glowFilter.outputImage {
                let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
                compositeFilter.setValue(image, forKey: kCIInputImageKey)
                compositeFilter.setValue(glowImage, forKey: kCIInputBackgroundImageKey)
                styledImage = compositeFilter.outputImage ?? image
            }
        }
        
        // Apply shadow
        if pipSettings.shadowEnabled {
            // Shadow implementation
        }
        
        return styledImage
    }
    
    private func finishWriting() async {
        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        
        await assetWriter?.finishWriting()
    }
}

// MARK: - Extensions

extension CVPixelBufferPool {
    func createPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, self, &pixelBuffer)
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }
}

// Note: UIGraphicsImageRenderer is iOS-only, need to use NSGraphicsContext for macOS
#if os(macOS)
import AppKit

extension VideoCompositor {
    private func createCircleMask(size: CGSize) -> CIImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        NSColor.white.setFill()
        let path = NSBezierPath(ovalIn: CGRect(origin: .zero, size: size))
        path.fill()
        
        image.unlockFocus()
        
        return CIImage(data: image.tiffRepresentation!) ?? CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
    }
    
    private func createRoundedRectMask(size: CGSize, cornerRadius: CGFloat) -> CIImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        NSColor.white.setFill()
        let path = NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: cornerRadius, yRadius: cornerRadius)
        path.fill()
        
        image.unlockFocus()
        
        return CIImage(data: image.tiffRepresentation!) ?? CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
    }
}
#endif
