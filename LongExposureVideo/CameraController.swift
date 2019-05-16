//
//  CameraController.swift
//  LongExposureVideo
//
//  Created by Rafael M Mudafort on 1/1/17.
//  Copyright © 2017 Rafael M Mudafort. All rights reserved.
//
// metal references:
// http://metalbyexample.com/fundamentals-of-image-processing/
// http://metalbyexample.com/introduction-to-compute/
// https://www.invasivecode.com/weblog/metal-image-processing

import AVFoundation
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
    let imageWidth = 720
    let imageHeight = 1280
    
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
    var metalDevice: MTLDevice!
    var metalLibrary: MTLLibrary!
    var metalCommandQueue: MTLCommandQueue!
    var metalCommandBuffer: MTLCommandBuffer!
    var metalCommandEncoder: MTLComputeCommandEncoder!
    var metalKernelFunction: MTLFunction!
    var inTexture: MTLTexture!
    var outTexture: MTLTexture!
    let bytesPerPixel: Int = 4
    let threadGroupCount = MTLSizeMake(16, 16, 1)
    lazy var threadGroups = MTLSizeMake(imageWidth/threadGroupCount.width, imageHeight/threadGroupCount.height, 1)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
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
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal could not create device")
        }
        metalDevice = device
        
        guard let library = metalDevice.makeDefaultLibrary() else {
            fatalError("Metal could not create library")
        }
        metalLibrary = library
        
        guard let queue = metalDevice.makeCommandQueue() else {
            fatalError("Metal could not create command queue")
        }
        metalCommandQueue = queue
        
        guard let kernelFunction = metalLibrary.makeFunction(name: "processingKernel") else {
            fatalError("Metal could not create the kernal function")
        }
        metalKernelFunction = kernelFunction
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
    
    func captureStillImage(completionHandler handler: @escaping ((_ image: UIImage, _ metadata: NSDictionary) -> Void)) {
        sessionQueue.async() { () -> Void in
            self.stillCameraOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
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

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        guard let imageBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            fatalError("error converting CMSampleBuffer")
        }
        let ciimage = CIImage(cvPixelBuffer: imageBuffer)
        guard let uiimage = convert(ciimage: ciimage) else {
            fatalError("error converting CIImage to UIImage")
        }
        inTexture = texture(from: uiimage)
        
        executeMetalPipeline()

        let outimage = image(from: outTexture)
        if let ciimage = CIImage(image: outimage) {
            self.delegate?.cameraController(cameraController: self, didOutputImage: ciimage)
        }
    }
    
    func convert(ciimage: CIImage) -> UIImage? {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciimage, from: ciimage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    
    func image(from texture: MTLTexture) -> UIImage {
        
        // The total number of bytes of the texture
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        
        // The number of bytes for each image row
        let bytesPerRow = texture.width * bytesPerPixel
        
        // An empty buffer that will contain the image
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        
        // Gets the bytes from the texture
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // Creates an image context
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        let bitsPerComponent = 8
        guard let context = CGContext(data: &src, width: texture.width, height: texture.height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            fatalError("could not create cgcontext")
        }
        
        // Creates the image from the graphics context
        guard let dstImage = context.makeImage() else {
            fatalError("could not create image from cgcontext")
        }
        
        // Creates the final UIImage
        return UIImage(cgImage: dstImage, scale: 0.0, orientation: .up)
    }
    
    func texture(from image: UIImage) -> MTLTexture {
        
        guard let cgImage = image.cgImage else {
            fatalError("Can't open image \(image)")
        }
        
        let textureLoader = MTKTextureLoader(device: metalDevice)
        do {
            let textureOut = try textureLoader.newTexture(cgImage: cgImage, options: nil)
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: textureOut.pixelFormat, width: textureOut.width, height: textureOut.height, mipmapped: false)
            outTexture = metalDevice.makeTexture(descriptor: textureDescriptor)
            return textureOut
        } catch {
            fatalError("Can't load texture")
        }
    }
    
    func executeMetalPipeline() {
        
        // configure Metal pipeline
        guard let buffer = metalCommandQueue.makeCommandBuffer() else {
            fatalError("Metal could not create command buffer")
        }
        metalCommandBuffer = buffer
        
        
        guard let encoder = metalCommandBuffer.makeComputeCommandEncoder() else {
            fatalError("Metal could not create command encoder")
        }
        metalCommandEncoder = encoder
        
        do {
            let pipelineState = try metalDevice.makeComputePipelineState(function: metalKernelFunction)
            metalCommandEncoder.setComputePipelineState(pipelineState)
        } catch {
            fatalError("Metal could not add set the compute pipeline state")
        }
        
        // Encodes the input texture set it at location 0
        metalCommandEncoder.setTexture(inTexture, index: 0)
        
        // Encodes the output texture set it at location 1
        metalCommandEncoder.setTexture(outTexture, index: 1)
        
        // Encodes the dispatch of threadgroups
        metalCommandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        
        // Ends the encoding of the command
        metalCommandEncoder.endEncoding()
        
        // Commits the command to the command buffer
        metalCommandBuffer.commit()
        
        // Waits for the execution of the commands
        metalCommandBuffer.waitUntilCompleted()
        
        // for future reference ... the input buffer is more suited for gpgpu
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

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        return
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
}
