//
//  ESTask.m
//  ESTask
//
//  Created by Etienne on 16/02/2016.
//  Copyright © 2016 Etienne Samson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ESTask.h"

#include <crt_externs.h> // for _NSGetEnviron
#include <spawn.h>

static inline BOOL errorWithCodeAndInfo(NSError **error, NSInteger code, NSDictionary *info)
{
    if (!error) return NO;

    *error = [NSError errorWithDomain:ESTaskErrorDomain code:code userInfo:info];

    return NO;
}

static inline BOOL errorWithCode(NSError **error, NSInteger code, NSString *failureReasonFormat, ...)
{
    if (!error) return NO;

    va_list args;
    va_start(args, failureReasonFormat);

    NSString *formattedFailureReason = [[NSString alloc] initWithFormat:failureReasonFormat arguments:args];
    va_end(args);

    NSDictionary *info = @{
                           NSLocalizedDescriptionKey: @"Task error",
                           NSLocalizedFailureReasonErrorKey: formattedFailureReason,
                           };
    return errorWithCodeAndInfo(error, code, info);
}

static inline BOOL errorWithCodePOSIX(NSError **error, NSInteger code, NSString *failureReasonFormat, ...)
{
    if (!error) return NO;
    va_list args;
    va_start(args, failureReasonFormat);

    NSString *formattedFailureReason = [[NSString alloc] initWithFormat:failureReasonFormat arguments:args];
    va_end(args);

    NSError *posixError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    NSDictionary *info = @{
                           NSLocalizedDescriptionKey: @"Task error",
                           NSLocalizedFailureReasonErrorKey: formattedFailureReason,
                           NSUnderlyingErrorKey: posixError,
                           };

    return errorWithCodeAndInfo(error, code, info);
}


NSString *const ESTaskErrorDomain = @"ESTaskErrorDomain";

@interface ESTask () {
    BOOL _hasSpawned;
    pid_t _pid;
    int _waitStatus;
    dispatch_queue_t _taskQueue;
    dispatch_source_t _taskSource;
    dispatch_semaphore_t _taskWait;
}

@property (readwrite, getter=isRunning) BOOL running;

@end

@implementation ESTask

- (instancetype)init
{
    self = [super init];
    if (!self) return nil;

    _pid = 0;

    char *label;
    int err = asprintf(&label, "ESTask queue %p", (__bridge void *)self);
    if (err == 0) {
        return nil;
    }

    _taskQueue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);

    _taskWait = dispatch_semaphore_create(0);

    return self;
}

