//
//  ESTask.h
//  ESTask
//
//  Created by Etienne on 16/02/2016.
//  Copyright © 2016 Etienne Samson. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ESTaskErrorDomain;

typedef NS_ENUM(NSUInteger, ESTaskErrorCode) {
    ESTaskErrorSpawnFailed = 1,
    ESTaskErrorInvalidLaunchPath,
    ESTaskErrorInvalidWorkingDirectory,
    ESTaskErrorTooManyArguments,
    ESTaskErrorFileActionFailure,
    ESTaskErrorChangeDirectoryFailed,
};

@interface ESTask : NSObject
- (instancetype)init NS_DESIGNATED_INITIALIZER;

// these methods can only be set before a launch
@property (nullable, copy) NSString *launchPath;
@property (nullable, copy) NSArray<NSString *> *arguments;
@property (nullable, copy) NSDictionary<NSString *, NSString *> *environment; // if not set, use current
@property (copy) NSString *currentDirectoryPath; // if not set, use current

// standard I/O channels; could be either an NSFileHandle or an NSPipe
@property (nullable, retain) id standardInput;
@property (nullable, retain) id standardOutput;
@property (nullable, retain) id standardError;

// actions
- (void)launch; // XXX: Deprecated, NS_UNAVAILABLE ?

- (BOOL)launch:(NSError **)error;

- (void)interrupt; // Not always possible. Sends SIGINT.
- (void)terminate; // Not always possible. Sends SIGTERM.

- (BOOL)suspend;
- (BOOL)resume;

// status
@property (readonly) int processIdentifier;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly) NSInteger suspendCount;

@property (readonly) int terminationStatus;
@property (readonly) NSTaskTerminationReason terminationReason;

@property (nullable, copy) void (^terminationHandler)(ESTask *task);

@property NSQualityOfService qualityOfService;

@end

@interface ESTask (ESTaskConveniences)

+ (BOOL)executeTask:(NSString *)command arguments:(nullable NSArray *)arguments inDirectory:(nullable NSString *)directory error:(NSError **)error terminationHandler:(void (^)(ESTask *task))terminationHandler;

+ (BOOL)executeTask:(NSString *)command arguments:(nullable NSArray *)arguments inDirectory:(nullable NSString *)directory error:(NSError **)error completionHandler:(void (^)(ESTask *task, NSData * _Nullable readData))completionHandler;

+ (instancetype)taskWithCommand:(NSString *)command arguments:(nullable NSArray *)arguments inDirectory:(nullable NSString *)directory;

- (BOOL)launch:(NSError **)error completionHandler:(void (^)(ESTask *task, NSData * _Nullable readData))completionHandler;

- (BOOL)launch:(NSError **)error terminationHandler:(void (^)(ESTask *task))terminationHandler;

+ (ESTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments;
// convenience; create and launch

- (void)waitUntilExit;
// poll the runLoop in defaultMode until task completes

@end

NS_ASSUME_NONNULL_END