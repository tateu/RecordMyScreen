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

			CFPreferencesAppSynchronize(CFSTR("org.coolstar.recordmyscreen"));
			NSNumber *audioChannels = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"channels"] ?: @(1);
			NSNumber *sampleRate = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"samplerate"] ?: @(44100);
			NSNumber *audioBitRate = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"audioBitRate"] ?: @(96000);
			NSNumber *recordAudio = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"recordaudio"] ?: @(NO);
			NSNumber *videoFormat = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"vidformat"] ?: @(0);

			NSNumber *fps = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"fps"] ?: @(24);
			NSNumber *kbps = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"bitrate"] ?: @(5000);
			NSNumber *h264ProfileAndLevel = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"h264ProfileAndLevel"] ?: @(0);
			NSNumber *vidsize = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"vidsize"] ?: @(1);
			NSNumber *vidorientation = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.coolstar.recordmyscreen"] objectForKey:@"vidorientation"] ?: @(0);

			NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setDateFormat:@"yyyyMMdd_HHmmss"];
			NSString *date = [dateFormatter stringFromDate:[NSDate date]];
			NSString *outName = [NSString stringWithFormat:@"Documents/%@_tmp.%@", date, [videoFormat intValue] == 2 ? @"mov" : @"mp4"];
			NSString *videoPath = [NSHomeDirectory() stringByAppendingPathComponent:outName];
			NSString *audioPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@_tmp.%@", date, [videoFormat intValue] == 2 ? @"caf" : @"aac"]];
			[dateFormatter release];

			_screenRecorder.videoOutPath = videoPath;
			_screenRecorder.audioOutPath = audioPath;
			_screenRecorder.numberOfAudioChannels = audioChannels;
			_screenRecorder.audioSampleRate = sampleRate;
			_screenRecorder.audioBitRate = audioBitRate;
			_screenRecorder.videoFormat = videoFormat;
			_screenRecorder.recordAudio = recordAudio;
			_screenRecorder.fps = fps;
			_screenRecorder.kbps = kbps;
			_screenRecorder.h264ProfileAndLevel = h264ProfileAndLevel;
			_screenRecorder.vidsize = vidsize;
			_screenRecorder.vidorientation = vidorientation;
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
				[_screenRecorder startRecordingScreen];
			});
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
