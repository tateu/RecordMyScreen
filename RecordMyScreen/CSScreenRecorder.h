//
//  CSScreenRecorder.h
//  RecordMyScreen
//
//  Created by Aditya KD on 02/04/13.
//  Copyright (c) 2013 CoolStar Organization. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@protocol CSScreenRecorderDelegate;


@interface CSScreenRecorder : NSObject <AVAudioRecorderDelegate>

// All these properties must be set before -startRecordingScreen is called, or defaults will be used.

// the path where the video/audio is saved whilst being recorded.
@property(nonatomic, copy) NSString *videoOutPath;
@property(nonatomic, copy) NSString *audioOutPath;

@property(nonatomic, copy) NSNumber *audioBitRate;
@property(nonatomic, copy) NSNumber *audioSampleRate;
@property(nonatomic, copy) NSNumber *numberOfAudioChannels;
@property(nonatomic, copy) NSNumber *recordAudio;
@property(nonatomic, copy) NSNumber *videoFormat;

@property(nonatomic, copy) NSNumber *fps;
@property(nonatomic, copy) NSNumber *kbps;
@property(nonatomic, copy) NSNumber *h264ProfileAndLevel;
@property(nonatomic, copy) NSNumber *vidsize;
@property(nonatomic, copy) NSNumber *vidorientation;

@property(nonatomic, assign) id<CSScreenRecorderDelegate> delegate;

- (void)startRecordingScreen;
- (void)stopRecordingScreen;

@end

@protocol CSScreenRecorderDelegate <NSObject>
@optional
- (void)screenRecorderDidStartRecording:(CSScreenRecorder *)recorder;
- (void)screenRecorderDidStopRecording:(CSScreenRecorder *)recorder;
// Called every second.
- (void)screenRecorder:(CSScreenRecorder *)recorder recordingTimeChanged:(NSTimeInterval)recordingTime; // time in seconds since start of capture

- (void)screenRecorder:(CSScreenRecorder *)recorder videoContextSetupFailedWithError:(NSError *)error;
- (void)screenRecorder:(CSScreenRecorder *)recorder audioSessionSetupFailedWithError:(NSError *)error;
- (void)screenRecorder:(CSScreenRecorder *)recorder audioRecorderSetupFailedWithError:(NSError *)error;

@end
