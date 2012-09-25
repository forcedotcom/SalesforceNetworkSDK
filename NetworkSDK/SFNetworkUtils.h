//
//  SFNetworkUtils.h
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/25/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SFNetworkUtils : NSObject

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

/**Helper method to translate NSError to the localized string key to use to display the error
 
 It will return nil, if NSError does not have one of the listed status code
 
 session time out error - Returns "SESSION_TIME_OUT"
 400 status code - Returns "INVALID_REQUEST_FORMAT"
 403 status code - Returns "ACCESS_FORBIDDEN"
 404 status code - Returns "URL_NO_LONGER_EXISTS"
 500 status code - Returns "INTERNAL_SERVER_ERROR"
 503 status code - Returns "API_LIMIT_REACHED"
 
 @param error NSError object used to translate the error message to user friendly error mesasge
 */
+ (NSString *)displayMessageForError:(NSError *)error;
@end
