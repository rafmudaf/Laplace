//
//  CameraController.swift
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 1/1/17.
//  Copyright © 2017 Rafael M Mudafort. All rights reserved.
//

import AVFoundation
import UIKit
import GLKit
import AssetsLibrary

let CameraControllerDidStartSession = "CameraControllerDidStartSession"
let CameraControllerDidStopSession = "CameraControllerDidStopSession"
let CameraControlObservableSettingLensPosition = "CameraControlObservableSettingLensPosition"
let CameraControlObservableSettingExposureTargetOffset = "CameraControlObservableSettingExposureTargetOffset"
let CameraControlObservableSettingExposureDuration = "CameraControlObservableSettingExposureDuration"
let CameraControlObservableSettingISO = "CameraControlObservableSettingISO"
let CameraControlObservableSettingWBGains = "CameraControlObservableSettingWBGains"
let CameraControlObservableSettingAdjustingFocus = "CameraControlObservableSettingAdjustingFocus"
let CameraControlObservableSettingAdjustingExposure = "CameraControlObservableSettingAdjustingExposure"
let CameraControlObservableSettingAdjustingWhiteBalance = "CameraControlObservableSettingAdjustingWhiteBalance"

protocol CameraControllerDelegate : class {
    func cameraController(cameraController:CameraController, didDetectFaces faces:Array<(id:Int,frame:CGRect)>)
    func cameraController(cameraController: CameraController, didOutputImage image: CIImage)
}

enum CameraControllePreviewType {
    case PreviewLayer
    case Manual
}

@objc protocol CameraSettingValueObserver {
    func cameraSetting(setting:String, valueChanged value:AnyObject)
}

extension AVCaptureWhiteBalanceGains {
    mutating func clampGainsToRange(minVal:Float, maxVal:Float) {
        blueGain = max(min(blueGain, maxVal), minVal)
        redGain = max(min(redGain, maxVal), minVal)
        greenGain = max(min(greenGain, maxVal), minVal)
    }
}

class WhiteBalanceValues {
    var temperature:Float
    var tint:Float
    
    init(temperature:Float, tint:Float) {
        self.temperature = temperature
        self.tint = tint
    }
    
    convenience init(temperatureAndTintValues:AVCaptureWhiteBalanceTemperatureAndTintValues) {
        self.init(temperature: temperatureAndTintValues.temperature, tint:temperatureAndTintValues.tint)
    }
}

class CameraController: NSObject {
    
    weak var delegate: CameraControllerDelegate?
    var previewType: CameraControllePreviewType
    
    var previewLayer: AVCaptureVideoPreviewLayer!
    var currentSampleBuffer: CMSampleBuffer?
    var newSampleBufferExists = false
    var currentlyRecording = false
    
    var enableBracketedCapture: Bool = false {
        didSet {
            // TODO: if true, prepare for capture
        }
    }
    
    var currentCameraDevice:AVCaptureDevice?
    
    // MARK: Private properties
    var sessionQueue = DispatchQueue(label: "com.example.session_access_queue")
    var session:AVCaptureSession!
    var backCameraDevice:AVCaptureDevice?
    var frontCameraDevice:AVCaptureDevice?
    var stillCameraOutput:AVCaptureStillImageOutput!
    var movieFileOutput:AVCaptureMovieFileOutput!
    var assetWriter:AVAssetWriter!
    var videoOutput:AVCaptureVideoDataOutput!
    var metadataOutput:AVCaptureMetadataOutput!
    var lensPositionContext = 0
    var adjustingFocusContext = 0
    var adjustingExposureContext = 0
    var adjustingWhiteBalanceContext = 0
    var exposureDuration = 0
    var ISO = 0
    var exposureTargetOffsetContext = 0
    var deviceWhiteBalanceGainsContext = 0
    var controlObservers = [String: [AnyObject]]()
    
    // MARK: - Initialization
    required init(previewType: CameraControllePreviewType, delegate: CameraControllerDelegate) {
        self.delegate = delegate
        self.previewType = previewType
        
        super.init()
        
        initializeSession()
    }
    
    convenience init(delegate: CameraControllerDelegate) {
        self.init(previewType: .PreviewLayer, delegate: delegate)
    }
    
