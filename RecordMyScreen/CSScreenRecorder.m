//
//  CSScreenRecorder.m
//  RecordMyScreen
//
//  Created by Aditya KD on 02/04/13.
//  Copyright (c) 2013 CoolStar Organization. All rights reserved.
//

#import "CSScreenRecorder.h"
#import <Foundation/NSDistributedNotificationCenter.h>
#import <IOMobileFrameBuffer.h>
#import <CoreVideo/CVPixelBuffer.h>
#import <QuartzCore/QuartzCore.h>

#include <IOSurface.h>
#include <sys/time.h>

#define NSLog(fmt, ...)

void CARenderServerRenderDisplay(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);

CGFloat degreesToRadians (CGFloat deg)
{
	return deg * (M_PI / 180.0f);
}

int roundDownToMultiple(int numberToRound, int multiple)
{
	if (multiple == 0)
		return numberToRound;

	int remainder = abs(numberToRound) % multiple;
	if (remainder == 0)
		return numberToRound;

	if (numberToRound < 0)
		return -(abs(numberToRound) + remainder);

	return numberToRound - remainder;
}

int roundUpToMultiple(int numberToRound, int multiple)
{
	if (multiple == 0)
		return numberToRound;

	int remainder = abs(numberToRound) % multiple;
	if (remainder == 0)
		return numberToRound;
	if (numberToRound < 0)
		return -(abs(numberToRound) - remainder);
	return numberToRound + multiple - remainder;
}

@interface CSScreenRecorder ()
{
@private
	BOOL				_isRecording;
	int				 _kbps;
	int				 _fps;

	NSDictionary		*settings;

	//surface
	IOSurfaceRef		_surface;
	int				 _bytesPerRow;
	int				 _width;
	int				 _height;

	dispatch_queue_t	_videoQueue;

	NSLock			 *_pixelBufferLock;
	NSTimer			*_recordingTimer;
	NSDate			 *_recordStartDate;

	AVAudioRecorder	*_audioRecorder;
	AVAssetWriter	  *_videoWriter;
	AVAssetWriterInput *_videoWriterInput;
	AVAssetWriterInputPixelBufferAdaptor *_pixelBufferAdaptor;
}

- (void)_setupVideoContext;
- (void)_setupAudio;
- (void)_setupVideoAndStartRecording;
- (void)_captureShot:(CMTime)frameTime;
- (IOSurfaceRef)_createScreenSurface;
- (void)_finishEncoding;

- (void)_sendDelegateTimeUpdate:(NSTimer *)timer;

@end

@implementation CSScreenRecorder

