//
//  CVWrapper.h
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 12/31/16.
//  Copyright © 2016 Rafael M Mudafort. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CVWrapper : NSObject

+ (UIImage*) processImageWithOpenCV: (UIImage*) inputImage;

+ (UIImage*) processWithOpenCVImage1:(UIImage*)inputImage1 image2:(UIImage*)inputImage2;

+ (UIImage*) processWithArray:(NSArray*)imageArray;

@end
