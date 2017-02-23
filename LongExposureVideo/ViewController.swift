//
//  ViewController.swift
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 3/6/16.
//  Copyright © 2016 Rafael M Mudafort. All rights reserved.
//

import UIKit
import AVFoundation
import GLKit

class ViewController: UIViewController {

    @IBOutlet weak var videoPreviewView: UIView!
    @IBOutlet weak var swapCameraButton: UIButton!
    @IBOutlet weak var recordVideoButton: UIButton!
    @IBOutlet weak var isoSlider: UISlider!

    var glContext: EAGLContext?
    var ciContext: CIContext?
    var renderBuffer: GLuint = GLuint()
    var glView: GLKView?

    var cameraController: CameraController!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        cameraController = CameraController(previewType: .Manual, delegate: self)
        
        glContext = EAGLContext(API: .OpenGLES2)
        glView = GLKView(frame: videoPreviewView.frame, context: glContext!)
        
        glView!.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
        
        // what does this do?
//        if let window = glView!.window {
//            glView!.frame = window.bounds
//        }
        
        glView!.frame = videoPreviewView.frame
        
        ciContext = CIContext(EAGLContext: glContext!)
        videoPreviewView.addSubview(glView!)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        cameraController.startRunning()
    }
    
    @IBAction func swapCameraButtonClicked(sender: AnyObject) {
        cameraController.switchCamera()
    }
    
    @IBAction func recordVideoButtonClicked(sender: AnyObject) {
        cameraController.toggleRecording()
    }
    
    @IBAction func sliderValueChanged(sender: UISlider) {
        switch sender {
        case isoSlider:
            cameraController?.setCustomExposureWithISO(sender.value)
        default: break
        }
    }
}

extension ViewController: CameraControllerDelegate {
    func cameraController(cameraController: CameraController, didDetectFaces faces:Array<(id:Int,frame:CGRect)>) { }
    
    func cameraController(cameraController: CameraController, didOutputImage image: CIImage) {
        if glContext != EAGLContext.currentContext() {
            EAGLContext.setCurrentContext(glContext)
        }
        glView!.bindDrawable()
        ciContext?.drawImage(image, inRect: image.extent, fromRect: image.extent)
        glView!.display()
    }
}
