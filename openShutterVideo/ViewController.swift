//
//  ViewController.swift
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 3/6/16.
//  Copyright © 2016 Rafael M Mudafort. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    
    let captureSession = AVCaptureSession()
    var captureDevice: AVCaptureDevice?
    var previewLayer = AVCaptureVideoPreviewLayer()
    let stillImageOutput = AVCaptureStillImageOutput()
    
    var beginImage: CIImage!
    
    @IBOutlet weak var imageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        captureSession.sessionPreset = AVCaptureSessionPresetHigh
        
        let devices = AVCaptureDevice.devices()
        
        for device in devices {
            if (device.hasMediaType(AVMediaTypeVideo)) {
                if (device.position == AVCaptureDevicePosition.Back) {
                    captureDevice = device as? AVCaptureDevice
                }
            }
        }
        
        if captureDevice != nil {
            beginSession()
        }
    }
    
    func beginSession() {
        do {
            configureDevice()
            try self.captureSession.addInput(AVCaptureDeviceInput(device: captureDevice))
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            self.view.layer.addSublayer(previewLayer)
            previewLayer.frame = self.view.layer.frame
            captureSession.startRunning()
        } catch let error as NSError {
            print("error: \(error.localizedDescription)")
        }
    }
    
    func configureDevice() {
        if let device = captureDevice {
            do {
                try device.lockForConfiguration()
                device.focusMode = .Locked
                device.unlockForConfiguration()
            } catch let error as NSError {
                print("error: \(error.localizedDescription)")
            }
        }
    }
    
    func updateDeviceSettings(focusValue: Float, isoValue: Float) {
        if let device = captureDevice {
            do {
                try device.lockForConfiguration()
                device.setFocusModeLockedWithLensPosition(focusValue, completionHandler: { (time) -> Void in
                    //
                })
                
                let minISO = device.activeFormat.minISO
                let maxISO = device.activeFormat.maxISO
                let clampedISO = isoValue * (maxISO - minISO) + minISO
                
                device.setExposureModeCustomWithDuration(AVCaptureExposureDurationCurrent, ISO: clampedISO, completionHandler: { (time) -> Void in
                    //
                })
                
                device.unlockForConfiguration()
            } catch let error as NSError {
                print("error: \(error.localizedDescription)")
            }
        }
    }
    
    func updateLayer(opacityValue: Float) {
        previewLayer.opacity = opacityValue
    }
    
    func touchPercent(touch: UITouch) -> CGPoint {
        let screenSize = UIScreen.mainScreen().bounds.size
        var touchPer = CGPointZero
        touchPer.x = touch.locationInView(self.view).x / screenSize.width
        touchPer.y = touch.locationInView(self.view).y / screenSize.height
        return touchPer
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        let touchPer = touchPercent(touches.first! as UITouch)
        updateDeviceSettings(Float(touchPer.x), isoValue: Float(touchPer.y))
        updateLayer(Float(touchPer.x))
    }
    
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?) {
        let touchPer = touchPercent(touches.first! as UITouch)
        updateDeviceSettings(Float(touchPer.x), isoValue: Float(touchPer.y))
        updateLayer(Float(touchPer.x))
    }
    
    func saveToCamera(sender: UITapGestureRecognizer) {
        if let videoConnection = stillImageOutput.connectionWithMediaType(AVMediaTypeVideo) {
            stillImageOutput.captureStillImageAsynchronouslyFromConnection(videoConnection) {
                (imageDataSampleBuffer, error) -> Void in
                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                UIImageWriteToSavedPhotosAlbum(UIImage(data: imageData)!, nil, nil, nil)
            }
        }
    }
}








//import UIKit
//import AVFoundation
//class ViewController: UIViewController {
//    let captureSession = AVCaptureSession()
//    let stillImageOutput = AVCaptureStillImageOutput()
//    var error: NSError?
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        let devices = AVCaptureDevice.devices().filter{ $0.hasMediaType(AVMediaTypeVideo) && $0.position == AVCaptureDevicePosition.Back }
//        if let captureDevice = devices.first as? AVCaptureDevice  {
//            
//            captureSession.addInput(AVCaptureDeviceInput(device: captureDevice, error: &error))
//            captureSession.sessionPreset = AVCaptureSessionPresetPhoto
//            captureSession.startRunning()
//            stillImageOutput.outputSettings = [AVVideoCodecKey:AVVideoCodecJPEG]
//            if captureSession.canAddOutput(stillImageOutput) {
//                captureSession.addOutput(stillImageOutput)
//            }
//            if let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession) {
//                previewLayer.bounds = view.bounds
//                previewLayer.position = CGPointMake(view.bounds.midX, view.bounds.midY)
//                previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
//                let cameraPreview = UIView(frame: CGRectMake(0.0, 0.0, view.bounds.size.width, view.bounds.size.height))
//                cameraPreview.layer.addSublayer(previewLayer)
//                cameraPreview.addGestureRecognizer(UITapGestureRecognizer(target: self, action:"saveToCamera:"))
//                view.addSubview(cameraPreview)
//            }
//        }
//    }
//    func saveToCamera(sender: UITapGestureRecognizer) {
//        if let videoConnection = stillImageOutput.connectionWithMediaType(AVMediaTypeVideo) {
//            stillImageOutput.captureStillImageAsynchronouslyFromConnection(videoConnection) {
//                (imageDataSampleBuffer, error) -> Void in
//                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
//                UIImageWriteToSavedPhotosAlbum(UIImage(data: imageData), nil, nil, nil)
//            }
//        }
//    }
//    override func didReceiveMemoryWarning() {
//        super.didReceiveMemoryWarning()
//    }
//}