//
//  ViewController.swift
//  LongExposureVideo
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

    var glContext: EAGLContext?
    var ciContext: CIContext?
    var renderBuffer: GLuint = GLuint()
    var glView: GLKView?

    var cameraController: CameraController!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        cameraController = CameraController(delegate: self)
        
        glContext = EAGLContext(api: .openGLES2)
        glView = GLKView(frame: videoPreviewView.frame, context: glContext!)
        glView!.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi/2))
        
        // what does this do?
        /*
        if let window = glView!.window {
            glView!.frame = window.bounds
        }
        */
        
        glView!.frame = videoPreviewView.frame
        ciContext = CIContext(eaglContext: glContext!)
        videoPreviewView.addSubview(glView!)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraController.startRunning()
    }
    
    @IBAction func swapCameraButtonClicked(sender: AnyObject) {
        cameraController.switchCamera()
    }
    
    @IBAction func recordVideoButtonClicked(sender: AnyObject) {
        cameraController.captureStillImage { (image, metadata) in
            print(metadata)
        }
//        cameraController.toggleRecording()
    }
}

extension ViewController: CameraControllerDelegate {    
    func cameraController(cameraController: CameraController, didOutputImage image: CIImage) {
        if glContext != EAGLContext.current() {
            EAGLContext.setCurrent(glContext)
        }
        glView!.bindDrawable()
        ciContext?.draw(image, in: image.extent, from: image.extent)
        glView!.display()
    }
}
