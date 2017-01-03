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

class ViewController: UIViewController, CameraControllerDelegate {

    @IBOutlet weak var videoPreviewView: UIView!
    
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
        
        let translationrotation = CGAffineTransformConcat(CGAffineTransformMakeRotation(CGFloat(M_PI_2)), CGAffineTransformMakeTranslation(-1*glView!.frame.minX, -1*glView!.frame.minY))
        glView!.transform = translationrotation
        if let window = glView!.window {
            glView!.frame = window.bounds
        }
        
        ciContext = CIContext(EAGLContext: glContext!)
        videoPreviewView.addSubview(glView!)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        cameraController.startRunning()
    }
    
    // MARK: - CameraControllerDelegate
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
