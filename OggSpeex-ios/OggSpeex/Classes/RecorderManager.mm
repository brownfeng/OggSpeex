//
//  RecorderManager.mm
//  OggSpeex
//
//  Created by Jiang Chuncheng on 6/25/13.
//  Copyright (c) 2013 Sense Force. All rights reserved.
//

#import "RecorderManager.h"
#import "AQRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface RecorderManager()

- (void)updateLevelMeter:(id)sender;
- (void)stopRecording:(BOOL)isCanceled;

@end

@implementation RecorderManager

@synthesize dateStartRecording, dateStopRecording;
@synthesize encapsulator;
@synthesize timerLevelMeter;
@synthesize timerTimeout;

static RecorderManager *mRecorderManager = nil;
AQRecorder *mAQRecorder;
AudioQueueLevelMeterState *levelMeterStates;

+ (RecorderManager *)sharedManager {
    @synchronized(self) {
        if (mRecorderManager == nil)
        {
            mRecorderManager = [[self alloc] init];
        }
    }
    return mRecorderManager;
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self)
    {
        if(mRecorderManager == nil)
        {
            mRecorderManager = [super allocWithZone:zone];
            return mRecorderManager;
        }
    }
    
    return nil;
}
/**

 
 在startRecording函数中，先实例化类AQRecorder，该类是用C++实现的，主要用作录制音频文件（核心类）。随后调用函数AudioSessionInitialize初始化音频，并添加回调函数interruptionListener，若监听被打断则停止AQRecorder类的录制工作。若返回值不是error则对音频添加相应的属性，并且回调函数为propListener，若监听的属性不正确，就停止录音。当然了，所有的音频都是以文件为单位的，在startRecording函数中利用[EncapsulatordefaultFileName]来获取音频的存放地址，Encapsulator类也是一个很重要的类，它封装了ogg,极大的方便了我们调用它里面的函数来实现录音。
 函数- (void)stopRecording的作用大家想必都知道就是停止录音，但是不取消音频；
 函数- (void)cancelRecording的作用则是停止录音并且取消；
 函数recordedTimeInterval则是获取录音时间，单位为float;

 
 */


- (void)startRecording {
    if ( ! mAQRecorder) {
        
        mAQRecorder = new AQRecorder();
        
        OSStatus error = AudioSessionInitialize(NULL, NULL, interruptionListener, (__bridge void *)self);
        if (error) printf("ERROR INITIALIZING AUDIO SESSION! %d\n", (int)error);
        else
        {
            UInt32 category = kAudioSessionCategory_PlayAndRecord;
            error = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
            if (error) printf("couldn't set audio category!");
           //添加属性监听，一旦有属性改变则调用其中的propListener函数
            error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, propListener, (__bridge void *)self);
            if (error) printf("ERROR ADDING AUDIO SESSION PROP LISTENER! %d\n", (int)error);
            UInt32 inputAvailable = 0;
            UInt32 size = sizeof(inputAvailable);
            
            // we do not want to allow recording if input is not available
            error = AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &size, &inputAvailable);
            if (error) printf("ERROR GETTING INPUT AVAILABILITY! %d\n", (int)error);
            
            // we also need to listen to see if input availability changes
            error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioInputAvailable, propListener, (__bridge void *)self);
            if (error) printf("ERROR ADDING AUDIO SESSION PROP LISTENER! %d\n", (int)error);
            
            error = AudioSessionSetActive(true); 
            if (error) printf("AudioSessionSetActive (true) failed");
        }
        
    }
    //获取音频存放地址
    filename = [NSString stringWithString:[Encapsulator defaultFileName]];
    NSLog(@"filename:%@",filename);
    
