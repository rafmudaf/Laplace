//
//  CVWrapper.m
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 12/31/16.
//  Copyright © 2016 Rafael M Mudafort. All rights reserved.
//

#import "CVWrapper.h"
#import "UIImage+OpenCV.h"
#import "UIImage+Rotate.h"
#import "openshutter.hpp"

#include <opencv2/imgcodecs.hpp>
#include <opencv2/videoio/videoio.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgcodecs/ios.h>

@implementation CVWrapper

+ (UIImage*) processImageWithOpenCV: (UIImage*) inputImage {
    Mat mat;
    UIImageToMat(inputImage, mat, true);
    UIImage* result = MatToUIImage(openshutter(mat));
    return result;
}

@end
