//
//  PauseModeTests.m
//  LanguageKitTests
//
//  Created by Graham Lee on 21/02/2019.
//

#import <XCTest/XCTest.h>
#import "LKContinueMode.h"
#import "LKDebuggerService.h"
#import "LKPauseMode.h"

@interface PauseModeTests : XCTestCase

@end

@implementation PauseModeTests
{
    LKDebuggerService *_debugger;
}

- (void)setUp {
    _debugger = [LKDebuggerService new];
    _debugger.shouldStop = NO;
    [_debugger pause];
}

- (void)tearDown {
    _debugger = nil;
}

- (void)testResumingAPausedDebuggerPutsItBackInContinueMode {
    [_debugger resume];
    XCTAssertEqualObjects([_debugger.mode class], [LKContinueMode class], @"Resuming debugger puts it back in continue mode");
}

@end
