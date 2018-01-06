//
//  CameraController.swift
//  LongExposureVideo
//
//  Created by Rafael M Mudafort on 1/1/17.
//  Copyright © 2017 Rafael M Mudafort. All rights reserved.
//

import AVFoundation
import UIKit
import GLKit
import AssetsLibrary
import MetalKit

protocol CameraControllerDelegate : class {
    func cameraController(cameraController: CameraController, didOutputImage image: CIImage)
}

class CameraController: NSObject {
    
    weak var delegate: CameraControllerDelegate?
    
    var previewLayer: AVCaptureVideoPreviewLayer!
    var currentSampleBuffer: CMSampleBuffer?
    var newSampleBufferExists = false
    var currentlyRecording = false
    
    let assetManager = AssetManager()
    
    // AVCapture variables
    var sessionQueue = DispatchQueue(label: "session_access_queue")
    var currentCameraDevice: AVCaptureDevice?
    var session: AVCaptureSession!
    var backCameraDevice: AVCaptureDevice?
    var frontCameraDevice: AVCaptureDevice?
    var stillCameraOutput: AVCapturePhotoOutput!
    var movieFileOutput: AVCaptureMovieFileOutput!
    var assetWriter: AVAssetWriter!
    var videoOutput: AVCaptureVideoDataOutput!
    var metadataOutput: AVCaptureMetadataOutput!
    
    // Metal variables
    var device: MTLDevice!
    var defaultLibrary: MTLLibrary!
    var commandQueue: MTLCommandQueue?
    var commandBuffer: MTLCommandBuffer?
    var commandEncoder: MTLComputeCommandEncoder!
    
    required init(delegate: CameraControllerDelegate) {
        self.delegate = delegate
        super.init()
        initializeSession()
        initializeMetal()
    }
    