- (BOOL)launch:(NSError **)error
{
    NSAssert(_hasSpawned != YES, @"Task already launched");

    int err;
    BOOL isDir = NO;

    // Build launch path and check that it is executable
    NSString *launchPath = [self.launchPath stringByStandardizingPath];
    if (!launchPath || ![[NSFileManager defaultManager] fileExistsAtPath:launchPath isDirectory:&isDir] || isDir) {
        return errorWithCode(error, ESTaskErrorInvalidLaunchPath, @"Launch path \"%@\" is invalid.", self.launchPath);
    }
    const char *launchDir = [launchPath fileSystemRepresentation];

    err = access(launchDir, X_OK);
    if (err != 0) {
        return errorWithCodePOSIX(error, ESTaskErrorInvalidLaunchPath, @"Launch path \"%@\" inaccessible.");
    }

    // Check our working directory
    NSString *currentDirectoryPath = [self.currentDirectoryPath stringByStandardizingPath];
    if (currentDirectoryPath && (![[NSFileManager defaultManager] fileExistsAtPath:currentDirectoryPath isDirectory:&isDir] || !isDir)) {
        return errorWithCode(error, ESTaskErrorInvalidWorkingDirectory, @"Working directory \"%@\" invalid.", self.currentDirectoryPath);
    }
    const char *cwd = [currentDirectoryPath fileSystemRepresentation];

    // Build our argument list
    if (self.arguments.count >= ARG_MAX) {
        return errorWithCode(error, ESTaskErrorTooManyArguments, @"Too many arguments (%ld).", self.arguments.count);
    }
    // We need pointers for each arg plus our launch path plus the ending NULL
    char **argv = alloca(self.arguments.count * sizeof(void *) + 1 + 1);
    argv[0] = (char *)launchDir;
    NSInteger idx = 1;
    if (self.arguments.count > 0) {
        for (idx = 1; idx < self.arguments.count + 1; idx++) {
            argv[idx] = (char *)self.arguments[idx - 1].fileSystemRepresentation;
        }
    }
    argv[idx] = NULL;

    // Setup environment
    char **envp = NULL;
    if (self.environment.count > 0) {
        envp = calloc(self.environment.count, sizeof(void *));
        NSUInteger env_id = 0;
        for (NSString *key in self.environment) {
            NSString *value = self.environment[key];
            envp[env_id++] = (char *)[[NSString stringWithFormat:@"%@=%@", key, value] fileSystemRepresentation];
        }
    } else {
        envp = *_NSGetEnviron();
    }

    // Setup file descriptors
    posix_spawn_file_actions_t file_actions;
    posix_spawn_file_actions_init(&file_actions);

    int fds[3];
    int fd_id = 0;
    NSFileHandle *handle = nil;
    handle = self.standardInput;
    if (handle) {
        if ([handle respondsToSelector:@selector(fileHandleForReading)]) {
            handle = [(NSPipe *)handle fileHandleForReading];
        }
        if (![handle respondsToSelector:@selector(fileDescriptor)]) {
            [NSException raise:NSInvalidArgumentException format:@"Invalid object passed for standardInput"];
        }
        fds[fd_id] = [handle fileDescriptor];
    } else {
        fds[fd_id] = -1;
    }
    fd_id++;
    handle = self.standardOutput;
    if (handle) {
        if ([handle respondsToSelector:@selector(fileHandleForWriting)]) {
            handle = [(NSPipe *)handle fileHandleForWriting];
        }
        if (![handle respondsToSelector:@selector(fileDescriptor)]) {
            [NSException raise:NSInvalidArgumentException format:@"Invalid object passed for standardOutput"];
        }
        fds[fd_id] = [handle fileDescriptor];
    } else {
        fds[fd_id] = -1;
    }
    fd_id++;
    handle = self.standardError;
    if (handle) {
        if ([handle respondsToSelector:@selector(fileHandleForWriting)]) {
            handle = [(NSPipe *)handle fileHandleForWriting];
        }
        if (![handle respondsToSelector:@selector(fileDescriptor)]) {
            [NSException raise:NSInvalidArgumentException format:@"Invalid object passed for standardError"];
        }
        fds[fd_id] = [handle fileDescriptor];
    } else {
        fds[fd_id] = -1;
    }

    int fd_idx = 0;
    int null_fd = open("/dev/null", O_RDWR);
    for (fd_idx = 0; fd_idx <= 2; fd_idx++) {
        if (fds[fd_idx] == -1) {
            fds[fd_idx] = null_fd;
        }

        fds[fd_idx] = dup(fds[fd_idx]);

        // XXX: maybe use actions_addclose for the other end of pipes ?
        err = posix_spawn_file_actions_adddup2(&file_actions, fds[fd_idx], fd_idx);
        if (err != 0) {
            break;
        }
    }
    if (err != 0) {
        // Close dup()-ed fds
        int tmperrno = errno;
        for (int tmp = 0; tmp <= fd_idx; tmp++) {
            close(fds[tmp]); fds[tmp] = -1;
        }
        close(null_fd); null_fd = -1;
        errno = tmperrno;
        return errorWithCodePOSIX(error, ESTaskErrorFileActionFailure, @"Failed to set up file descriptors.");
    }
    // Only close our /dev/null placeholder, the rest will be done after spawn is complete
    close(null_fd); null_fd = -1;

    // Setup attributes
    posix_spawnattr_t spawn_attr;
    posix_spawnattr_init(&spawn_attr);

    // Reset our spawned task signal handlers
    sigset_t sigset_empty;
    sigemptyset(&sigset_empty);
    posix_spawnattr_setsigmask(&spawn_attr, &sigset_empty);

    sigset_t sigset_all;
    sigfillset(&sigset_all);
    posix_spawnattr_setsigdefault(&spawn_attr, &sigset_all);

    // Set the flags so that signals aren't masked, handlers are set to default, and every file descriptor we didn't explicitly set are closed
    posix_spawnattr_setflags(&spawn_attr, POSIX_SPAWN_SETSIGMASK|POSIX_SPAWN_SETSIGDEF|POSIX_SPAWN_CLOEXEC_DEFAULT);

    // Setup working directory
    int old_cwd_fd = -1;
    if (cwd != NULL) {
        // Grab our current WD
        old_cwd_fd = open(".", O_RDONLY);
        if (old_cwd_fd == -1 || chdir(cwd) != 0) {
            return errorWithCodePOSIX(error, ESTaskErrorChangeDirectoryFailed, @"Failed to change working directory.");
        }
    }

    // Spawn our task !
    err = posix_spawn(&_pid, launchDir, &file_actions, &spawn_attr, argv, envp);
    int tmperrno = errno;
    // Whether we succeeded or not, close the dup()-ed file descriptors
    for (int idx = 0; idx < 3; idx++) {
        close(fds[idx]); fds[idx] = -1;
    }
    // Reset the working directory
    if (cwd != NULL && fchdir(old_cwd_fd) == 0) {
        close(old_cwd_fd); old_cwd_fd = -1;
    }
    if (err != 0) {
        errno = tmperrno;
        return errorWithCodePOSIX(error, ESTaskErrorSpawnFailed, @"Failed to spawn task.");
    }

    _hasSpawned = YES;

    // Close the end of pipes we don't need anymore
    if (self.standardInput && [self.standardInput respondsToSelector:@selector(fileHandleForReading)]) {
        [[self.standardInput fileHandleForReading] closeFile];
    }
    if (self.standardOutput && [self.standardOutput respondsToSelector:@selector(fileHandleForWriting)]) {
        [[self.standardOutput fileHandleForWriting] closeFile];
    }
    if (self.standardError && [self.standardError respondsToSelector:@selector(fileHandleForWriting)]) {
        [[self.standardError fileHandleForWriting] closeFile];
    }

    // Setup a dispatch source for our new process exit events
    _taskSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, _pid, DISPATCH_PROC_EXIT, _taskQueue);
    dispatch_source_set_event_handler(_taskSource, ^{
        dispatch_source_cancel(_taskSource);

        int err = 0;
        do {
            err = waitpid(_pid, &_waitStatus, 0);
        } while (err != 0 && errno == EINTR);
        NSAssert(err == _pid, @"waitpid returned an unexpected value: %d", err);

        // XXX: KVO ?
        self.running = NO;

        if (!self.terminationHandler) {
            // Easy case, just signal the semaphore in case someone is -waitUntilExit on us

            dispatch_semaphore_signal(_taskWait);
        } else {
            // Run the termination handler on another queue
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                self.terminationHandler(self);

                dispatch_async(_taskQueue, ^{
                    // Clear the handler
                    self.terminationHandler = nil;

                    // And signal clients that might wait
                    dispatch_semaphore_signal(_taskWait);
                });
            });
        }

    });
    dispatch_resume(_taskSource);

    posix_spawnattr_destroy(&spawn_attr);
    posix_spawn_file_actions_destroy(&file_actions);

    return YES;
}