    func initializeSession() {
        
        session = AVCaptureSession()
        if session.canSetSessionPreset(AVCaptureSessionPreset1280x720) {
//            session.sessionPreset = AVCaptureSessionPresetPhoto
            session.sessionPreset = AVCaptureSessionPreset1280x720
        }
        
        if previewType == .PreviewLayer {
            previewLayer = AVCaptureVideoPreviewLayer(session: self.session) as AVCaptureVideoPreviewLayer
        }
        
        let authorizationStatus = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        
        switch authorizationStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) { (granted: Bool) -> Void in
                if granted {
                    self.configureSession()
                }
                else {
                    self.showAccessDeniedMessage()
                }
            }
        case .authorized:
            configureSession()
        case .denied, .restricted:
            showAccessDeniedMessage()
        }
    }
    
    func switchCamera() {
        if session != nil {
            
            let currentCameraInput = session.inputs.first as! AVCaptureInput
            if self.currentCameraDevice?.position == .back {
                self.currentCameraDevice = self.frontCameraDevice
            } else if self.currentCameraDevice?.position == .front {
                self.currentCameraDevice = self.backCameraDevice
            }
            
            // Swap cameras
            session.beginConfiguration()
            session.removeInput(currentCameraInput)
            do {
                let possibleCameraInput = try AVCaptureDeviceInput(device: self.currentCameraDevice)
                if self.session.canAddInput(possibleCameraInput) {
                    self.session.addInput(possibleCameraInput)
                }
            } catch {
                print("error capturing the device \(error)")
            }
            session.commitConfiguration()
        }
    }
    
    // MARK: - Save Output
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
                self.assetWriter = try AVAssetWriter(outputURL: outputURL as URL, fileType: AVFileTypeQuickTimeMovie)
                let writerInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: nil)
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
                print("recording")
                
            } catch {
                
            }
        } else {
            // Stop recording
            assetWriter.inputs[0].markAsFinished()
            assetWriter.endSession(atSourceTime: CMTime(seconds: 10, preferredTimescale: 1))
            assetWriter.finishWriting(completionHandler: {
                UISaveVideoAtPathToSavedPhotosAlbum(outputPath, self, nil, nil)
                print("1")
            })
            currentlyRecording = false
        }
    }
    
    // MARK: - Camera Control
    func startRunning() {
        performConfiguration { () -> Void in
            self.observeValues()
            self.session.startRunning()
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: CameraControllerDidStartSession), object: self)
        }
    }
    
    func stopRunning() {
        performConfiguration { () -> Void in
            self.unobserveValues()
            self.session.stopRunning()
        }
    }
    
    func registerObserver<T>(observer:T, property:String) where T:NSObject, T:CameraSettingValueObserver {
        var propertyObservers = controlObservers[property]
        if propertyObservers == nil {
            propertyObservers = [AnyObject]()
        }
        
        propertyObservers?.append(observer)
        controlObservers[property] = propertyObservers
    }
    
    func unregisterObserver<T>(observer:T, property:String) where T:NSObject, T:CameraSettingValueObserver {
//		var indexes = [Int]()
        if let propertyObservers = controlObservers[property] {
            let filteredPropertyObservers = propertyObservers.filter({ (obs) -> Bool in
                obs as! NSObject != observer
            })
            controlObservers[property] = filteredPropertyObservers
        }
    }
    
    // MARK: Focus
    func enableContinuousAutoFocus() {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            if currentDevice.isFocusModeSupported(.continuousAutoFocus) {
                currentDevice.focusMode = .continuousAutoFocus
            }
        }
    }
    
    func isContinuousAutoFocusEnabled() -> Bool {
        return currentCameraDevice!.focusMode == .continuousAutoFocus
    }
    
    func lockFocusAtPointOfInterest(pointInView:CGPoint) {
        let pointInCamera = previewLayer.captureDevicePointOfInterest(for: pointInView)
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            if currentDevice.isFocusPointOfInterestSupported {
                currentDevice.focusPointOfInterest = pointInCamera
                currentDevice.focusMode = .autoFocus
            }
        }
    }
    
    func lockFocusAtLensPosition(lensPosition:CGFloat) {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            currentDevice.setFocusModeLockedWithLensPosition(Float(lensPosition)) {
                (time:CMTime) -> Void in
                
            }
        }
    }
    
    func currentLensPosition() -> Float? {
        return self.currentCameraDevice?.lensPosition
    }
    
    // MARK: Exposure
    func enableContinuousAutoExposure() {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            if currentDevice.isExposureModeSupported(.continuousAutoExposure) {
                currentDevice.exposureMode = .continuousAutoExposure
            }
        }
    }
    
    func isContinuousAutoExposureEnabled() -> Bool {
        return currentCameraDevice!.exposureMode == .continuousAutoExposure
    }
    
    func lockExposureAtPointOfInterest(pointInView:CGPoint) {
        let pointInCamera = previewLayer.captureDevicePointOfInterest(for: pointInView)
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            if currentDevice.isExposurePointOfInterestSupported {
                currentDevice.exposurePointOfInterest = pointInCamera
                currentDevice.exposureMode = .autoExpose
            }
        }
    }
    
    func setCustomExposureWithISO(iso:Float) {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            let activeFormat = currentDevice.activeFormat
            let isoScaled = iso*((activeFormat?.maxISO)!-(activeFormat?.minISO)!)+(activeFormat?.minISO)!
            currentDevice.setExposureModeCustomWithDuration(AVCaptureExposureDurationCurrent, iso: isoScaled, completionHandler: nil)
        }
    }
    
    func setCustomExposureWithDuration(duration:Float) {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            let activeFormat = currentDevice.activeFormat
            let finalDuration = CMTimeMakeWithSeconds(Float64(duration), 1_000_000)
            let durationRange = CMTimeRangeFromTimeToTime((activeFormat?.minExposureDuration)!, (activeFormat?.maxExposureDuration)!)
            
            if CMTimeRangeContainsTime(durationRange, finalDuration) {
                currentDevice.setExposureModeCustomWithDuration(finalDuration, iso: AVCaptureISOCurrent, completionHandler: nil)
            }
        }
    }
    
    func setExposureTargetBias(bias:Float) {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            currentDevice.setExposureTargetBias(bias, completionHandler: nil)
        }
    }
    
    func currentExposureDuration() -> Float? {
        if let exposureDuration = currentCameraDevice?.exposureDuration {
            return Float(CMTimeGetSeconds(exposureDuration))
        }
        else {
            return nil
        }
    }
    
    func currentISO() -> Float? {
        return currentCameraDevice?.iso
    }
    
    func currentExposureTargetOffset() -> Float? {
        return currentCameraDevice?.exposureTargetOffset
    }
    
    // MARK: White balance
    func enableContinuousAutoWhiteBalance() {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            if currentDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                currentDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
    }
    
    func isContinuousAutoWhiteBalanceEnabled() -> Bool {
        return currentCameraDevice!.whiteBalanceMode == .continuousAutoWhiteBalance
    }
    
    func setCustomWhiteBalanceWithTemperature(temperature:Float) {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            if currentDevice.isWhiteBalanceModeSupported(.locked) {
                let currentGains = currentDevice.deviceWhiteBalanceGains
                let currentTint = currentDevice.temperatureAndTintValues(forDeviceWhiteBalanceGains: currentGains).tint
                let temperatureAndTintValues = AVCaptureWhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: currentTint)
                
                var deviceGains = currentDevice.deviceWhiteBalanceGains(for: temperatureAndTintValues)
                let maxWhiteBalanceGain = currentDevice.maxWhiteBalanceGain
                deviceGains.clampGainsToRange(minVal: 1, maxVal: maxWhiteBalanceGain)
                
                currentDevice.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(deviceGains) {
                    (timestamp:CMTime) -> Void in
                }
            }
        }
    }
    
    func setCustomWhiteBalanceWithTint(tint:Float) {
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            if currentDevice.isWhiteBalanceModeSupported(.locked) {
                let maxWhiteBalanceGain = currentDevice.maxWhiteBalanceGain
                var currentGains = currentDevice.deviceWhiteBalanceGains
                currentGains.clampGainsToRange(minVal: 1, maxVal: maxWhiteBalanceGain)
                let currentTemperature = currentDevice.temperatureAndTintValues(forDeviceWhiteBalanceGains: currentGains).temperature
                let temperatureAndTintValues = AVCaptureWhiteBalanceTemperatureAndTintValues(temperature: currentTemperature, tint: tint)
                
                var deviceGains = currentDevice.deviceWhiteBalanceGains(for: temperatureAndTintValues)
                deviceGains.clampGainsToRange(minVal: 1, maxVal: maxWhiteBalanceGain)
                
                currentDevice.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(deviceGains) {
                    (timestamp:CMTime) -> Void in
                }
            }
        }
    }
    
    func currentTemperature() -> Float? {
        if let gains = currentCameraDevice?.deviceWhiteBalanceGains {
            let tempAndTint = currentCameraDevice?.temperatureAndTintValues(forDeviceWhiteBalanceGains: gains)
            return tempAndTint?.temperature
        }
        return nil
    }
    
    func currentTint() -> Float? {
        if let gains = currentCameraDevice?.deviceWhiteBalanceGains {
            let tempAndTint = currentCameraDevice?.temperatureAndTintValues(forDeviceWhiteBalanceGains: gains)
            return tempAndTint?.tint
        }
        return nil
    }
    
    // MARK: Still image capture
    func captureStillImage(completionHandler handler: @escaping ((_ image: UIImage, _ metadata: NSDictionary) -> Void)) {
        if enableBracketedCapture {
            bracketedCaptureStillImage(completionHandler: handler)
        }
        else {
            captureSingleStillImage(completionHandler: handler)
        }
    }
    
    /*!
     Capture a photo
     
     :param: handler executed on the main queue
     */
    func captureSingleStillImage(completionHandler handler: @escaping ((_ image: UIImage, _ metadata: NSDictionary) -> Void)) {
        sessionQueue.async() { () -> Void in
            
            let connection = self.stillCameraOutput.connection(withMediaType: AVMediaTypeVideo)
            
            connection?.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.current.orientation.rawValue)!
            
            self.stillCameraOutput.captureStillImageAsynchronously(from: connection) {
                (imageDataSampleBuffer, error) -> Void in
                
                if error == nil {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    
                    let metadata: NSDictionary = CMCopyDictionaryOfAttachments(nil, imageDataSampleBuffer!, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate))!//.takeUnretainedValue()
                    
                    if let image = UIImage(data: imageData!) {
                        DispatchQueue.main.async() { () -> Void in
                            handler(image, metadata)
                        }
                    }
                }
                else {
                    NSLog("error while capturing still image: \(String(describing: error))")
                }
            }
        }
    }
    
    func bracketedCaptureStillImage(completionHandler handler: @escaping ((_ image: UIImage, _ metadata: NSDictionary) -> Void)) {
        sessionQueue.async() { () -> Void in
            
            let connection = self.stillCameraOutput.connection(withMediaType: AVMediaTypeVideo)
            connection?.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.current.orientation.rawValue)!
            
            let settings = [-1.0, 0.0, 1.0].map {
                (bias:Float) -> AVCaptureAutoExposureBracketedStillImageSettings in
                
                AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(withExposureTargetBias: bias)
            }
            
            self.stillCameraOutput.captureStillImageBracketAsynchronously(from: connection, withSettingsArray: settings, completionHandler: {
                (sampleBuffer, captureSettings, error) -> Void in
                
                // TODO: stitch images
                
                if error == nil {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer)
                    
                    let metadata: NSDictionary = CMCopyDictionaryOfAttachments(nil, sampleBuffer!, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate))!//.takeUnretainedValue()
                    
                    if let image = UIImage(data: imageData!) {
                        DispatchQueue.main.async() { () -> Void in
                            handler(image, metadata)
                        }
                    }
                }
                else {
                    NSLog("error while capturing still image: \(String(describing: error))")
                }
            })
        }
    }
    
    
    // MARK: - Notifications
    func subjectAreaDidChange(notification:NSNotification) {
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        var key = ""
        var newValue = change![NSKeyValueChangeKey.newKey]!
        
//        switch context {
//        case lensPositionContext:
//            key = CameraControlObservableSettingLensPosition
//            
//        case exposureDuration:
//            key = CameraControlObservableSettingExposureDuration
//            
//        case ISO:
//            key = CameraControlObservableSettingISO
//            
//        case deviceWhiteBalanceGainsContext:
//            key = CameraControlObservableSettingWBGains            
////            if let newNSValue = newValue as? NSValue {
////                var gains: AVCaptureWhiteBalanceGains? = nil
////                newNSValue.getValue(&gains)
////                if let newTemperatureAndTint = currentCameraDevice?.temperatureAndTintValuesForDeviceWhiteBalanceGains(gains!) {
////                    newValue = WhiteBalanceValues(temperatureAndTintValues: newTemperatureAndTint)
////                }
////            }
//        case adjustingFocusContext:
//            key = CameraControlObservableSettingAdjustingFocus
//        case adjustingExposureContext:
//            key = CameraControlObservableSettingAdjustingExposure
//        case adjustingWhiteBalanceContext:
//            key = CameraControlObservableSettingAdjustingWhiteBalance
//        default:
//            key = "unknown context"
//        }
        
        notifyObservers(key: key, value: newValue as AnyObject)
    }
}

