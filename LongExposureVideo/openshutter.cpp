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
}

Mat lastframe() {
    return ims[0];
}

Mat framediff(Mat image0, Mat image1, Mat image2) {
//        return (image0 - 2*image1 + image2)/((image0 - image1) + (image1 - image2));
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

int process(VideoCapture& capture) {
    int n = 0;
    char filename[200];
    
    string window_name = "this is live! - q or esc to quit - space to save frame";
    namedWindow(window_name, WINDOW_KEEPRATIO);
    
    int effectFlag = 1; // 1: framediff, 2: modified lapacian
    
    Mat i0;              // current frame
    Mat im1;             // frame at i-1
    Mat im2;             // frame at i-2
    Mat processed_frame; // resultant frame
    
    capture >> im2;
    waitKey(1);
    capture >> im1;
    waitKey(1);
    
    for (;;) {
        
        capture >> i0;
        
        switch (effectFlag) {
            case 1:
                processed_frame = framediff(i0, im1, im2);
                im1.copyTo(im2);
                i0.copyTo(im1);
                break;
            case 2:
                processed_frame = mod_laplace(i0);
                break;
            case 3:
                processed_frame = sharp(i0);
                break;
            case 4:
                processed_frame = mod_laplace(i0);
                processed_frame = negative(processed_frame);
                break;
            default:
                processed_frame = i0;
                break;
        }
        
        imshow(window_name, processed_frame);
        char key = (char)waitKey(1000/32); //delay for 32 frames per second
        switch (key) {
            case 'q':
            case 'Q':
            case 27: //escape key
                return 0;
            case ' ': //Save an image
                sprintf(filename, "processed_frame%.3d.png", n++);
                imwrite(filename, processed_frame);
                cout << "Saved " << filename << endl;
                break;
            case '0':
                effectFlag = 0;
                break;
            case '1':
                effectFlag = 1;
                break;
            case '2':
                effectFlag = 2;
                break;
            case '3':
                effectFlag = 3;
                break;
            case '4':
                effectFlag = 4;
                break;
            default:
                break;
        }
    }
    return 0;
}
