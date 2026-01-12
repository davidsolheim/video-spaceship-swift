import Foundation
import AVFoundation
import CoreImage
import CoreML
import Vision

class CameraRecorder: NSObject {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sampleBufferDelegate: CameraSampleBufferDelegate?
    
    private var backgroundEffect: BackgroundEffect = .none
    private var isCapturing = false
    private var isPaused = false
    
    // Background segmentation
    private let segmentationRequest: VNGeneratePersonSegmentationRequest
    private let ciContext = CIContext()
    
    // Sample buffer callback
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    
    override init() {
        // Initialize segmentation request for background effects
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        
        super.init()
    }
    
    func start(device: AVCaptureDevice, backgroundEffect: BackgroundEffect) async throws {
        self.backgroundEffect = backgroundEffect
        
        // Create capture session
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        captureSession.beginConfiguration()
        
        // Set session preset for high quality
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        
        // Add video input
        let videoInput = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        // Add video output
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let queue = DispatchQueue(label: "com.videospaceship.camera", qos: .userInitiated)
        sampleBufferDelegate = CameraSampleBufferDelegate(recorder: self)
        videoOutput?.setSampleBufferDelegate(sampleBufferDelegate, queue: queue)
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        
        if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.commitConfiguration()
        
        // Start session
        captureSession.startRunning()
        isCapturing = true
    }
    
    func stop() async {
        guard isCapturing else { return }
        
        isCapturing = false
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    func pause() async {
        isPaused = true
    }
    
    func resume() async {
        isPaused = false
    }
    
    // MARK: - Sample Buffer Processing
    
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isCapturing, !isPaused else { return }
        
        // Apply background effect if needed
        let processedBuffer: CMSampleBuffer
        if backgroundEffect != .none {
            processedBuffer = applyBackgroundEffect(to: sampleBuffer) ?? sampleBuffer
        } else {
            processedBuffer = sampleBuffer
        }
        
        // Send to compositor
        onSampleBuffer?(processedBuffer)
    }
    
    // MARK: - Background Effects
    
    private func applyBackgroundEffect(to sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Perform person segmentation
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([segmentationRequest])
        } catch {
            print("Segmentation error: \(error)")
            return nil
        }
        
        guard let maskObservation = segmentationRequest.results?.first else { return nil }
        guard let maskPixelBuffer = maskObservation.pixelBuffer else { return nil }
        
        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        // Scale mask to match video size
        let scaleX = ciImage.extent.width / maskImage.extent.width
        let scaleY = ciImage.extent.height / maskImage.extent.height
        let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Apply effect based on type
        let outputImage: CIImage
        switch backgroundEffect {
        case .blur:
            outputImage = applyBlurEffect(to: ciImage, mask: scaledMask)
        case .remove:
            outputImage = applyRemoveEffect(to: ciImage, mask: scaledMask)
        case .none:
            outputImage = ciImage
        }
        
        // Render to pixel buffer
        guard let outputPixelBuffer = createPixelBuffer(from: outputImage) else { return nil }
        
        // Create new sample buffer with processed pixel buffer
        return createSampleBuffer(from: outputPixelBuffer, timing: sampleBuffer)
    }
    
    private func applyBlurEffect(to image: CIImage, mask: CIImage) -> CIImage {
        // Blur the background
        let blurFilter = CIFilter(name: "CIGaussianBlur")!
        blurFilter.setValue(image, forKey: kCIInputImageKey)
        blurFilter.setValue(25.0, forKey: kCIInputRadiusKey)
        let blurredBackground = blurFilter.outputImage!.cropped(to: image.extent)
        
        // Blend using mask
        let blendFilter = CIFilter(name: "CIBlendWithMask")!
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(blurredBackground, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        
        return blendFilter.outputImage!
    }
    
    private func applyRemoveEffect(to image: CIImage, mask: CIImage) -> CIImage {
        // Create transparent background
        let clearColor = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        let backgroundImage = CIImage(color: clearColor).cropped(to: image.extent)
        
        // Blend using mask
        let blendFilter = CIFilter(name: "CIBlendWithMask")!
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        
        return blendFilter.outputImage!
    }
    
    private func createPixelBuffer(from image: CIImage) -> CVPixelBuffer? {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        ciContext.render(image, to: buffer)
        return buffer
    }
    
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer, timing originalBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(originalBuffer, at: 0, timingInfoOut: &timingInfo)
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription!,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
}

// MARK: - Sample Buffer Delegate

class CameraSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var recorder: CameraRecorder?
    
    init(recorder: CameraRecorder) {
        self.recorder = recorder
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        recorder?.processSampleBuffer(sampleBuffer)
    }
}
