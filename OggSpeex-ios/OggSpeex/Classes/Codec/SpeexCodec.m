//
//  SpeexCodec.m
//  OggSpeex
//
//  Created by Jiang Chuncheng on 11/26/12.
//  Copyright (c) 2012 Sense Force. All rights reserved.
//

#import "SpeexCodec.h"

@implementation SpeexCodec
- (id)init {
    if (self = [super init]) {
        codecOpenedTimes = 0;
    }
    return self;
}

/*
 quality value 1 ~ 10
 */
- (void)open:(int)quality {
    if ((quality < 1) || (quality > 10)) {
        return;
    }
    if (codecOpenedTimes++ != 0) {
        return;
    }
    else {
        speex_bits_init(&encodeSpeexBits);
        speex_bits_init(&decodeSpeexBits);
        
        encodeState = speex_encoder_init(&speex_nb_mode);
        decodeState = speex_decoder_init(&speex_nb_mode);
        
        int tmp = quality;
        speex_encoder_ctl(encodeState, SPEEX_SET_QUALITY, &tmp);
        speex_encoder_ctl(encodeState, SPEEX_GET_FRAME_SIZE, &encodeFrameSize);
        speex_decoder_ctl(decodeState, SPEEX_GET_FRAME_SIZE, &decodeFrameSize);
    }
}

/**
 *  使用speex给pcmBuffer数据编码
 *
 *  @param pcmBuffer      要编码的pcmData
 *  @param lengthOfShorts pcm数据的长度
 *
 *  @return 已经编码好的data
 */
- (NSData *)encode:(short *)pcmBuffer length:(int)lengthOfShorts {
    if (codecOpenedTimes == 0) {
		return nil;
    }
    
    NSMutableData *decodedData = [NSMutableData dataWithCapacity:20];
    
    short input_frame[encodeFrameSize];
    char cbits[200];
    int nbBytes;
    //在下一帧压缩前,使用speex_bits_reset来清空重置bits结构体,以便接受新的帧
    speex_bits_reset(&encodeSpeexBits);
    
	int nSamples = (int)ceil(lengthOfShorts / (float)encodeFrameSize);
    
	for (int sampleIndex = 0; sampleIndex < nSamples; sampleIndex++) {
        memcpy(input_frame, pcmBuffer + (sampleIndex * encodeFrameSize * sizeof(short)), encodeFrameSize * sizeof(short));
        // 压缩时, 通过speex_encode_int进行对当前帧的压缩,并写入bit结构体
		speex_encode_int(encodeState, input_frame, &encodeSpeexBits);
        //压缩结束后,使用speex_bits_write来将压缩后的音频从bits中转移到speexFrame中
        nbBytes = speex_bits_write(&encodeSpeexBits, cbits, encodeFrameSize);
        
        [decodedData appendBytes:cbits length:nbBytes];
	}
	
    return decodedData;
}

- (int)decode:(unsigned char *)encodedBytes length:(int)lengthOfBytes output:(short *)decoded {
	if ( ! codecOpenedTimes)
		return 0;
    
    char cbits[200];
    memcpy(cbits, encodedBytes, lengthOfBytes);
    
    speex_bits_read_from(&decodeSpeexBits, cbits, lengthOfBytes);
    
    speex_decode_int(decodeState, &decodeSpeexBits, decoded);
    
	return decodeFrameSize;
}

- (void)close {
    if (--codecOpenedTimes != 0) {
		return;
    }
    
    speex_bits_destroy(&encodeSpeexBits);
	speex_bits_destroy(&decodeSpeexBits);
    speex_encoder_destroy(encodeState);
	speex_decoder_destroy(decodeState);
}

- (void)dealloc {
    [self close];
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

@end