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

NSString * const kErrorCodeKeyInResponse = @"errorCode";
NSString * const kInvalidSessionID = @"INVALID_SESSION_ID";


@interface SFNetworkUtils ()
/** Return YES if error is related to network connectivity error
 
 @param error NSError object used to check whether the error is related to network connectivity error
 */
+ (BOOL)isNetworkError:(NSError *)error;

/** Return YES if error is related to OAuth error
 
 OAuth error should trigger a login progress again
 @param error NSError object used to check whether the error is related to OAuth error
 */
+ (BOOL)isOAuthError:(NSError *)error;

/** Return YES if error is related to session timeout
 
 Session timeout error should trigger access token refresh process
 @param error NSError object used to check whether the error is related to session timeout error
 */
+ (BOOL)isSessionTimeOutError:(NSError *)error;
@end

@implementation SFNetworkUtils

+ (BOOL)isNetworkError:(NSError *)error {
    if (nil == error) {
        return NO;
    }
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
    if (nil == error) {
        return NO;
    }
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
    if (nil == error) {
        return NO;
    }
    
    //Check for INVALID_SESSION
    id obj = [[error userInfo] objectForKey:kErrorCodeKeyInResponse];
    if(obj) {
        if (![obj rangeOfString:kInvalidSessionID].location == NSNotFound) {
            return YES;
        }
    }
    
    if (error.code == 401 || error.code == kCFURLErrorUserCancelledAuthentication) {
        return YES;
    } else {
        return NO;
    }
}

+ (SFNetworkOperationErrorType)typeOfError:(NSError *)error {
    if (error == nil) {
        return SFNetworkOperationErrorTypeUnknown;
    }
    if ([[self class] isNetworkError:error]){
        return SFNetworkOperationErrorTypeNetworkError;
    }
    if ([[self class] isOAuthError:error]) {
        return SFNetworkOperationErrorTypeOAuthError;
    }

    if ([[self class] isSessionTimeOutError:error]) {
        return SFNetworkOperationErrorTypeSessionTimeOut;
    }

    if (error.code == 400) {
        return SFNetworkOperationErrorTypeInvalidRequest;
    }
    if (error.code == 403) {
        return SFNetworkOperationErrorTypeAccessDenied;
    }

    if (error.code == 404) {
       return SFNetworkOperationErrorTypeURLNoLongerExists;
    }
    if (error.code == 500) {
       return SFNetworkOperationErrorTypeInternalServerError;
    }
    if (error.code == 503) {
        return SFNetworkOperationErrorTypeAPILimitReached;
    }
    return SFNetworkOperationErrorTypeUnknown;
}

@end