- (instancetype)init
{
	if ((self = [super init])) {
		_pixelBufferLock = [NSLock new];

		//video queue
		_videoQueue = dispatch_queue_create("video_queue", DISPATCH_QUEUE_SERIAL);
		//frame rate
		_fps = 24;
		//encoding kbps
		_kbps = 5000;

		settings = [[[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/org.coolstar.recordmyscreen.plist"] retain];
		if (!settings) {
			settings = [[[NSDictionary alloc] init] retain];
		}
	}
	return self;
}

- (void)dealloc
{
	if (_surface) {
		CFRelease(_surface);
		_surface = NULL;
	}

	dispatch_release(_videoQueue);
	_videoQueue = NULL;

	[_pixelBufferLock release];
	_pixelBufferLock = nil;

	[_videoOutPath release];
	_videoOutPath = nil;

	_recordingTimer = nil;
	// These are released when capture stops, etc, but what if?
	// You don't want to leak memory!
	[_recordStartDate release];
	_recordStartDate = nil;

	[_audioRecorder release];
	_audioRecorder = nil;

	[_videoWriter release];
	_videoWriter = nil;

	[_videoWriterInput release];
	_videoWriterInput = nil;

	[_pixelBufferAdaptor release];
	_pixelBufferAdaptor = nil;

	[settings release];
	settings = nil;

	[super dealloc];
}

- (void)startRecordingScreen
{
	// if the AVAssetWriter is NOT valid, setup video context
	if(!_videoWriter)
		[self _setupVideoContext]; // this must be done before _setupVideoAndStartRecording
	_recordStartDate = [[NSDate date] retain];

	if ([self.recordAudio boolValue] == YES) {
		[self _setupAudio];
	}
	[self _setupVideoAndStartRecording];
}

- (void)stopRecordingScreen
{
	// Set the flag to stop recording
	_isRecording = NO;

	// Invalidate the recording time
	[_recordingTimer invalidate];
	_recordingTimer = nil;
}

- (void)_setupAudio
{
	// Setup to be able to record global sounds (preexisting app sounds)
	NSError *sessionError = nil;
	if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(setCategory:withOptions:error:)])
		[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDuckOthers error:&sessionError];
	else
		[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&sessionError];

	// Set the audio session to be active
	[[AVAudioSession sharedInstance] setActive:YES error:&sessionError];

	if (sessionError && [self.delegate respondsToSelector:@selector(screenRecorder:audioSessionSetupFailedWithError:)]) {
		[self.delegate screenRecorder:self audioSessionSetupFailedWithError:sessionError];
		return;
	}

	// Set the number of audio channels, using defaults if necessary.
	NSNumber *audioChannels = (self.numberOfAudioChannels ? self.numberOfAudioChannels : @1);
	NSNumber *sampleRate	= (self.audioSampleRate	   ? self.audioSampleRate	   : @44100.f);
	NSNumber *audioBitRate  = ([settings objectForKey:@"audioBitRate"] ?: @64000);

	NSDictionary *audioSettings;
	if ([self.videoFormat intValue] == 2) {
		audioSettings = @{
						AVNumberOfChannelsKey : (audioChannels ? audioChannels : @1),
						AVSampleRateKey	   : (sampleRate	? sampleRate	: @44100.0f)
						};
	} else {
		AudioChannelLayout acl = {0};
		if ([audioChannels intValue] == 1) {
			acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
		} else {
			acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
		}
		NSData *aclData = [NSData dataWithBytes:&acl length: sizeof(acl)];

		audioSettings = @{
						AVFormatIDKey		   :   @(kAudioFormatMPEG4AAC),
						AVNumberOfChannelsKey   :   (audioChannels ? audioChannels : @1),
						AVSampleRateKey		 :   (sampleRate	? sampleRate	: @44100.0f),
						AVEncoderBitRateKey	 :   (audioBitRate  ? audioBitRate  : @64000),
						AVChannelLayoutKey	  :   aclData
						};
		}


	// Initialize the audio recorder
	// Set output path of the audio file
	NSError *error = nil;
	NSAssert((self.audioOutPath != nil), @"Audio out path cannot be nil!");
	_audioRecorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:self.audioOutPath] settings:audioSettings error:&error];
	if (error && [self.delegate respondsToSelector:@selector(screenRecorder:audioRecorderSetupFailedWithError:)]) {
		// Let the delegate know that shit has happened.
		[self.delegate screenRecorder:self audioRecorderSetupFailedWithError:error];

		[_audioRecorder release];
		_audioRecorder = nil;

		return;
	}

	[_audioRecorder setDelegate:self];
	[_audioRecorder prepareToRecord];

	// Start recording :P
	[_audioRecorder record];
}

- (void)_setupVideoAndStartRecording
{
	// Set timer to notify the delegate of time changes every second
	_recordingTimer = [NSTimer scheduledTimerWithTimeInterval:1
													   target:self
													 selector:@selector(_sendDelegateTimeUpdate:)
													 userInfo:nil
													  repeats:YES];

	_isRecording = YES;

	//capture loop (In another thread)
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		int targetFPS = _fps;
		int msBeforeNextCapture = 1000 / targetFPS;

		struct timeval lastCapture, currentTime, startTime;
		lastCapture.tv_sec = 0;
		lastCapture.tv_usec = 0;

		//recording start time
		gettimeofday(&startTime, NULL);
		startTime.tv_usec /= 1000;

		int lastFrame = -1;
		while(_isRecording)
		{
			//time passed since last capture
			gettimeofday(&currentTime, NULL);

			//convert to milliseconds to avoid overflows
			currentTime.tv_usec /= 1000;

			unsigned long long diff = (currentTime.tv_usec + (1000 * currentTime.tv_sec) ) - (lastCapture.tv_usec + (1000 * lastCapture.tv_sec) );

			// if enough time has passed, capture another shot
			if(diff >= msBeforeNextCapture)
			{
				//time since start
				long int msSinceStart = (currentTime.tv_usec + (1000 * currentTime.tv_sec) ) - (startTime.tv_usec + (1000 * startTime.tv_sec) );

				// Generate the frame number
				int frameNumber = msSinceStart / msBeforeNextCapture;
				CMTime presentTime;
				presentTime = CMTimeMake(frameNumber, targetFPS);

				// Frame number cannot be last frames number :P
				NSParameterAssert(frameNumber != lastFrame);
				lastFrame = frameNumber;

				// Capture next shot and repeat
				[self _captureShot:presentTime];
				lastCapture = currentTime;
			}
		}

		// finish encoding, using the video_queue thread
		dispatch_async(_videoQueue, ^{
			[self _finishEncoding];
		});

	});
}

