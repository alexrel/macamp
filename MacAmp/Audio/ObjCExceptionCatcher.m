#import "ObjCBridge/ObjCExceptionCatcher.h"

static void logException(NSString *label, NSException *exception) {
    NSLog(@"AudioEngine: Caught Objective-C exception in %@: %@: %@", label, exception.name, exception.reason);
}

@implementation MacAmpObjC

+ (BOOL)startEngine:(AVAudioEngine *)engine {
    NSError *error = nil;
    @try {
        return [engine startAndReturnError:&error] && error == nil && engine.isRunning;
    } @catch (NSException *exception) {
        logException(@"engine.start", exception);
        return NO;
    }
}

+ (void)pauseEngine:(AVAudioEngine *)engine {
    @try {
        [engine pause];
    } @catch (NSException *exception) {
        logException(@"engine.pause", exception);
    }
}

+ (void)stopEngine:(AVAudioEngine *)engine {
    @try {
        [engine stop];
    } @catch (NSException *exception) {
        logException(@"engine.stop", exception);
    }
}

+ (void)resetEngine:(AVAudioEngine *)engine {
    @try {
        [engine reset];
    } @catch (NSException *exception) {
        logException(@"engine.reset", exception);
    }
}

+ (void)prepareEngine:(AVAudioEngine *)engine {
    @try {
        [engine prepare];
    } @catch (NSException *exception) {
        logException(@"engine.prepare", exception);
    }
}

+ (BOOL)connectInEngine:(AVAudioEngine *)engine
                   from:(AVAudioNode *)fromNode
                     to:(AVAudioNode *)toNode
                fromBus:(NSInteger)fromBus
                  toBus:(NSInteger)toBus
                 format:(AVAudioFormat *)format {
    @try {
        [engine connect:fromNode to:toNode fromBus:(AVAudioNodeBus)fromBus toBus:(AVAudioNodeBus)toBus format:format];
        return YES;
    } @catch (NSException *exception) {
        logException(@"engine.connect", exception);
        return NO;
    }
}

+ (void)disconnectOutputInEngine:(AVAudioEngine *)engine node:(AVAudioNode *)node {
    @try {
        [engine disconnectNodeOutput:node];
    } @catch (NSException *exception) {
        logException(@"engine.disconnectNodeOutput", exception);
    }
}

+ (BOOL)playNode:(AVAudioPlayerNode *)player {
    @try {
        [player play];
        return player.isPlaying;
    } @catch (NSException *exception) {
        logException(@"playerNode.play", exception);
        return NO;
    }
}

+ (void)pauseNode:(AVAudioPlayerNode *)player {
    @try {
        [player pause];
    } @catch (NSException *exception) {
        logException(@"playerNode.pause", exception);
    }
}

+ (void)stopNode:(AVAudioPlayerNode *)player {
    @try {
        [player stop];
    } @catch (NSException *exception) {
        logException(@"playerNode.stop", exception);
    }
}

+ (BOOL)playbackTimeForNode:(AVAudioPlayerNode *)player
                 sampleTime:(double *)sampleTimeOut
                 sampleRate:(double *)sampleRateOut {
    @try {
        AVAudioTime *nodeTime = player.lastRenderTime;
        if (!nodeTime || (!nodeTime.isSampleTimeValid && !nodeTime.isHostTimeValid)) return NO;
        AVAudioTime *playerTime = [player playerTimeForNodeTime:nodeTime];
        if (!playerTime || playerTime.sampleRate <= 0) return NO;
        *sampleTimeOut = (double)playerTime.sampleTime;
        *sampleRateOut = playerTime.sampleRate;
        return YES;
    } @catch (NSException *exception) {
        logException(@"playerNode.playerTime", exception);
        return NO;
    }
}

+ (BOOL)scheduleSegmentOnNode:(AVAudioPlayerNode *)player
                         file:(AVAudioFile *)file
                startingFrame:(AVAudioFramePosition)startFrame
                   frameCount:(AVAudioFrameCount)frameCount
                   onComplete:(void (^)(void))onComplete {
    @try {
        [player scheduleSegment:file
                  startingFrame:startFrame
                     frameCount:frameCount
                         atTime:nil
         completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
              completionHandler:^(AVAudioPlayerNodeCompletionCallbackType type) {
            (void)type;
            onComplete();
        }];
        return YES;
    } @catch (NSException *exception) {
        logException(@"playerNode.scheduleSegment", exception);
        return NO;
    }
}

+ (BOOL)scheduleBufferOnNode:(AVAudioPlayerNode *)player
                      buffer:(AVAudioPCMBuffer *)buffer
                  onComplete:(void (^)(void))onComplete {
    @try {
        [player scheduleBuffer:buffer
        completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
             completionHandler:^(AVAudioPlayerNodeCompletionCallbackType type) {
            (void)type;
            onComplete();
        }];
        return YES;
    } @catch (NSException *exception) {
        logException(@"streamNode.scheduleBuffer", exception);
        return NO;
    }
}

+ (BOOL)installTapOnNode:(AVAudioNode *)node
                     bus:(NSInteger)bus
              bufferSize:(AVAudioFrameCount)bufferSize
                   block:(void (^)(AVAudioPCMBuffer *buffer))tapBlock {
    @try {
        [node installTapOnBus:(AVAudioNodeBus)bus bufferSize:bufferSize format:nil block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            (void)when;
            if (buffer) tapBlock(buffer);
        }];
        return YES;
    } @catch (NSException *exception) {
        logException(@"node.installTap", exception);
        return NO;
    }
}

+ (void)removeTapOnNode:(AVAudioNode *)node bus:(NSInteger)bus {
    @try {
        [node removeTapOnBus:(AVAudioNodeBus)bus];
    } @catch (NSException *exception) {
        logException(@"node.removeTap", exception);
    }
}

+ (BOOL)raiseTestException:(NSString *)reason {
    @try {
        [NSException raise:NSInternalInconsistencyException format:@"%@", reason];
        return YES;
    } @catch (NSException *exception) {
        logException(@"test", exception);
        return NO;
    }
}

@end
