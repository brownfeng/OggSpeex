//
//  PlayerManager.h
//  OggSpeex
//
//  Created by Jiang Chuncheng on 6/25/13.
//  Copyright (c) 2013 Sense Force. All rights reserved.
//

/**
 该函数首先判断音频文件是.spx格式的还是.mp3格式，随后通过解析类Decapsulator来解析音频并播放之（与Encapsulator类对应）。再类中还实现了距离监听的功能，当用户脸靠近手机时则会按掉屏幕打开听他，当远离时则打开扬声器屏幕变亮。
 总而言之，对好奇想尝试一下开发ios语音的人来说，这几个类绝对是个福音，封装的很好，调用起来也很方便。若想用作开发语音聊天的产品，则需要我们要加深理解他背后压缩与解压缩的的原理了。
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "Decapsulator.h"

@protocol PlayingDelegate <NSObject>

- (void)playingStoped;

@end

@interface PlayerManager : NSObject <DecapsulatingDelegate, AVAudioPlayerDelegate> {
    Decapsulator *decapsulator;
    AVAudioPlayer *avAudioPlayer;
    
}
@property (nonatomic, strong) Decapsulator *decapsulator;
@property (nonatomic, strong) AVAudioPlayer *avAudioPlayer;
@property (nonatomic, weak)  id<PlayingDelegate> delegate;

+ (PlayerManager *)sharedManager;

- (void)playAudioWithFileName:(NSString *)filename delegate:(id<PlayingDelegate>)newDelegate;
- (void)stopPlaying;

@end