- (void)_captureShot:(CMTime)frameTime
{
	// Create an IOSurfaceRef if one does not exist
	if(!_surface) {
		_surface = [self _createScreenSurface];
	}

	// Lock the surface from other threads
	static NSMutableArray *buffers = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		buffers = [[NSMutableArray alloc] init];
	});

	IOSurfaceLock(_surface, 0, nil);
	// Take currently displayed image from the LCD
	CARenderServerRenderDisplay(0, CFSTR("LCD"), _surface, 0, 0);
	// Unlock the surface
	IOSurfaceUnlock(_surface, 0, 0);

	// Make a raw memory copy of the surface
	void *baseAddr = IOSurfaceGetBaseAddress(_surface);
	int totalBytes = _bytesPerRow * _height;

	//void *rawData = malloc(totalBytes);
	//memcpy(rawData, baseAddr, totalBytes);
	NSMutableData * rawDataObj = nil;
	if (buffers.count == 0)
		rawDataObj = [[NSMutableData dataWithBytes:baseAddr length:totalBytes] retain];
	else @synchronized(buffers) {
		rawDataObj = [buffers lastObject];
		memcpy((void *)[rawDataObj bytes], baseAddr, totalBytes);
		//[rawDataObj replaceBytesInRange:NSMakeRange(0, rawDataObj.length) withBytes:baseAddr length:totalBytes];
		[buffers removeLastObject];
	}

	dispatch_async(dispatch_get_main_queue(), ^{

		if(!_pixelBufferAdaptor.pixelBufferPool){
			NSLog(@"skipping frame: %lld", frameTime.value);
			//free(rawData);
			@synchronized(buffers) {
				//[buffers addObject:rawDataObj];
			}
			return;
		}

		static CVPixelBufferRef pixelBuffer = NULL;

		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			NSParameterAssert(_pixelBufferAdaptor.pixelBufferPool != NULL);
			[_pixelBufferLock lock];
			CVPixelBufferPoolCreatePixelBuffer (kCFAllocatorDefault, _pixelBufferAdaptor.pixelBufferPool, &pixelBuffer);
			[_pixelBufferLock unlock];
			NSParameterAssert(pixelBuffer != NULL);
		});

		//unlock pixel buffer data
		CVPixelBufferLockBaseAddress(pixelBuffer, 0);
		void *pixelData = CVPixelBufferGetBaseAddress(pixelBuffer);
		NSParameterAssert(pixelData != NULL);

		//copy over raw image data and free
		memcpy(pixelData, [rawDataObj bytes], totalBytes);
		//free(rawData);
		@synchronized(buffers) {
			[buffers addObject:rawDataObj];
		}

		//unlock pixel buffer data
		CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

		dispatch_async(_videoQueue, ^{
			// Wait until AVAssetWriterInput is ready
			while(!_videoWriterInput.readyForMoreMediaData)
				usleep(1000);

			// Lock from other threads
			[_pixelBufferLock lock];
			// Add the new frame to the video
			[_pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:frameTime];

			// Unlock
			//CVPixelBufferRelease(pixelBuffer);
			[_pixelBufferLock unlock];
		});
	});
}

