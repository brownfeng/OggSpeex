//
//  Encapsulator.m
//  OggSpeex
//
//  Created by Jiang Chuncheng on 6/25/13.
//  Copyright (c) 2013 Sense Force. All rights reserved.
//

#import "Encapsulator.h"

#define NOTIFICATION_ENCAPSULTING_OVER @"EncapsulatingOver"

@implementation Encapsulator

@synthesize moreDataInputing,isCanceled;
@synthesize speexHeader;
@synthesize mode, sampleRate, channels, nframes, vbr, streamSeraialNmber;
@synthesize mFileName;
@synthesize delegete;

void writeInt(unsigned char *dest, int offset, int value) {
    for(int i = 0;i < 4;i++) {
        dest[offset + i]=(unsigned char)(0xff & ((unsigned int)value)>>(i*8));
    }
}

void writeString(unsigned char *dest, int offset, unsigned char *value, int length) {
    unsigned char *tempPointr = dest + offset;
    memcpy(tempPointr, value, length);
}

/**
 *  辅助类,返回当前时间创建的文件的文件名 - 后缀的 .spx , 注意文件格式和音频编码格式的区别
 *
 *  @return 文件名
 */
+ (NSString *)defaultFileName {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *voiceDirectory = [documentsDirectory stringByAppendingPathComponent:@"voice"];
    if ( ! [[NSFileManager defaultManager] fileExistsAtPath:voiceDirectory]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:voiceDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return [voiceDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.spx", [[NSDate date] timeIntervalSince1970]]];
    
}

- (id)initWithFileName:(NSString *)filename {
    if (self = [super init]) {
        //传入重要参数,文件存储的地址
        mFileName = [NSString stringWithString:filename];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:filename]) {
            [fileManager removeItemAtPath:filename error:nil];
        }
        bufferData = [NSMutableData data];
        tempData = [NSMutableData data];
        pcmDatas = [NSMutableArray array];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(encapsulatingOver:) name:NOTIFICATION_ENCAPSULTING_OVER object:nil];
        
        //设置mode 采样率, 单channel 1帧, 可变bitRate
        [self setMode:0 sampleRate:8000 channels:1 frames:1 vbr:YES];
        
        //初始化speexHeader,其中包括重要的编码的信息: 采样率, 单声道, 窄声道(8bit)
        speex_init_header(&speexHeader, sampleRate, channels, &speex_nb_mode);
        
        operationQueue = [[NSOperationQueue alloc] init];
    }
    return self;
}

- (void)resetWithFileName:(NSString *)filename {
    for(NSOperation *operation in [operationQueue operations]) {
        [operation cancel];
    }
    mFileName = [NSString stringWithString:filename];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filename]) {
        [fileManager removeItemAtPath:filename error:nil];
    }

    [bufferData setLength:0];
    [tempData setLength:0];
    [pcmDatas removeAllObjects];
}

- (NSMutableData *)getBufferData {
    return bufferData;
}

- (NSMutableArray *)getPCMDatas {
    @synchronized(pcmDatas) {
        return pcmDatas;
    }
}


- (void)setMode:(int)_mode sampleRate:(int)_sampleRate channels:(int)_channels frames:(int)_nframes vbr:(BOOL)_vbr {
    self.mode = _mode;
    self.sampleRate = _sampleRate;
    self.channels = _channels;
    self.nframes = _nframes;
    self.vbr = _vbr;
    
}

/**
 *  创建包装Operation,并且将该行为加入到OperationQueue中
 */
- (void)prepareForEncapsulating {
        
    self.moreDataInputing = YES;
    self.isCanceled = NO;
    encapsulationOperation = [[EncapsulatingOperation alloc] initWithParent:self];
    if (operationQueue) {
        [operationQueue addOperation:encapsulationOperation];
    }
    
    //写入一些数据之前的头
    [encapsulationOperation writeHeaderWithComment:@"Encoded with:test by jcccn "];
    
}

