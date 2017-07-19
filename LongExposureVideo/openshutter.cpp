//
//  openshutter.cpp
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 1/2/17.
//  Copyright © 2017 Rafael M Mudafort. All rights reserved.
//

#include "openshutter.hpp"

int maxFrameCount = 20;
Mat ims[20];
int framecount = 0;

Mat openshutter(Mat i0) {
    
    // shift the image array over one index
    for (int i=maxFrameCount-1; i>0; i--) {
        ims[i] = ims[i-1];
    }
    ims[0] = i0;
    
    // if the image array is not full, return the initial image
    if (framecount < maxFrameCount) {
        ++framecount;
        return i0;
    }
    
    // initialize the combo Mat to all zeros
    Mat combo = Mat(i0.rows, i0.cols, i0.type(), double(0));
    
    // calculate the combination frame
    for (int i=0; i<maxFrameCount; i++) {
        //        float denom = 2*(i+1);
        float denom = 2;
        scaleAdd(ims[i], 1/denom, combo, combo);
    }
    
    return combo;
    
//        vector<uchar> array;
//        if (i0.isContinuous()) {
//            array.assign(i0.datastart, i0.dataend);
//        } else {
//            for (int i = 0; i < i0.rows; ++i) {
//                array.insert(array.end(), i0.ptr<uchar>(i), i0.ptr<uchar>(i)+i0.cols);
//            }
//        }
//        Laplacian(i0, diff, 3, 5);
//        diff.convertTo(diff, i0.depth());
}

Mat lastframe() {
    return ims[0];
}