// MARK: - Delegate methods
extension CameraController: AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    func capture(_ output: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        return
    }
    
    @nonobjc func captureOutput(captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [AnyObject]!, fromConnection connection: AVCaptureConnection!) {
//        var faces = Array<(id:Int,frame:CGRect)>()
//        for metadataObject in metadataObjects as! [AVMetadataObject] {
//            if metadataObject.type == AVMetadataObjectTypeFace {
//                if let faceObject = metadataObject as? AVMetadataFaceObject {
//                    let transformedMetadataObject = previewLayer.transformedMetadataObjectForMetadataObject(metadataObject)
//                    let face:(id: Int, frame: CGRect) = (faceObject.faceID, transformedMetadataObject.bounds)
//                    faces.append(face)
//                }
//            }
//        }

//        if let delegate = self.delegate {
//            dispatch_async(dispatch_get_main_queue()) {
//                delegate.cameraController(self, didDetectFaces: faces)
//            }
//        }
    }
    
    internal func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        // use long exposure
        //*
        currentSampleBuffer = sampleBuffer
        newSampleBufferExists = true
        let uiimage = uiimageFromSampleBuffer(sampleBuffer: sampleBuffer)
        var ocvimage = CVWrapper.processImage(withOpenCV: uiimage)
        if self.currentCameraDevice?.position == .front {
            ocvimage = UIImage(cgImage: ocvimage!.cgImage!, scale: (ocvimage?.scale)!, orientation: .leftMirrored)
        }
        let ciimage = CIImage(image: ocvimage!)
        if ciimage != nil {
            self.delegate?.cameraController(cameraController: self, didOutputImage: ciimage!)
        }
    }
    
    func uiimageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> UIImage {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly)
        
        // Get the number of bytes per row for the pixel buffer
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!)
        
        // Get the number of bytes per row for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!)
        
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(imageBuffer!)
        let height = CVPixelBufferGetHeight(imageBuffer!)
        
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
        CVPixelBufferUnlockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly)
        
        // Create an image object from the Quartz image
        let image = UIImage(cgImage: quartzImage!)
