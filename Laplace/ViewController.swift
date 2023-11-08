//
//  ViewController.swift
//  Laplace
//
//  Created by Rafael M Mudafort on 3/6/16.
//  Copyright © 2016 Rafael M Mudafort. All rights reserved.
//

import UIKit
//import AVFoundation
import MetalKit

class ViewController: UIViewController {

    @IBOutlet weak var videoPreviewView: MTKView!
    @IBOutlet weak var swapCameraButton: UIButton!
    @IBOutlet weak var recordVideoButton: UIButton!
    
    var _view = MTKView()

    var cameraController: CameraController!

    override func viewDidLoad() {
        super.viewDidLoad()
        cameraController = CameraController(delegate: self)
        
        _view = self.videoPreviewView
//        _view.enableSetNeedsDisplay = true
        _view.device = MTLCreateSystemDefaultDevice()
        _view.clearColor = MTLClearColorMake(0.0, 0.5, 1.0, 1.0)
        
        let _renderer = Renderer(mtkView: _view)
        _view.delegate = _renderer

        // Initialize the renderer with the view size.
        _renderer.mtkView(_view, drawableSizeWillChange: _view.drawableSize)        
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
//        if glContext != EAGLContext.current() {
//            EAGLContext.setCurrent(glContext)
//        }
//        guard let glView = self.glView else {
//            fatalError("glView not accessible")
//        }
//        
//        glView.bindDrawable()
//        ciContext?.draw(image, in: image.extent, from: image.extent)
//        glView.display()
    }
}