- (IOSurfaceRef)_createScreenSurface
{
	// Pixel format for Alpha Red Green Blue
	unsigned pixelFormat = 0x42475241;//'ARGB';

	// 4 Bytes per pixel
	int bytesPerElement = 4;

	// Properties include: SurfaceIsGlobal, BytesPerElement, BytesPerRow, SurfaceWidth, SurfaceHeight, PixelFormat, SurfaceAllocSize (space for the entire surface)
	NSDictionary *properties = [NSDictionary dictionaryWithObjectsAndKeys:
								[NSNumber numberWithBool:YES], kIOSurfaceIsGlobal,
								[NSNumber numberWithInt:bytesPerElement], kIOSurfaceBytesPerElement,
								[NSNumber numberWithInt:_bytesPerRow], kIOSurfaceBytesPerRow,
								[NSNumber numberWithInt:_width], kIOSurfaceWidth,
								[NSNumber numberWithInt:_height], kIOSurfaceHeight,
								[NSNumber numberWithUnsignedInt:pixelFormat], kIOSurfacePixelFormat,
								[NSNumber numberWithInt:_bytesPerRow * _height], kIOSurfaceAllocSize,
								nil];

	// This is the current surface
	return IOSurfaceCreate((CFDictionaryRef)properties);
}

#pragma mark - Encoding
- (void)_setupVideoContext
{
	// Get the screen rect and scale
	CGRect screenRect = [UIScreen mainScreen].bounds;
	float scale = [UIScreen mainScreen].scale;

	// setup the width and height of the framebuffer for the device
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
		// iPhone frame buffer is Portrait
		_width = screenRect.size.width * scale;
		_height = screenRect.size.height * scale;
	} else {
		// iPad frame buffer is Landscape
		_width = screenRect.size.height * scale;
		_height = screenRect.size.width * scale;
	}

	if (_width % 2 != 0) {
		_width -= 1;
	}


	NSAssert((self.videoOutPath != nil) , @"A valid videoOutPath must be set before the recording starts!");

	NSError *error = nil;

	// Setup AVAssetWriter with the output path
	_videoWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:self.videoOutPath]
											 fileType:AVFileTypeMPEG4
												error:&error];
	// check for errors
	if(error) {
		if ([self.delegate respondsToSelector:@selector(screenRecorder:videoContextSetupFailedWithError:)]) {
			[self.delegate screenRecorder:self videoContextSetupFailedWithError:error];
		}
	}

	// Makes sure AVAssetWriter is valid (check check check)
	NSParameterAssert(_videoWriter);

	// Setup AverageBitRate, FrameInterval, and ProfileLevel (Compression Properties)
	NSMutableDictionary * compressionProperties = [NSMutableDictionary dictionary];
	if ([settings objectForKey:@"fps"]) {
		_fps = [[settings objectForKey:@"fps"] intValue];
	}

	if ([self.videoFormat intValue] == 2) {
		[compressionProperties setObject: [NSNumber numberWithFloat: 0.85] forKey: AVVideoQualityKey];
	} else {
		if ([settings objectForKey:@"bitrate"]) {
			_kbps = [[settings objectForKey:@"bitrate"] intValue];
			if (_kbps <= 0) _kbps = 5000;
		}

		[compressionProperties setObject: [NSNumber numberWithInt: _fps] forKey: AVVideoMaxKeyFrameIntervalKey];
		[compressionProperties setObject: [NSNumber numberWithInt: _kbps * 1000] forKey: AVVideoAverageBitRateKey];
		if ([settings objectForKey:@"h264ProfileAndLevel"]) {
			if ([[settings objectForKey:@"h264ProfileAndLevel"] intValue] == 1) {
				[compressionProperties setObject: AVVideoProfileLevelH264Main31 forKey: AVVideoProfileLevelKey];
			} else if ([[settings objectForKey:@"h264ProfileAndLevel"] intValue] == 2) {
				[compressionProperties setObject: AVVideoProfileLevelH264Baseline41 forKey: AVVideoProfileLevelKey];
			} else if ([[settings objectForKey:@"h264ProfileAndLevel"] intValue] == 3) {
				[compressionProperties setObject: AVVideoProfileLevelH264Baseline31 forKey: AVVideoProfileLevelKey];
			} else {
				[compressionProperties setObject: AVVideoProfileLevelH264Main41 forKey: AVVideoProfileLevelKey];
			}
		} else {
			[compressionProperties setObject: AVVideoProfileLevelH264Main41 forKey: AVVideoProfileLevelKey];
		}
	}

	// Setup output settings, Codec, Width, Height, Compression
	int videowidth = _width;
	int videoheight = _height;
	if ([settings objectForKey:@"vidsize"]) {
		if ([[settings objectForKey:@"vidsize"] intValue] == 0) {
			videowidth *= 0.50; //If it's set to half-size, divide both by 2.
			videoheight *= 0.50;
		} else if ([[settings objectForKey:@"vidsize"] intValue] == 2) {
			videowidth *= 0.75; //If it's set to half-size, divide both by 2.
			videoheight *= 0.75;
		}
	}

	if (videowidth % 2 != 0) {
		videowidth -= 1;
	}

	NSMutableDictionary *outputSettings = [NSMutableDictionary dictionaryWithObjectsAndKeys:
										   [self.videoFormat intValue] == 2 ? AVVideoCodecJPEG : AVVideoCodecH264, AVVideoCodecKey,
										   [NSNumber numberWithInt:videowidth], AVVideoWidthKey,
										   [NSNumber numberWithInt:videoheight], AVVideoHeightKey,
										   compressionProperties, AVVideoCompressionPropertiesKey,
										   nil];

	NSParameterAssert([_videoWriter canApplyOutputSettings:outputSettings forMediaType:AVMediaTypeVideo]);

	// Get a AVAssetWriterInput
	// Add the output settings
	_videoWriterInput = [[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
															outputSettings:outputSettings] retain];

	// Check if AVAssetWriter will take an AVAssetWriterInput
	NSParameterAssert(_videoWriterInput);
	NSParameterAssert([_videoWriter canAddInput:_videoWriterInput]);
	[_videoWriter addInput:_videoWriterInput];

	// Setup buffer attributes, PixelFormatType, PixelBufferWidth, PixelBufferHeight, PixelBufferMemoryAlocator
	NSDictionary *bufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
									  [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
									  [NSNumber numberWithInt:_width], kCVPixelBufferWidthKey,
									  [NSNumber numberWithInt:_height], kCVPixelBufferHeightKey,
									  kCFAllocatorDefault, kCVPixelBufferMemoryAllocatorKey,
									  nil];


	// 4 Bytes per pixel
	int bytesPerElement = 4;

	CVPixelBufferRef tmp = NULL;
	CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, _width, _height, kCVPixelFormatType_32BGRA, (CFDictionaryRef)bufferAttributes, &tmp);
	if (status == kCVReturnSuccess) {
		_bytesPerRow = CVPixelBufferGetBytesPerRow(tmp);
		CVPixelBufferRelease(tmp);
	} else {
		// Bytes per row
		_bytesPerRow = (bytesPerElement * roundUpToMultiple(_width, 16));
	}

	// Get AVAssetWriterInputPixelBufferAdaptor with the buffer attributes
	_pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput
																						   sourcePixelBufferAttributes:bufferAttributes];
	[_pixelBufferAdaptor retain];

	//FPS
	_videoWriterInput.mediaTimeScale = _fps;
	_videoWriter.movieTimeScale = _fps;

	//Start a session:
	[_videoWriterInput setExpectsMediaDataInRealTime:YES];
	[_videoWriter startWriting];
	[_videoWriter startSessionAtSourceTime:kCMTimeZero];

	NSParameterAssert(_pixelBufferAdaptor.pixelBufferPool != NULL);
}


