//
//  openshutter.hpp
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 1/2/17.
//  Copyright © 2017 Rafael M Mudafort. All rights reserved.
//

#ifndef openshutter_hpp
#define openshutter_hpp

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/videoio/videoio.hpp>
#include <opencv2/highgui/highgui.hpp>

#include <iostream>
#include <stdio.h>
#include <stdlib.h>

using namespace cv;
using namespace std;

Mat noop(Mat image);
Mat openshutter(Mat i0);
Mat lastframe();
Mat mod_laplace(Mat image);

#endif /* openshutter_hpp */