//        let image = UIImage(CGImage: quartzImage!, scale: 1.0, orientation: UIImageOrientation.Right)
        
        return image
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        
        print("2")
        
        if error != nil {
            print("error in recording video: \(error)")
        }
        
//        let library = ALAssetsLibrary()
//        if library.videoAtPathIsCompatibleWithSavedPhotosAlbum(outputFileURL) {
//            library.writeVideoAtPathToSavedPhotosAlbum(outputFileURL, completionBlock: { (assetURL, error) in
//                if error != nil {
//                    print("error in saving video: \(error)")
//                }
//            })
//        }
    }
}

// MARK: - Private
private extension CameraController {
    func performConfiguration(block: @escaping (() -> Void)) {
        sessionQueue.async() { () -> Void in
            block()
        }
    }
    
    func performConfigurationOnCurrentCameraDevice(block: @escaping ((_ currentDevice: AVCaptureDevice) -> Void)) {
        if let currentDevice = self.currentCameraDevice {
            performConfiguration { () -> Void in
                do {
                    try currentDevice.lockForConfiguration()
                    block(currentDevice)
                    currentDevice.unlockForConfiguration()
                } catch {
                    print("error in performConfigurationOnCurrentCameraDevice")
                }
            }
        }
    }
    
    func configureSession() {
        configureDeviceInput()
        configureStillImageCameraOutput()
        configureFaceDetection()
//        configureMovieOutput()
        
        if previewType == .Manual {
            configureVideoOutput()
        }
    }
    