- (void)launch {
    [self launch:NULL];
}

- (BOOL)sendSignal:(int)signal
{
    int err = kill(_pid, signal);
    return (err == 0);
}

- (void)interrupt
{
    [self sendSignal:SIGINT];
}

- (void)terminate
{
    [self sendSignal:SIGTERM];
}

- (BOOL)suspend
{
    BOOL success = [self sendSignal:SIGSTOP];
    if (!success) return NO;
    _suspendCount++;
    return YES;
}

- (BOOL)resume
{
    BOOL success = [self sendSignal:SIGCONT];
    if (!success) return NO;
    _suspendCount--;
    return YES;
}

- (int)processIdentifier
{
    return _pid;
}

- (int)terminationStatus {
    return WEXITSTATUS(_waitStatus);
}

- (NSTaskTerminationReason)terminationReason {
    if (WIFSIGNALED(_waitStatus)) {
        return NSTaskTerminationReasonUncaughtSignal;
    } else if (WIFEXITED(_waitStatus)) {
        return NSTaskTerminationReasonExit;
    }
    return 0;
}

@end



@implementation ESTask (ESTaskConveniences)

+ (BOOL)executeTask:(NSString *)command arguments:(NSArray *)arguments inDirectory:(NSString *)directory error:(NSError **)error terminationHandler:(void (^)(ESTask *task))terminationHandler
{
    ESTask *task = [self taskWithCommand:command arguments:arguments inDirectory:directory];
    NSAssert(task != nil, @"task shouldn't be nil");

    return [task launch:error terminationHandler:^(ESTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            terminationHandler(task);
        });
    }];
}

+ (BOOL)executeTask:(NSString *)command arguments:(NSArray *)arguments inDirectory:(NSString *)directory error:(NSError **)error completionHandler:(void (^)(ESTask *task, NSData *readData))completionHandler
{
    ESTask *task = [self taskWithCommand:command arguments:arguments inDirectory:directory];
    NSAssert(task != nil, @"task shouldn't be nil");

    return [task launch:error completionHandler:completionHandler];
}

+ (instancetype)taskWithCommand:(NSString *)command arguments:(NSArray *)arguments inDirectory:(NSString *)directory
{
    ESTask *task = [[self alloc] init];
    [task setLaunchPath:command];
    [task setArguments:arguments];

    if (directory)
        [task setCurrentDirectoryPath:directory];

    return task;
}

+ (ESTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    ESTask *task = [[ESTask alloc] init];
    task.launchPath = path;
    task.arguments = arguments;

    BOOL success = [task launch:NULL];

    return (success ? task : nil);
}

- (BOOL)launch:(NSError **)error completionHandler:(void (^)(ESTask *task, NSData *readData))completionHandler
{
    NSPipe *pipe = [NSPipe pipe];
    [self setStandardOutput:pipe];
    [self setStandardError:pipe];

    return [self launch:error terminationHandler:^(ESTask *task) {
        NSData *data = [[task.standardOutput fileHandleForReading] readDataToEndOfFile];

        completionHandler(task, data);
    }];
}

- (BOOL)launch:(NSError **)error terminationHandler:(void (^)(ESTask *task))terminationHandler
{
    self.terminationHandler = terminationHandler;

    return [self launch:error];
}

- (void)waitUntilExit {
    if (!_hasSpawned) {
        [NSException raise:NSInternalInconsistencyException format:@"-waitUntilExit called while task isn't launched"];
    }

    dispatch_semaphore_wait(_taskWait, DISPATCH_TIME_FOREVER);
}

@end
