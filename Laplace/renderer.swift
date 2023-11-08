//
//  renderer.swift
//  Laplace
//
//  Created by Mudafort, Rafael on 11/8/23.
//  Copyright © 2023 Rafael M Mudafort. All rights reserved.
//

import Foundation
import MetalKit
//@import simd;


// Main class performing the rendering
class Renderer: NSObject {
    
    var _device: MTLDevice?
    
    // The command queue used to pass commands to the device.
    var _commandQueue: MTLCommandQueue?

    init(mtkView: MTKView) {
//        self.delegate = delegate

        guard let device = mtkView.device else {
            print("Could not initialize Metal device.")
            return
        }
        self._device = device

        // Create the command queue
        guard let commandQueue = device.makeCommandQueue() else {
            print("Could not get device command queue.")
            return
        }
        self._commandQueue = commandQueue
    }

}

extension Renderer : MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        draw(in: view)
    }
    
    /// Called whenever the view needs to render a frame.
    func draw(in view: MTKView) {
        // The render pass descriptor references the texture into which Metal should draw
        guard let renderPassDescriptor: MTLRenderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        guard let commandBuffer: MTLCommandBuffer = _commandQueue!.makeCommandBuffer() else {
            return
        }
        
        // Create a render pass and immediately end encoding, causing the drawable to be cleared
        guard let commandEncoder: MTLRenderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        commandEncoder.endEncoding()
        
        // Get the drawable that will be presented at the end of the frame
        guard let drawable: MTLDrawable = view.currentDrawable else {
            return
        }

        // Request that the drawable texture be presented by the windowing system once drawing is done
        commandBuffer.present(drawable)
        
        commandBuffer.commit()
    }
}
