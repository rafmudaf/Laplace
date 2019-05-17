//
//  openshutter.cpp
//  openShutterVideo
//
//  Created by Rafael M Mudafort on 1/2/17.
//  Copyright © 2017 Rafael M Mudafort. All rights reserved.
//

#include "image_kernels.hpp"

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
        float denom = 2; //2*(i+1)
        scaleAdd(ims[i], 1/denom, combo, combo);
    }
    
    return combo;
}

Mat lastframe() {
    return ims[0];
}

Mat framediff(Mat image0, Mat image1, Mat image2) {
//    return (image0 - 2*image1 + image2)/((image0 - image1) + (image1 - image2));
    return image2 - image0;
}

Mat laplace(Mat image) {
    Mat kernel = Mat::zeros( 3, 3, CV_8S );
    kernel.at<uchar>(0,1) = 1;
    kernel.at<uchar>(1,0) = 1;
    kernel.at<uchar>(1,1) = -4;
    kernel.at<uchar>(1,2) = 1;
    kernel.at<uchar>(2,1) = 1;
    Mat output;
    filter2D(image, output, -1, kernel);
    return output;
}

Mat mod_laplace(Mat image) {
    Mat kernel = Mat::ones( 3, 3, CV_8S );
    kernel.at<uchar>(0,1) = 2;
    kernel.at<uchar>(1,0) = 2;
    kernel.at<uchar>(1,1) = -12;
    kernel.at<uchar>(1,2) = 2;
    kernel.at<uchar>(2,1) = 2;
    Mat output;
    filter2D(image, output, -1, kernel);
    return output;
}

Mat sharp(Mat image) {
    Mat filter = laplace(image);
    return image - filter;
}

Mat negative(Mat image) {
    Mat result;
    image.convertTo(result, CV_8S, -1, 0);
    return result;
}