    func initializeSession() {
        
        stillCameraOutput = AVCapturePhotoOutput()
        
        session = AVCaptureSession()
        if session.canSetSessionPreset(AVCaptureSession.Preset.hd1280x720) {
            session.sessionPreset = AVCaptureSession.Preset.hd1280x720
        }
        
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        
        switch authorizationStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video) { (granted: Bool) -> Void in
                if granted {
                    self.configureSession()
                }
                else {
                    print("permission for camera not granted")
                }
            }
        case .authorized:
            configureSession()
        case .denied, .restricted:
            print("permission for camera not granted")
        }
    }
    
    func initializeMetal() {
        device = MTLCreateSystemDefaultDevice()
        defaultLibrary = device.makeDefaultLibrary()
        commandQueue = device.makeCommandQueue()
        guard let queue = commandQueue else {
            print("Metal could not create command queue")
            return
        }
        commandBuffer = queue.makeCommandBuffer()
        guard let buffer = commandBuffer else {
            print("Metal could not create command buffer")
            return
        }
        commandEncoder = buffer.makeComputeCommandEncoder()
        configureMetal()
    }
    
    func startRunning() {
        performConfiguration { () -> Void in
            self.session.startRunning()
        }
    }
    
    func stopRunning() {
        performConfiguration { () -> Void in
            self.session.stopRunning()
        }
    }
    
    func switchCamera() {
        guard let session = session else {
            print("error switching the camera: AVCaptureSession is nil")
            return
        }
        
        guard let currentCameraInput = session.inputs.first else {
            print("error switching the camera: session input is nil")
            return
        }
        
        guard let device = self.currentCameraDevice else {
            print("error switching the camera: camera device is nil")
            return
        }

        if device.position == .back {
            self.currentCameraDevice = self.frontCameraDevice
        } else if device.position == .front {
            self.currentCameraDevice = self.backCameraDevice
        }
        
        session.beginConfiguration()
        session.removeInput(currentCameraInput)
        do {
            let possibleCameraInput = try AVCaptureDeviceInput(device: self.currentCameraDevice!)
            if self.session.canAddInput(possibleCameraInput) {
                self.session.addInput(possibleCameraInput)
            }
        } catch {
            print("error capturing the device \(error)")
        }
        session.commitConfiguration()
    }
    
    func toggleRecording() {
        // Create temporary URL to record to
        let outputPath = String(format: "%@%@", NSTemporaryDirectory(), "output.mov")
        let outputURL = NSURL(fileURLWithPath: outputPath)
        let fileManager = FileManager.default

        if !currentlyRecording {

            // Make sure we can save at the given url
            if fileManager.fileExists(atPath: outputPath) {
                do {
                    print("removing item at path \(outputPath)")
                    try fileManager.removeItem(atPath: outputPath)
                } catch {
                    print("error removing item at path \(outputPath): \(error)")
                }
            }

            do {
                self.assetWriter = try AVAssetWriter(outputURL: outputURL as URL, fileType: AVFileType.mov)
                let writerInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: nil)
                writerInput.expectsMediaDataInRealTime = true

                if assetWriter.canAdd(writerInput) {
                    assetWriter.add(writerInput)
                }

//                let adaptor = AVAssetWriterInputPixelBufferAdaptor (
//                    assetWriterInput: writerInput,
//                    sourcePixelBufferAttributes: [
//                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
//                        kCVPixelBufferWidthKey as String: asset.size.width,
//                        kCVPixelBufferHeightKey as String: asset.size.height,
//                    ])
                assetWriter.startWriting()
                assetWriter.startSession(atSourceTime: kCMTimeZero)

                writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "VideoWriterQueue")) {
                    while writerInput.isReadyForMoreMediaData {
                        if self.newSampleBufferExists {
                            if let samplebuffer = self.currentSampleBuffer {
                                writerInput.append(samplebuffer)
                                self.currentSampleBuffer = nil
                                self.newSampleBufferExists = false
                            }
                        }
                    }
                }

                currentlyRecording = true

            } catch {

            }
        } else {
            // Stop recording
            assetWriter.inputs[0].markAsFinished()
            assetWriter.endSession(atSourceTime: CMTime(seconds: 10, preferredTimescale: 1))
            assetWriter.finishWriting(completionHandler: {
                UISaveVideoAtPathToSavedPhotosAlbum(outputPath, self, nil, nil)
            })
            currentlyRecording = false
        }
    }
    
    func captureStillImage(completionHandler handler: @escaping ((_ image: UIImage, _ metadata: NSDictionary) -> Void)) {
        sessionQueue.async() { () -> Void in
            self.stillCameraOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: CMSampleBuffer?, previewPhoto: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        guard error == nil, let sampleBuffer = photo else {
            print("error in didFinishProcessingPhotoSampleBuffer")
            return
        }
        
        guard let dataImage = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: sampleBuffer, previewPhotoSampleBuffer: nil) else {
            print("error in didFinishProcessingPhotoSampleBuffer converting to jpeg")
            return
        }
        
        let uiimage = UIImage(data: dataImage)
        
        var ocvimage = CVWrapper.processImage(withOpenCV: uiimage)
        if self.currentCameraDevice?.position == .front {
            ocvimage = UIImage(cgImage: ocvimage!.cgImage!, scale: (ocvimage?.scale)!, orientation: .leftMirrored)
        }
        
        guard let imageurl = assetManager.locallyStore(image: ocvimage, named: "1") else {
            print("error while saving photo to local storage")
            return
        }
        assetManager.saveImagesInPhotos(urls: [imageurl])
    }
}

extension CameraController: AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        return
    }
    
    internal func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        currentSampleBuffer = sampleBuffer
        newSampleBufferExists = true
        guard let uiimage = uiimageFromSampleBuffer(sampleBuffer: sampleBuffer) else {
            print("error in uiimageFromSampleBuffer")
            return
        }
        var ocvimage = CVWrapper.processImage(withOpenCV: uiimage)
        if self.currentCameraDevice?.position == .front {
            ocvimage = UIImage(cgImage: ocvimage!.cgImage!, scale: (ocvimage?.scale)!, orientation: .leftMirrored)
        }
        let ciimage = CIImage(image: ocvimage!)
        if ciimage != nil {
            self.delegate?.cameraController(cameraController: self, didOutputImage: ciimage!)
        }
    }
    
    func uiimageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("error in CMSampleBufferGetImageBuffer")
            return nil
        }
        
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags.readOnly)
        
        // Get the number of bytes per row for the pixel buffer
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        
        // Get the number of bytes per row for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        // Create a device-dependent RGB color space
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create a bitmap graphics context with the sample buffer data
        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
        //let bitmapInfo: UInt32 = CGBitmapInfo.alphaInfoMask.rawValue
        let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, releaseCallback: nil, releaseInfo: nil)
        
        // Create a Quartz image from the pixel data in the bitmap graphics context
        let quartzImage = context!.makeImage()
        
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags.readOnly)
        
        // Create an image object from the Quartz image
        let image = UIImage(cgImage: quartzImage!)
