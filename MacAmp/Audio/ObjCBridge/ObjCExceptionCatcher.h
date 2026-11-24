#ifndef MACAMP_OBJC_EXCEPTION_CATCHER_H
#define MACAMP_OBJC_EXCEPTION_CATCHER_H

#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

@interface MacAmpObjC : NSObject

+ (BOOL)startEngine:(AVAudioEngine *)engine NS_SWIFT_NAME(start(_:));
+ (void)pauseEngine:(AVAudioEngine *)engine NS_SWIFT_NAME(pause(_:));
+ (void)stopEngine:(AVAudioEngine *)engine NS_SWIFT_NAME(stop(_:));
+ (void)resetEngine:(AVAudioEngine *)engine NS_SWIFT_NAME(reset(_:));
+ (void)prepareEngine:(AVAudioEngine *)engine NS_SWIFT_NAME(prepare(_:));

+ (BOOL)connectInEngine:(AVAudioEngine *)engine
                   from:(AVAudioNode *)fromNode
                     to:(AVAudioNode *)toNode
                fromBus:(NSInteger)fromBus
                  toBus:(NSInteger)toBus
                 format:(nullable AVAudioFormat *)format
    NS_SWIFT_NAME(connect(in:from:to:fromBus:toBus:format:));

+ (void)disconnectOutputInEngine:(AVAudioEngine *)engine
                            node:(AVAudioNode *)node
    NS_SWIFT_NAME(disconnectOutput(in:node:));

+ (BOOL)playNode:(AVAudioPlayerNode *)player NS_SWIFT_NAME(play(_:));
+ (void)pauseNode:(AVAudioPlayerNode *)player NS_SWIFT_NAME(pause(_:));
+ (void)stopNode:(AVAudioPlayerNode *)player NS_SWIFT_NAME(stop(_:));

+ (BOOL)playbackTimeForNode:(AVAudioPlayerNode *)player
                 sampleTime:(double *)sampleTimeOut
                 sampleRate:(double *)sampleRateOut
    NS_SWIFT_NAME(playbackTime(for:sampleTime:sampleRate:));

+ (BOOL)scheduleSegmentOnNode:(AVAudioPlayerNode *)player
                         file:(AVAudioFile *)file
                startingFrame:(AVAudioFramePosition)startFrame
                   frameCount:(AVAudioFrameCount)frameCount
                   onComplete:(void (^)(void))onComplete
    NS_SWIFT_NAME(scheduleSegment(on:file:startingFrame:frameCount:onComplete:));

+ (BOOL)scheduleBufferOnNode:(AVAudioPlayerNode *)player
                      buffer:(AVAudioPCMBuffer *)buffer
                  onComplete:(void (^)(void))onComplete
    NS_SWIFT_NAME(scheduleBuffer(on:buffer:onComplete:));

+ (BOOL)installTapOnNode:(AVAudioNode *)node
                     bus:(NSInteger)bus
              bufferSize:(AVAudioFrameCount)bufferSize
                   block:(void (^)(AVAudioPCMBuffer *buffer))tapBlock
    NS_SWIFT_NAME(installTap(on:bus:bufferSize:block:));

+ (void)removeTapOnNode:(AVAudioNode *)node
                    bus:(NSInteger)bus
    NS_SWIFT_NAME(removeTap(on:bus:));

+ (BOOL)raiseTestException:(NSString *)reason NS_SWIFT_NAME(raiseTestException(_:));

@end

NS_ASSUME_NONNULL_END

#endif