//    if (self.encapsulator) {
//        self.encapsulator.delegete = nil;
//        [self.encapsulator release];
//    }
//    self.encapsulator = [[[Encapsulator alloc] initWithFileName:filename] autorelease];
//    self.encapsulator.delegete = self;
    
    if ( ! self.encapsulator) {
        self.encapsulator = [[Encapsulator alloc] initWithFileName:filename];
        self.encapsulator.delegete = self;
    }
    else {
        [self.encapsulator resetWithFileName:filename];
    }
    
    if ( ! mAQRecorder->IsRunning()) {
        NSLog(@"audio session category : %@", [[AVAudioSession sharedInstance] category]);
        Boolean recordingWillBegin = mAQRecorder->StartRecord(encapsulator);
        if ( ! recordingWillBegin) {
            if ([self.delegate respondsToSelector:@selector(recordingFailed:)]) {
                [self.delegate recordingFailed:@"程序错误，无法继续录音，请重启程序试试"];
            }
            return;
        }
    }

    self.dateStartRecording = [NSDate date];
    
    levelMeterStates = (AudioQueueLevelMeterState *)malloc(sizeof(AudioQueueLevelMeterState) * 1);
    self.timerLevelMeter = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateLevelMeter:) userInfo:nil repeats:YES];
    self.timerTimeout = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(timeoutCheck:) userInfo:nil repeats:NO];
}

- (void)stopRecording {
    [self stopRecording:NO];
}

- (void)cancelRecording {
    [self stopRecording:YES];
}

- (void)stopRecording:(BOOL)isCanceled {
    if (self.delegate) {
        [self.delegate recordingStopped];
    }
    if (isCanceled) {
        if (self.encapsulator) {
            [self.encapsulator stopEncapsulating:YES];
        }
    }
    [self.timerLevelMeter invalidate];
    [self.timerTimeout invalidate];
    self.timerLevelMeter = nil;
//    free(levelMeterStates);
    if (mAQRecorder) {
        mAQRecorder->StopRecord();
    }
    self.dateStopRecording = [NSDate date];
}

- (void)encapsulatingOver {
    if (self.delegate) {
        [self.delegate recordingFinishedWithFileName:filename time:[self recordedTimeInterval]];
    }
}

- (NSTimeInterval)recordedTimeInterval {
    return (dateStopRecording && dateStartRecording) ? [dateStopRecording timeIntervalSinceDate:dateStartRecording] : 0;
}

- (void)updateLevelMeter:(id)sender {
    if (self.delegate) {
        UInt32 dataSize = sizeof(AudioQueueLevelMeterState);
        AudioQueueGetProperty(mAQRecorder->Queue(), kAudioQueueProperty_CurrentLevelMeter, levelMeterStates, &dataSize);
        if ([self.delegate respondsToSelector:@selector(levelMeterChanged:)]) {
            [self.delegate levelMeterChanged:levelMeterStates[0].mPeakPower];
        }

    }
}

- (void)timeoutCheck:(id)sender {
    [self stopRecording];
    [[self delegate] recordingTimeout];
}

- (void)dealloc {
    if (mAQRecorder) {
        delete mAQRecorder;
    }
    self.encapsulator = nil;
}

#pragma mark AudioSession listeners
void interruptionListener(	void *	inClientData,
                          UInt32	inInterruptionState)
{
	RecorderManager *THIS = (__bridge RecorderManager*)inClientData;
	if (inInterruptionState == kAudioSessionBeginInterruption)
	{
		if (mAQRecorder->IsRunning()) {
			[THIS stopRecording];
		}
	}
}

void propListener(	void *                  inClientData,
                  AudioSessionPropertyID	inID,
                  UInt32                  inDataSize,
                  const void *            inData)
{
	RecorderManager *THIS = (__bridge RecorderManager*)inClientData;
	if (inID == kAudioSessionProperty_AudioRouteChange)
	{
		CFDictionaryRef routeDictionary = (CFDictionaryRef)inData;
		//CFShow(routeDictionary);
		CFNumberRef reason = (CFNumberRef)CFDictionaryGetValue(routeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_Reason));
		SInt32 reasonVal;
		CFNumberGetValue(reason, kCFNumberSInt32Type, &reasonVal);
		if (reasonVal != kAudioSessionRouteChangeReason_CategoryChange)
		{
			// stop the queue if we had a non-policy route change
			if (mAQRecorder->IsRunning()) {
				[THIS stopRecording];
			}
		}
	}
	else if (inID == kAudioSessionProperty_AudioInputAvailable)
	{
		if (inDataSize == sizeof(UInt32))
        {
//			UInt32 isAvailable = *(UInt32*)inData;
			// disable recording if input is not available
//			BOOL available = (isAvailable > 0) ? YES : NO;
		}
	}
}

@end