- (void)_finishEncoding
{
	// Tell the AVAssetWriterInput were done appending buffers
	[_videoWriterInput markAsFinished];

	// Tell the AVAssetWriter to finish and close the file
	[_videoWriter finishWriting];

	// Make objects go away
	[_videoWriter release];
	[_videoWriterInput release];
	[_pixelBufferAdaptor release];
	_videoWriter = nil;
	_videoWriterInput = nil;
	_pixelBufferAdaptor = nil;

	// Stop the audio recording
	if ([self.recordAudio boolValue] == YES) {
		[_audioRecorder stop];
		[_audioRecorder release];
		_audioRecorder = nil;
	}

	[_recordStartDate release];
	_recordStartDate = nil;

	[self addAudioTrackToRecording];
}

- (void)addAudioTrackToRecording {
	double degrees = 0.0;
	if ([settings objectForKey:@"vidorientation"])
		degrees = [[settings objectForKey:@"vidorientation"] doubleValue];

	NSString *videoPath = self.videoOutPath;
	NSString *audioPath = self.audioOutPath;

	NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
	NSURL *audioURL = [NSURL fileURLWithPath:audioPath];

	AVURLAsset *videoAsset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
	AVURLAsset *audioAsset = [[AVURLAsset alloc] initWithURL:audioURL options:nil];

	AVAssetTrack *assetVideoTrack = nil;
	AVAssetTrack *assetAudioTrack = nil;

	if ([[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
		NSArray *assetArray = [videoAsset tracksWithMediaType:AVMediaTypeVideo];
		if ([assetArray count] > 0)
			assetVideoTrack = assetArray[0];
	}

	if ([[NSFileManager defaultManager] fileExistsAtPath:audioPath] && [self.recordAudio boolValue] == YES) {
		NSArray *assetArray = [audioAsset tracksWithMediaType:AVMediaTypeAudio];
		if ([assetArray count] > 0)
			assetAudioTrack = assetArray[0];
	}

	AVMutableComposition *mixComposition = [AVMutableComposition composition];

	if (assetVideoTrack != nil) {
		AVMutableCompositionTrack *compositionVideoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
		[compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.duration) ofTrack:assetVideoTrack atTime:kCMTimeZero error:nil];
		if (assetAudioTrack != nil) [compositionVideoTrack scaleTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.duration) toDuration:audioAsset.duration];
		[compositionVideoTrack setPreferredTransform:CGAffineTransformMakeRotation(degreesToRadians(degrees))];
	}

	if (assetAudioTrack != nil) {
		AVMutableCompositionTrack *compositionAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
		[compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioAsset.duration) ofTrack:assetAudioTrack atTime:kCMTimeZero error:nil];
	}

	NSString *exportPath = [videoPath substringWithRange:NSMakeRange(0, videoPath.length - 8)];
	exportPath = [NSString stringWithFormat:@"%@.%@", exportPath, [self.videoFormat intValue] == 1 ? @"mp4" : @"mov"];

	NSURL *exportURL = [NSURL fileURLWithPath:exportPath];

	AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:mixComposition presetName:AVAssetExportPresetPassthrough];
	[exportSession setOutputFileType:([self.videoFormat intValue] == 1 ? AVFileTypeMPEG4 : AVFileTypeQuickTimeMovie)];

	[exportSession setOutputURL:exportURL];
	[exportSession setShouldOptimizeForNetworkUse:NO];

	[exportSession exportAsynchronouslyWithCompletionHandler:^(void){
		switch (exportSession.status) {
			case AVAssetExportSessionStatusCompleted:{
				[[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
				[[NSFileManager defaultManager] removeItemAtPath:audioPath error:nil];
				[videoAsset release];
				[audioAsset release];
				break;
			}

			case AVAssetExportSessionStatusFailed:
				[videoAsset release];
				[audioAsset release];
				NSLog(@"Failed: %@", exportSession.error);
				break;

			case AVAssetExportSessionStatusCancelled:
				[videoAsset release];
				[audioAsset release];
				NSLog(@"Canceled: %@", exportSession.error);
				break;

			default:
				[videoAsset release];
				[audioAsset release];
				break;
		}

		if ([self.delegate respondsToSelector:@selector(screenRecorderDidStopRecording:)]) {
			[self.delegate screenRecorderDidStopRecording:self];
		}
	}];
}


#pragma mark - Delegate Stuff
- (void)_sendDelegateTimeUpdate:(NSTimer *)timer
{
	if ([self.delegate respondsToSelector:@selector(screenRecorder:recordingTimeChanged:)]) {
		NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:_recordStartDate];
		[self.delegate screenRecorder:self recordingTimeChanged:timeInterval];
	}
}

@end
