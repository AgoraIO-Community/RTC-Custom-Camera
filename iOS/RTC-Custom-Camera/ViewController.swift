//
//  ViewController.swift
//  RTC-Custom-Camera
//
//  Created by Max Cobb on 14/11/2022.
//

import UIKit
import AgoraRtcKit
import AVKit

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var captureSession: AVCaptureSession!
    private var captureQueue: DispatchQueue!
    private var videoView: CustomVideoSourcePreview = CustomVideoSourcePreview(frame: .zero)
    private var agkit: AgoraRtcEngineKit!
    private var currentOutput: AVCaptureVideoDataOutput? {
        self.captureSession.outputs.first as? AVCaptureVideoDataOutput
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.addSubview(self.videoView)
        self.videoView.frame = .init(origin: .zero, size: .init(width: 200, height: 200))

        self.setupCamera()
    }

    func setupCamera() {
        let agkit = AgoraRtcEngineKit.sharedEngine(withAppId: <#Agora App Token#>, delegate: nil)
        agkit.setExternalVideoSource(true, useTexture: true, sourceType: .videoFrame)
        self.agkit = agkit

        guard let firstValidCamera = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .back
        ).devices.first else { fatalError("Cannot find above camera")}

        captureSession = AVCaptureSession()
        captureSession.usesApplicationAudioSession = false

        let captureOutput = AVCaptureVideoDataOutput()
        captureOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        if captureSession.canAddOutput(captureOutput) {
            captureSession.addOutput(captureOutput)
        }

        captureQueue = DispatchQueue(label: "MyCaptureQueue")

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoView.insertCaptureVideoPreviewLayer(previewLayer: previewLayer)
        self.startCapture(ofDevice: firstValidCamera)

        let medOpt = AgoraRtcChannelMediaOptions()
        medOpt.clientRoleType = .broadcaster
        self.agkit.joinChannel(byToken: <#Agora Token or nil#>, channelId: "test2", uid: 0, mediaOptions: medOpt)
    }

    open func startCapture(ofDevice device: AVCaptureDevice) {
        guard let currentOutput = self.currentOutput else {
            return
        }
        currentOutput.setSampleBufferDelegate(self, queue: self.captureQueue)

        captureQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.setCaptureDevice(device, ofSession: strongSelf.captureSession)
            strongSelf.captureSession.startRunning()
        }
    }

    func setCaptureDevice(_ device: AVCaptureDevice, ofSession captureSession: AVCaptureSession) {
        let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput
        guard let newInput = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        captureSession.beginConfiguration()
        if let currentInput = currentInput { captureSession.removeInput(currentInput) }
        if captureSession.canAddInput(newInput) { captureSession.addInput(newInput) }
        captureSession.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        DispatchQueue.main.async {[weak self] in
            guard let weakSelf = self else { return }

            weakSelf.myVideoCapture(
                didOutputSampleBuffer: pixelBuffer,
                // passing 90 as default portrait, handle rotations here.
                rotation: 90, timeStamp: time
            )
        }
    }
    /// This method receives the pixelbuffer, converts to `AgoraVideoFrame`, then pushes to Agora RTC.
    /// - Parameters:
    ///   - capture: Custom camera source for push.
    ///   - pixelBuffer: A reference to a Core Video pixel buffer object from the camera stream.
    ///   - rotation: Orientation of the incoming pixel buffer
    ///   - timeStamp: Timestamp when the pixel buffer was captured.
    public func myVideoCapture(
        didOutputSampleBuffer pixelBuffer: CVPixelBuffer,
        rotation: Int, timeStamp: CMTime
    ) {
        let videoFrame = AgoraVideoFrame()

        videoFrame.format = 12
        videoFrame.textureBuf = pixelBuffer
        videoFrame.time = timeStamp
        videoFrame.rotation = Int32(rotation)

        // once we have the video frame, we can push to agora sdk
        self.agkit.pushExternalVideoFrame(videoFrame)
    }
}

/// Class for previewing the custom camera feed.
class CustomVideoSourcePreview : UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func insertCaptureVideoPreviewLayer(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer?.removeFromSuperlayer()
        previewLayer.frame = bounds
        layer.insertSublayer(previewLayer, below: layer.sublayers?.first)
        self.previewLayer = previewLayer
    }

    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        previewLayer?.frame = bounds
    }
}
