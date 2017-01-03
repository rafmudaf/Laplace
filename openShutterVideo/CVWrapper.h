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

@end
