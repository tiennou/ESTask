//
//  ESTask_Errors.h
//  ESTask
//
//  Created by Etienne on 16/02/2016.
//  Copyright © 2016 Etienne Samson. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const ESTaskErrorDomain;

typedef NS_ENUM(NSUInteger, ESTaskErrorCode) {
    ESTaskErrorSpawnFailed = 1,
    ESTaskErrorInvalidLaunchPath = 2,
    ESTaskErrorInvalidWorkingDirectory = 3,
    ESTaskErrorTooManyArguments = 4,
    ESTaskErrorFileActionFailure,
    ESTaskErrorChangeDirectoryFailed,
};