//        let image = UIImage(CGImage: quartzImage!, scale: 1.0, orientation: UIImageOrientation.Right)
        
        return image
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        if error != nil {
            print("error in recording video: \(error)")
        }
    }
}

// configuration methods
private extension CameraController {

    func performConfiguration(block: @escaping (() -> Void)) {
        sessionQueue.async() { () -> Void in
            block()
        }
    }
    
    func configureSession() {
        configureDeviceInput()
        configureStillImageCameraOutput()
        //        configureMovieOutput()
        configureVideoOutput()
    }
    
    func configureDeviceInput() {
        performConfiguration { () -> Void in
            
            // start the device configuration
            let deviceTypes: [AVCaptureDevice.DeviceType] = [AVCaptureDevice.DeviceType.builtInWideAngleCamera]
            let mediaType = AVMediaType.video
            var position: AVCaptureDevice.Position
            var discovery: AVCaptureDevice.DiscoverySession
            
            // configure the rear camera
            position = .back
            discovery = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: mediaType, position: position)
            for device in discovery.devices {
                if device.position == .back {
                    self.backCameraDevice = device
                }
            }
            
            // configure the front camera
            position = .front
            discovery = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: mediaType, position: position)
            for device in discovery.devices {
                if device.position == .front {
                    self.frontCameraDevice = device
                }
            }
            
            // set the back camera as the initial device
            self.currentCameraDevice = self.backCameraDevice
            do {
                let possibleCameraInput = try AVCaptureDeviceInput(device: self.currentCameraDevice!)
                let backCameraInput = possibleCameraInput
                if self.session.canAddInput(backCameraInput) {
                    self.session.addInput(backCameraInput)
                }
            } catch {
                print("error capturing the device \(error)")
            }
        }
    }
    
    func configureStillImageCameraOutput() {
        performConfiguration { () -> Void in
            if self.session.canAddOutput(self.stillCameraOutput) {
                self.session.addOutput(self.stillCameraOutput)
            }
        }
    }
    
    func configureVideoOutput() {
        performConfiguration { () -> Void in
            self.videoOutput = AVCaptureVideoDataOutput()
            self.videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) as String: Int(kCVPixelFormatType_32BGRA)]
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
        }
    }
    
    func configureMovieOutput() {
        performConfiguration { () -> Void in
            self.movieFileOutput = AVCaptureMovieFileOutput()
//            self.movieFileOutput.setOutputSettings(<#T##outputSettings: [NSObject : AnyObject]!##[NSObject : AnyObject]!#>, forConnection: <#T##AVCaptureConnection!#>)
            if self.session.canAddOutput(self.movieFileOutput) {
                self.session.addOutput(self.movieFileOutput)
            }
        }
    }
    
    func configureMetal() {
//        let kernelFunction = defaultLibrary?.makeFunction(name: "squareValueShader")
//        do {
//            var pipelineState = try device.makeComputePipelineState(function: kernelFunction!)
//        } catch {
//            return
//        }
//        let valueByteLength = inputarray.count*MemoryLayout.size(ofValue: inputarray[0])
//
//        // add the input array to the metal buffer
//        var inVectorBuffer = device.makeBuffer(bytes: &inputarray, length: valueByteLength, options: .storageModeShared)
//        commandEncoder.setBuffer(inVectorBuffer, offset: 0, index: 0)
//
//        // add the output array to the metal buffer
//        var outVectorBuffer = device.makeBuffer(bytes: &resultarray, length: valueByteLength, options: .storageModeShared)
//        commandEncoder.setBuffer(outVectorBuffer, offset: 0, index: 1)
    }
}
