//
//  CVWrapper.m
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 12/31/16.
//  Copyright © 2016 Rafael M Mudafort. All rights reserved.
//

#import "CVWrapper.h"
#import "UIImage+OpenCV.h"
#import "openshutter.hpp"

#include <opencv2/imgcodecs.hpp>
#include <opencv2/videoio/videoio.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgcodecs/ios.h>

@implementation CVWrapper

+ (UIImage*) processImageWithOpenCV: (UIImage*) inputImage {
    Mat mat;
    Mat matout;
    UIImageToMat(inputImage, mat, true);
//    Mat openMat = openshutter(mat);
    Mat openMat = mod_laplace(mat);
    UIImage* result = MatToUIImage(openMat);
    return result;
}

+ (UIImage*) getLastProcessedFrame {
    return MatToUIImage(lastframe());
}

@end
