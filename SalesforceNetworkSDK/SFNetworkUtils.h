//
//  SFNetworkUtils.h
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/25/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import <Foundation/Foundation.h>

//Declare various error type
typedef enum {
    SFNetworkOperationErrorTypeNetworkError = 0, //network connectivity error
    SFNetworkOperationErrorTypeSessionTimeOut,
    SFNetworkOperationErrorTypeOAuthError,
    SFNetworkOperationErrorTypeAccessDenied,
    SFNetworkOperationErrorTypeAPILimitReached,
    SFNetworkOperationErrorTypeURLNoLongerExists,
    SFNetworkOperationErrorTypeInternalServerError,
    SFNetworkOperationErrorTypeUnknown
} SFNetworkOperationErrorType;

/** Helper class for SFNetworkSDK 
 
 This class provides
 - Utility methods to detect error type
 - Identify proper display message for various errors
 */
@interface SFNetworkUtils : NSObject

/** Get error type for the specified error
 
 @param error NSError object to get error type for
 */
+ (SFNetworkOperationErrorType)typeOfError:(NSError *)error;
@end