    func configureDeviceInput() {
        performConfiguration { () -> Void in
            
            let availableCameraDevices = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo)
            for device in availableCameraDevices as! [AVCaptureDevice] {
                if device.position == .back {
                    self.backCameraDevice = device
                }
                else if device.position == .front {
                    self.frontCameraDevice = device
                }
            }
            
            // let's set the back camera as the initial device
            self.currentCameraDevice = self.backCameraDevice
            do {
                let possibleCameraInput = try AVCaptureDeviceInput(device: self.currentCameraDevice)
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
            self.stillCameraOutput = AVCaptureStillImageOutput()
            self.stillCameraOutput.outputSettings = [
                AVVideoCodecKey  : AVVideoCodecJPEG,
                AVVideoQualityKey: 0.9
            ]
            
            if self.session.canAddOutput(self.stillCameraOutput) {
                self.session.addOutput(self.stillCameraOutput)
            }
        }
    }
    
    func configureVideoOutput() {
        performConfiguration { () -> Void in
            self.videoOutput = AVCaptureVideoDataOutput()
            
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as NSString: Int(kCVPixelFormatType_32BGRA)]

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
    
    func configureFaceDetection() {
        performConfiguration { () -> Void in
            self.metadataOutput = AVCaptureMetadataOutput()
            self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.sessionQueue)
            
            if self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
            }
            
//            if contains(self.metadataOutput.availableMetadataObjectTypes as! [NSString], AVMetadataObjectTypeFace) {
//                self.metadataOutput.metadataObjectTypes = [AVMetadataObjectTypeFace]
//            }
            self.metadataOutput.metadataObjectTypes = [AVMetadataObjectTypeFace]
        }
    }
    
    func observeValues() {
        currentCameraDevice?.addObserver(self, forKeyPath: "lensPosition", options: .new, context: &lensPositionContext)
        currentCameraDevice?.addObserver(self, forKeyPath: "adjustingFocus", options: .new, context: &adjustingFocusContext)
        currentCameraDevice?.addObserver(self, forKeyPath: "adjustingExposure", options: .new, context: &adjustingExposureContext)
        currentCameraDevice?.addObserver(self, forKeyPath: "adjustingWhiteBalance", options: .new, context: &adjustingWhiteBalanceContext)
        currentCameraDevice?.addObserver(self, forKeyPath: "exposureDuration", options: .new, context: &exposureDuration)
        currentCameraDevice?.addObserver(self, forKeyPath: "ISO", options: .new, context: &ISO)
        currentCameraDevice?.addObserver(self, forKeyPath: "deviceWhiteBalanceGains", options: .new, context: &deviceWhiteBalanceGainsContext)
    }
    
    func unobserveValues() {
        currentCameraDevice?.removeObserver(self, forKeyPath: "lensPosition", context: &lensPositionContext)
        currentCameraDevice?.removeObserver(self, forKeyPath: "adjustingFocus", context: &adjustingFocusContext)
        currentCameraDevice?.removeObserver(self, forKeyPath: "adjustingExposure", context: &adjustingExposureContext)
        currentCameraDevice?.removeObserver(self, forKeyPath: "adjustingWhiteBalance", context: &adjustingWhiteBalanceContext)
        currentCameraDevice?.removeObserver(self, forKeyPath: "exposureDuration", context: &exposureDuration)
        currentCameraDevice?.removeObserver(self, forKeyPath: "ISO", context: &ISO)
        currentCameraDevice?.removeObserver(self, forKeyPath: "deviceWhiteBalanceGains", context: &deviceWhiteBalanceGainsContext)
    }
    
    func showAccessDeniedMessage() {
        
    }
    
    func notifyObservers(key:String, value:AnyObject) {
        if let lensPositionObservers = controlObservers[key] {
            for obj in lensPositionObservers as [AnyObject] {
                if let observer = obj as? CameraSettingValueObserver {
                    notifyObserver(observer: observer, setting: key, value: value)
                }
            }
        }
    }
    
    func notifyObserver<T>(observer:T, setting:String, value:AnyObject) where T:CameraSettingValueObserver {
        observer.cameraSetting(setting: setting, valueChanged: value)
    }
}
