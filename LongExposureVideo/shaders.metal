//
//  shaders.metal
//  LongExposureVideo
//
//  Created by Mudafort, Rafael on 1/4/18.
//  Copyright © 2018 Rafael M Mudafort. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

//kernel void processingKernel(const device uint *inputValues [[ buffer(0) ]],
//                              device uint *outputValues [[ buffer(1) ]],
//                              uint id [[thread_position_in_grid]])
//{
//    outputValues[id] = inputValues[id] * inputValues[id];
//}

//kernel void processingKernel(texture2d<float, access::read> inTexture [[texture(0)]],
//                     texture2d<float, access::write> outTexture [[texture(1)]],
//                     device unsigned int *pixelSize [[buffer(0)]],
//                     uint2 gid [[thread_position_in_grid]])
//{
//    const uint2 pixellateGrid = uint2((gid.x / pixelSize[0]) * pixelSize[0], (gid.y / pixelSize[0]) * pixelSize[0]);
//    const float4 colorAtPixel = inTexture.read(pixellateGrid);
//    outTexture.write(colorAtPixel, gid);
//}

kernel void processingKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                             texture2d<float, access::write> outTexture [[texture(1)]],
                             uint2 id [[thread_position_in_grid]])
{
    uint2 indexUpLeft(id.x - 1, id.y - 1);
    uint2 indexUp(id.x, id.y - 1);
    uint2 indexUpRight(id.x + 1, id.y - 1);
    uint2 indexLeft(id.x - 1, id.y);
    uint2 indexRight(id.x + 1, id.y);
    uint2 indexBottomLeft(id.x - 1, id.y + 1);
    uint2 indexBottom(id.x, id.y + 1);
    uint2 indexBottomRight(id.x + 1, id.y + 1);
    
    const float4 upLeft = inTexture.read(indexUpLeft).rgba;
    const float4 up = inTexture.read(indexUp).rgba;
    const float4 upRight = inTexture.read(indexUpRight).rgba;
    const float4 left = inTexture.read(indexLeft).rgba;
    const float4 right = inTexture.read(indexRight).rgba;
    const float4 bottomLeft = inTexture.read(indexBottomLeft).rgba;
    const float4 bottom = inTexture.read(indexBottom).rgba;
    const float4 bottomRight = inTexture.read(indexBottomRight).rgba;
    const float4 current = inTexture.read(id).rgba;
    
    const float4 newpixel = upLeft + 2*up + upRight + 2*left -12*current + 2*right + bottomLeft + 2*bottom + bottomRight;
    
    outTexture.write(float4(newpixel.rgb, 1), id);
}
