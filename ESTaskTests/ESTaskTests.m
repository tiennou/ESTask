//
//  ESTaskTests.m
//  ESTaskTests
//
//  Created by Etienne on 16/02/2016.
//  Copyright © 2016 Etienne Samson. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <ESTask/ESTask.h>

@interface ESTaskTests : XCTestCase {
    ESTask *task;
}

@end

@implementation ESTaskTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

//- (void)testExample {
//    // This is an example of a functional test case.
//    // Use XCTAssert and related functions to verify your tests produce the correct results.
//}

- (void)testLaunch {
    task = [[ESTask alloc] init];
    task.launchPath = @"/usr/bin/true";

    NSError *error = nil;
    BOOL success = [task launch:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
}

- (void)testInvalidLaunchPath {
    task = [[ESTask alloc] init];
    task.launchPath = @"/usr/";

    NSError *error = nil;
    BOOL success = [task launch:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ESTaskErrorInvalidLaunchPath);
}

- (void)testArguments1 {
    task = [[ESTask alloc] init];
    task.launchPath = @"/bin/echo";
    task.arguments = @[@"pon", @"test", @"/etc/hosts"];

    NSError *error = nil;
    BOOL success = [task launch:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
}

- (void)testOutputToStandardOutput {
    task = [[ESTask alloc] init];
    task.launchPath = @"/bin/echo";
    task.arguments = @[@"pon", @"test", @"/etc/hosts"];
    task.standardOutput = [NSFileHandle fileHandleWithStandardOutput];

    NSError *error = nil;
    BOOL success = [task launch:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);

    // Check your log
}

- (void)testOutputToFileDescriptor {
    task = [[ESTask alloc] init];
    task.launchPath = @"/bin/echo";
    task.arguments = @[@"pon", @"test", @"/etc/hosts"];
    task.standardOutput = [NSPipe pipe];

    NSError *error = nil;
    BOOL success = [task launch:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);

    [task waitUntilExit];

    NSData *data = [[(NSPipe *)task.standardOutput fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(output);
    XCTAssertEqualObjects(output, @"pon test /etc/hosts\n");
}

- (void)testWorkingDirectory1 {
    task = [[ESTask alloc] init];
    task.launchPath = @"/bin/pwd";
    task.currentDirectoryPath = @"/tmp";
    task.standardOutput = [NSPipe pipe];

    NSString *oldWorkDir = [[NSFileManager defaultManager] currentDirectoryPath];

    NSError *error = nil;
    BOOL success = [task launch:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    XCTAssertEqual(oldWorkDir, [[NSFileManager defaultManager] currentDirectoryPath]);

    NSData *data = [[(NSPipe *)task.standardOutput fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(output, @"/tmp\n");
}

- (void)testCallsTerminationHandler {
    task = [[ESTask alloc] init];
    task.launchPath = @"/bin/pwd";

    __block BOOL called = NO;
    task.terminationHandler = ^(ESTask *task) {
        called = YES;
    };

    BOOL success = [task launch:NULL];
    XCTAssertTrue(success);
    [task waitUntilExit];
    XCTAssertTrue(called);
}

- (void)testEnvironmentSet {
    task = [[ESTask alloc] init];
    task.launchPath = @"/usr/bin/env";
    task.environment = @{@"ENVVAR": @"envvalue"};
    task.standardOutput = [NSPipe pipe];

    BOOL success = [task launch:NULL];
    XCTAssertTrue(success);
    [task waitUntilExit];

    NSData *data = [[(NSPipe *)task.standardOutput fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(output);
    XCTAssertEqualObjects(output, @"ENVVAR=envvalue\n");
}

- (void)testEnvironmentDefault {
    task = [[ESTask alloc] init];
    task.launchPath = @"/usr/bin/env";
    task.standardOutput = [NSPipe pipe];

    BOOL success = [task launch:NULL];
    XCTAssertTrue(success);
    [task waitUntilExit];

    NSData *data = [[(NSPipe *)task.standardOutput fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(output);
    XCTAssertNotEqual(output, @"\n");
}

- (void)testTerminationReason {
    task = [[ESTask alloc] init];
    task.launchPath = @"/bin/sleep";
    task.arguments = @[@"3"];

    BOOL success = [task launch:NULL];
    XCTAssertTrue(success);
    [task terminate];
    [task waitUntilExit];
    XCTAssertEqual(task.terminationReason, NSTaskTerminationReasonUncaughtSignal);
    XCTAssertEqual(task.terminationStatus, 0);
}

- (void)testSuspend {
    task = [[ESTask alloc] init];
    task.launchPath = @"/bin/sleep";
    task.arguments = @[@"3"];

    BOOL success = [task launch:NULL];
    XCTAssertTrue(success);
    [task suspend];
    sleep(1);
    XCTAssertEqual(task.suspendCount, 1);
    [task resume];
    XCTAssertEqual(task.suspendCount, 0);
    [task waitUntilExit];
    XCTAssertEqual(task.terminationReason, NSTaskTerminationReasonExit);
    XCTAssertEqual(task.terminationStatus, 0);
}

- (void)testPassingFileDescriptors {
    task = [[ESTask alloc] init];
    task.launchPath = @"/bin/cat";
    task.standardInput = [NSFileHandle fileHandleForReadingAtPath:@"/etc/passwd"];
    task.standardOutput = [NSPipe pipe];

    BOOL success = [task launch:NULL];
    XCTAssertTrue(success);
    [task waitUntilExit];

    NSData *data = [[(NSPipe *)task.standardOutput fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(output);
}

- (void)testCompletionConvenienceMethod {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSError *error = nil;
    __block NSData *data = nil;
    BOOL success = [ESTask executeTask:@"/bin/cat"
                             arguments:@[@"/etc/hosts"]
                           inDirectory:nil
                                 error:&error
                     completionHandler:^(ESTask *task, NSData *readData) {
                         data = readData;

                         dispatch_semaphore_signal(semaphore);
                     }];
    XCTAssertTrue(success);
    if (!success) return;

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    XCTAssertNotNil(data);
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

@end
