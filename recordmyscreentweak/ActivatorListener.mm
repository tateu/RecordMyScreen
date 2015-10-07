#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <libactivator/libactivator.h>
#import "CSRecordQueryWindow.h"
#import "CSRecordCompletionAlert.h"
#import "../RecordMyScreen/CSScreenRecorder.h"

typedef void(^RecordMyScreenCallback)(void);

@interface CSRecordMyScreenListener : NSObject<LAListener,CSScreenRecorderDelegate> {
	CSScreenRecorder *_screenRecorder;
}
@end

@implementation CSRecordMyScreenListener

+(void)load {
	[[LAActivator sharedInstance] registerListener:[self new] forName:@"org.coolstar.recordmyscreen"];
}

- (void)activator:(LAActivator *)listener receiveEvent:(LAEvent *)event
{
	if (!_screenRecorder){
		CSRecordQueryWindow *queryWindow = [[CSRecordQueryWindow alloc] initWithFrame:CGRectMake(0,0,320,150)];
		queryWindow.center = CGPointMake([[UIScreen mainScreen] bounds].size.width/2, [[UIScreen mainScreen] bounds].size.height/2);
		queryWindow.onConfirmation = ^{
			_screenRecorder = [[CSScreenRecorder alloc] init];

			NSDictionary *settings = [[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/org.coolstar.recordmyscreen.plist"];
			if (!settings) {
				settings = [[NSDictionary alloc] init];
			}

			NSNumber *audioChannels = [settings objectForKey:@"channels"] ?: @(1);
			NSNumber *sampleRate = [settings objectForKey:@"samplerate"] ?: @(44100);
			NSNumber *audioBitRate = [settings objectForKey:@"audioBitRate"] ?: @(96000);
			NSNumber *recordAudio = [settings objectForKey:@"recordaudio"] ?: @(NO);
			NSNumber *videoFormat = [settings objectForKey:@"vidformat"] ?: @(0);

			NSString *videoPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/video.mp4"];
			NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setDateFormat:@"yyyyMMdd_HHmmss"];
			NSString *date = [dateFormatter stringFromDate:[NSDate date]];
			NSString *outName = [NSString stringWithFormat:@"Documents/%@_tmp.%@",date, [videoFormat intValue] == 2 ? @"mov" : @"mp4"];
			videoPath = [NSHomeDirectory() stringByAppendingPathComponent:outName];
			NSString *audioPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@_tmp.%@",date, [videoFormat intValue] == 2 ? @"caf" : @"aac"]];
			[dateFormatter release];

			_screenRecorder.videoOutPath = videoPath;
			_screenRecorder.audioOutPath = audioPath;
			_screenRecorder.numberOfAudioChannels = audioChannels;
			_screenRecorder.audioSampleRate = sampleRate;
			_screenRecorder.audioBitRate = audioBitRate;
			_screenRecorder.videoFormat = videoFormat;
			_screenRecorder.recordAudio = recordAudio;
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
				[_screenRecorder startRecordingScreen];
			});
			[settings release];
		};
	} else {
		[_screenRecorder stopRecordingScreen];
		CSRecordCompletionAlert *completionAlert = [[CSRecordCompletionAlert alloc] initWithFrame:CGRectMake(0,0,320,150)];
		completionAlert.center = CGPointMake([[UIScreen mainScreen] bounds].size.width/2, [[UIScreen mainScreen] bounds].size.height/2);
		[_screenRecorder release];
		_screenRecorder = nil;
	}
	[event setHandled:YES];
}

-(void)activator:(LAActivator *)listener abortEvent:(LAEvent *)event
{
}

// - (void)screenRecorderDidStopRecording:(CSScreenRecorder *)recorder {
// 	[_screenRecorder release];
// 	_screenRecorder = nil;
// }

@end;