/**
 *  核心方法 - 在recorder每次回调时候就会调用,将buffer中的数据传入到本方法中,然后使用buffer
 *
 *  @param buffer   最新的buffer中的audio data
 *  @param dataSize mAudioDataByteSize
 */
- (void)inputPCMDataFromBuffer:(Byte *)buffer size:(UInt32)dataSize {

    if ( ! self.moreDataInputing) {
        return;
    }
    int packetSize = FRAME_SIZE * 2; //首先计算每个 packet 有多大 -> 这个packetsize应该是自己定义的多大,这里一个packet中有2个frame,因此字节数目是frameSize的2倍
    @synchronized(pcmDatas) {
        //将buffer中的数据加入到tempData中,这个data是通过byte来管理的
        [tempData appendBytes:buffer length:dataSize];
        //只要tempData的数据大于一个packetSize,就可以去拆分PCM数据,将
        while ([tempData length] >= packetSize) {
            //取出tempData的前一个packetSize的数据量,并将这部分数据量放到pcmDatas中
            NSData *pcmData = [tempData subdataWithRange:NSMakeRange(0, packetSize)];
            //每次给pcmDatas array中添加的object士一个NSData*的对象,它的长度士一个packetSize
            [pcmDatas addObject:pcmData];
            
            //将tempData中已经加入到pcmDatas的数据清空 -> 注意这个方法如果传入的值为NULL,类似于将这部分bytes删除
            [tempData replaceBytesInRange:NSMakeRange(0, packetSize) withBytes:NULL length:0];
        }
    }
}

- (void)stopEncapsulating:(BOOL)forceCancel {
    self.moreDataInputing = NO;
    if ( ! self.isCanceled) {
        self.isCanceled = forceCancel;
    }
}

