//
//  RecorderManager.h
//  OggSpeex
//
//  Created by Jiang Chuncheng on 6/25/13.
//  Copyright (c) 2013 Sense Force. All rights reserved.
//

#import <Foundation/Foundation.h>
//#import "AQRecorder.h"
#import "Encapsulator.h"

@protocol RecordingDelegate <NSObject>

/**
 *  录音结束以后的返回的时间和调用事件
 *
 *  @param filePath 录音以后保存的文件的地址
 *  @param interval 整个录音的时间长度
 */
- (void)recordingFinishedWithFileName:(NSString *)filePath time:(NSTimeInterval)interval;

/**
 *  录音超时,默认超时时间是60s
 */
- (void)recordingTimeout;

/**
 *  录音机停止采集
 */
- (void)recordingStopped;

/**
 *  录音出错
 *
 *  @param failureInfoString 出错信息
 */
- (void)recordingFailed:(NSString *)failureInfoString;

@optional
/**
 *  每0.1s会更新
 *
 *  @param levelMeter <#levelMeter description#>
 */
- (void)levelMeterChanged:(float)levelMeter;

@end

@interface RecorderManager : NSObject <EncapsulatingDelegate> {
    
    Encapsulator *encapsulator;
    NSString *filename;
    NSDate *dateStartRecording;
    NSDate *dateStopRecording;
    NSTimer *timerLevelMeter;
    NSTimer *timerTimeout;
}

@property (nonatomic, weak)  id<RecordingDelegate> delegate;
@property (nonatomic, strong) Encapsulator *encapsulator;
@property (nonatomic, strong) NSDate *dateStartRecording, *dateStopRecording;
@property (nonatomic, strong) NSTimer *timerLevelMeter;
@property (nonatomic, strong) NSTimer *timerTimeout;

+ (RecorderManager *)sharedManager;

- (void)startRecording;

- (void)stopRecording;

- (void)cancelRecording;

- (NSTimeInterval)recordedTimeInterval;

@end
