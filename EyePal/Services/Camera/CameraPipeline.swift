import AVFoundation
import CoreImage
import SwiftUI
import UIKit

final class CameraPipeline: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case configuring
        case running
        case failed(String)
        case unauthorized
    }

    let session = AVCaptureSession()

    @Published private(set) var state: State = .idle

    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.eyepals.camera.session")
    private let outputQueue = DispatchQueue(label: "com.eyepals.camera.output")
    private let latestFrameQueue = DispatchQueue(label: "com.eyepals.camera.latest-frame")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private var isConfigured = false
    private var latestSampleBuffer: CMSampleBuffer?

    func start() {
        sessionQueue.async {
            self.configureIfNeeded()
            guard self.state != .unauthorized else { return }
            guard self.isConfigured else { return }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.state = .running
            }
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.state = .idle
            }
        }
    }

    func currentFrameImage() -> UIImage? {
        guard let sampleBuffer = latestFrameQueue.sync(execute: { latestSampleBuffer }) else {
            return nil
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        DispatchQueue.main.async {
            self.state = .configuring
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    DispatchQueue.main.async {
                        self.state = .unauthorized
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        default:
            DispatchQueue.main.async {
                self.state = .unauthorized
            }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CameraError.noCameraAvailable
            }

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw CameraError.cannotAddInput
            }
            session.addInput(input)

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

            guard session.canAddOutput(videoOutput) else {
                throw CameraError.cannotAddOutput
            }
            session.addOutput(videoOutput)
            videoOutput.connection(with: .video)?.videoRotationAngle = 90

            session.commitConfiguration()
            isConfigured = true
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.state = .failed(error.localizedDescription)
            }
        }
    }
}

extension CameraPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        latestFrameQueue.sync {
            latestSampleBuffer = sampleBuffer
        }
        onSampleBuffer?(sampleBuffer)
    }
}

private enum CameraError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera is available on this device."
        case .cannotAddInput:
            return "The camera input could not be configured."
        case .cannotAddOutput:
            return "The camera output could not be configured."
        }
    }
}
