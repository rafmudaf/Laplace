//
//  openshutter.cpp
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 1/2/17.
//  Copyright © 2017 Rafael M Mudafort. All rights reserved.
//

#include "openshutter.hpp"

bool firsttime = true;
Mat im1;

Mat openshutter(Mat i0) {
    Mat diff;
    if (firsttime) {
        firsttime = false;
        im1 = i0;
        return i0;
    } else {
        diff = im1 - i0;
        im1 = i0;
        return diff;
    }
}
