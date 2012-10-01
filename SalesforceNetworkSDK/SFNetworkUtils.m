//
//  SFNetworkUtils.m
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/25/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import "SFNetworkUtils.h"
#import "SalesforceCommonUtils.h"
#import "SFOAuthCoordinator.h"


@implementation SFNetworkUtils

+ (BOOL)isNetworkError:(NSError *)error {
    switch (error.code) {
        case kCFURLErrorNotConnectedToInternet:
        case kCFURLErrorCannotFindHost:
        case kCFURLErrorCannotConnectToHost:
        case kCFURLErrorNetworkConnectionLost:
        case kCFURLErrorDNSLookupFailed:
        case kCFURLErrorResourceUnavailable:
        case kCFURLErrorTimedOut:
            return YES;
            break;
        default:
            return NO;
    }
}

+ (BOOL)isOAuthError:(NSError *)error {
    switch (error.code) {
        case kSFOAuthErrorAccessDenied:
        case kSFOAuthErrorInvalidClientId:
        case kSFOAuthErrorInvalidGrant:
        case kSFOAuthErrorInactiveUser:
        case kSFOAuthErrorInactiveOrg:
            return YES;
            break;
        default:
            return NO;
    }
}

+ (BOOL)isSessionTimeOutError:(NSError *)error {
    if (error.code == 401) {
        return YES;
    } else {
        return NO;
    }
}

+ (NSString *)displayMessageForError:(NSError *)error {
    NSString *errorMessage = nil;
    if (error == nil) {
        errorMessage = nil;
    }
    else {
        if ([[self class] isNetworkError:error]){
            errorMessage = NSLocalizedString(@"NETWORK_CONNECTION_ERROR", @"connection error");
        } else if ([[self class] isSessionTimeOutError:error]) {
            errorMessage = NSLocalizedString(@"SESSION_TIME_OUT", @"session timeout error");
        }
        else if (error.code == 403) {
            errorMessage = NSLocalizedString(@"ACCESS_FORBIDDEN", @"access not allowed error");
        }
        else if (error.code == 404) {
            errorMessage = NSLocalizedString(@"URL_NO_LONGER_EXISTS", @"URL no longer exists error");
        }
        else if (error.code == 500) {
            errorMessage = NSLocalizedString(@"INTERNAL_SERVER_ERROR", @"internal server error");
        }
        else if (error.code == 503) {
            errorMessage = NSLocalizedString(@"API_LIMIT_REACHED", @"API limit error");
        }
        else {
            errorMessage = [error localizedDescription];
        }
    }
    
    return errorMessage;
}
@end