- (void)encapsulatingOver:(NSNotification *)notification {
    NSLog(@"encapsulatingOver by %@", [self description]);
    if (self.delegete) {
        [self.delegete encapsulatingOver];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@implementation EncapsulatingOperation

@synthesize mParent;

/**
 *  Operation的main方法,会一直循环获取pcmData数组中的数据,然后用speex进行压缩,将压缩后的数据packet封装成ogg packet,直到取消录音
 *  或者调用者标记当前moreDataInputing.
 */
- (void)main {
    SpeexCodec *codec = [[SpeexCodec alloc] init];
    [codec open:4];     //压缩率为4 -> 这个就是使用speex的压缩质量
    while ( ! self.mParent.isCanceled) {//如果要调用压缩方法的类没有取消录制
        if ([[self.mParent getPCMDatas] count] > 0) {//获取当前已经分页好的PCM数据,如果数据
            NSData *pcmData = [[self.mParent getPCMDatas] objectAtIndex:0];//取出第一个元素,它的长度士一个packetSize
            
            //通过codec压缩pcmData以后的数据为speexData -> 这里为什么用short* short:不少于两个byte 16bit
            NSData *speexData = [codec encode:(short *)[pcmData bytes] length:[pcmData length]/sizeof(short)];
            
            //将每个未压缩的packet的被speex压缩过的数据speexData,封装成一个ogg packet
            [self inputOggPacketFromSpeexData:speexData];
            
            [[self.mParent getPCMDatas] removeObjectAtIndex:0];//删除这个处理过的对象->然后所有的数据迁移一个位置
        }
        else {
            [NSThread sleepForTimeInterval:0.02];
            
            if ( ! [self.mParent moreDataInputing]) {//表明是否有更多的数据写入了pcmDatas 数组
                break;
            }
        }

    }
    [codec close];
    codec = nil;
    if ( ! [self.mParent isCanceled]) {
        [self outputAPage:NO endOfSteam:YES];
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_ENCAPSULTING_OVER object:self userInfo:nil];
    }
}

//初始化NSOperation
- (id)initWithParent:(Encapsulator *)parent {
    if (self = [super init]) {
        self.mParent = parent;
        
        isFirstInput = 1;
        mPacketCount = 0;
        mGranulepos = 0;
        
        oggPeckets = [NSMutableArray array];
        
        ogg_stream_init(&oggStreamState, arc4random()%8888);
    }
    return self;
}


//写入ogg的头以及comment
/**
 *  1 首先写入ogg的page是 headerPage: 主要包括常见的mode, bitrate,channels等重要的信息
 *  2 然后第二个page是 commentPage
 *  @param comment
 */
- (void)writeHeaderWithComment:(NSString *)comment {
    
    mPacketCount = 0;
    mGranulepos = 0;
    
    //first, write the ogg header page,头部
    unsigned char speexHeader[80];
    
    int offset = 0;
    writeString(speexHeader, offset+0, (unsigned char *)"Speex   ", 8);    //  0 -  7: speex_string
    int versionSize = sizeof(self.mParent.speexHeader.speex_version);
    NSLog(@"size of version(%s) chars array:%d",self.mParent.speexHeader.speex_version, versionSize);
    writeString(speexHeader, offset+8, (unsigned char *)self.mParent.speexHeader.speex_version, versionSize);  //8 - 27: speex_version
    writeInt(speexHeader, offset+28, 1);           // 28 - 31: speex_version_id
    writeInt(speexHeader, offset+32, 80);          // 32 - 35: header_size
    writeInt(speexHeader, offset+36, 8000);  // 36 - 39: rate
    writeInt(speexHeader, offset+40, 0);        // 40 - 43: mode (0=NB, 1=WB, 2=UWB)
    writeInt(speexHeader, offset+44, 4);           // 44 - 47: mode_bitstream_version
    writeInt(speexHeader, offset+48, 1);    // 48 - 51: nb_channels
    writeInt(speexHeader, offset+52, -1);          // 52 - 55: bitrate
    writeInt(speexHeader, offset+56, 160 << 0); // 56 - 59: frame_size (NB=160, WB=320, UWB=640)
    writeInt(speexHeader, offset+60, 1);     // 60 - 63: vbr
    writeInt(speexHeader, offset+64, 1);     // 64 - 67: frames_per_packet
    writeInt(speexHeader, offset+68, 0);           // 68 - 71: extra_headers
    writeInt(speexHeader, offset+72, 0);           // 72 - 75: reserved1
    writeInt(speexHeader, offset+76, 0);           // 76 - 79: reserved2
    
    ogg_packet speexHeaderPacket;//第一个ogg packet
    speexHeaderPacket.packet = (unsigned char *)speexHeader;
    speexHeaderPacket.bytes = 80;
    speexHeaderPacket.b_o_s = 1;//在packet中设置是bos
    speexHeaderPacket.e_o_s = 0;
    speexHeaderPacket.granulepos = 0;
    speexHeaderPacket.packetno = mPacketCount++;
    
    ogg_stream_packetin(&oggStreamState, &speexHeaderPacket);//将第一个packet放入ogg stream中,然后调用outputApage方法存储到文件中
    [self outputAPage:YES endOfSteam:NO];//由于是first page所以设置成YES
    NSLog(@"ogg header writed\n");
    
    
    
    //second. write the ogg comment page
    offset = 0;
    const char *commentChars = [comment cStringUsingEncoding:NSUTF8StringEncoding];
    int length = [comment lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    unsigned char speexCommentHeader[length + 8];
    writeInt(speexCommentHeader, offset, length);       // vendor comment size
    writeString(speexCommentHeader, offset+4, (unsigned char *)commentChars, length); // vendor comment
    writeInt(speexCommentHeader, offset+length+4, 0);   // user comment list length
    
    //第二页ogg_packet
    ogg_packet speexCommentPacket;
    speexCommentPacket.packet = (unsigned char *)speexCommentHeader;
    speexCommentPacket.bytes = length + 8;
    speexCommentPacket.b_o_s = 0;
    speexCommentPacket.e_o_s = 0;
    speexCommentPacket.granulepos = 0;
    speexCommentPacket.packetno = mPacketCount++;
    
    //将ogg封装的packet封装成page.
    ogg_stream_packetin(&oggStreamState, &speexCommentPacket);
    [self outputAPage:YES endOfSteam:NO];
    NSLog(@"ogg comment writed\n");
}

/**
 *  将data进行ogg封装
 *
 *  @param data 需要封装的数据
 */
- (void)inputOggPacketFromSpeexData:(NSData *)data {
    ogg_packet packet;//创建packet
    packet.packet = (unsigned char *)[data bytes];//包数据
    packet.bytes = (long)([data length]);
    packet.b_o_s = 0;
    packet.e_o_s = 0;
    mGranulepos += FRAME_SIZE;
    packet.granulepos = mGranulepos;
    packet.packetno = mPacketCount++;
    //将data -> packet -> 进入ogg Stream
    ogg_stream_packetin(&oggStreamState, &packet);
    
    [self checkPageSufficient];
}

//检查packet是否足够生成一个page
- (void)checkPageSufficient {
    [self outputAPage:NO endOfSteam:NO];
}

//将页保存至文件并重置一些计数器。是否关闭文件。
/**
 *  根据传入参数判断是否将ogg封装以后得数据写入文件.  其中bufferData是ogg封装的tempbuffer
 *
 *  @param isHeaderOrComment 当前是否将header 或者 comment 写入buffer
 *  @param endOfStream       是否完成ogg
 */
- (void)outputAPage:(BOOL)isHeaderOrComment endOfSteam:(BOOL)endOfStream {
    if (isHeaderOrComment || endOfStream) {//如果是否 士header或者comment或者ogg page完成
        ogg_stream_flush(&oggStreamState, &oggPage);//将ogg的缓存的内容到page中
        //在bufferData中写入oggPage header,然后向bufferData中写入oggPage body
        [[self.mParent getBufferData] appendBytes:oggPage.header length:oggPage.header_len];
        [[self.mParent getBufferData] appendBytes:oggPage.body length:oggPage.body_len];
        // 将 bufferdata 中的ogg page 写入到文件中
        [self writeDataToFile:[self.mParent getBufferData]];
        [[self.mParent getBufferData] setLength:0];//reset bufferdata
        
        if (endOfStream) {
            NSLog(@"end of stream");
//            self.mParent.moreDataInputing = NO;
        }
    }
    else {//将ogg stream 生成page &oggPage
        /**
         This constructs pages from buffered packet segments.  The pointers
         returned are to static buffers; do not free. The returned buffers are
         good only until the next call (using the same ogg_stream_state)
         */
        if (ogg_stream_pageout(&oggStreamState, &oggPage)) {
            NSLog(@"page out");
            //将ogg 的内容输出到文件中
            [[self.mParent getBufferData] appendBytes:oggPage.header length:oggPage.header_len];
            [[self.mParent getBufferData] appendBytes:oggPage.body length:oggPage.body_len];
            [self writeDataToFile:[self.mParent getBufferData]];
            
            [[self.mParent getBufferData] setLength:0];
        }
    }
    
}

/**
 *  将NSData数据写入到文件系统中,每次都从文件的末尾写入
 *
 *  @param newData 要写入的data数据
 */
- (void)writeDataToFile:(NSData *)newData {
    NSString *filename = (NSString *)self.mParent.mFileName;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ( ! [fileManager fileExistsAtPath:filename]) {
        [fileManager createFileAtPath:filename contents:nil attributes:nil];
    }
//    NSLog(@"write data of %d bytes to file %@", [newData length], filename);
    NSFileHandle *file = [NSFileHandle fileHandleForUpdatingAtPath:filename];
    [file seekToEndOfFile];
    [file writeData:newData];
    [file closeFile];
}


@end