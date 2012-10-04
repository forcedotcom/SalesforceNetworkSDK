//
//  SFNetworkOperation+Internal.h
//  SalesforceNetworkSDK
//
//  Created by Qingqing Liu on 9/27/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MKNetworkKit.h"

@interface SFNetworkOperation ()

/** Internal `MKNetworkOperation` object used to perform the actual network call
 */
@property (nonatomic, strong) MKNetworkOperation *internalOperation;

/** Custom post data encoding content type
 
 See `setCustomPostDataEncodingHandler:postDataEncodingHandler:forType` for more details
 */
@property (nonatomic, readonly, copy) NSString *customPostDataEncodingContentType;

/**Create new SFNetworkOperation
 
@param operation MKNetworkOperation object. Class for handling the low level network calls
@param url URL string used to created the operation
@param method HTTP method
@param useSSL YES to use SSL
 */
- (id)initWithOperation:(MKNetworkOperation *)operation url:(NSString *)url method:(NSString *)method ssl:(BOOL)useSSL;

/** Invoke delegate's operationDidFinish callback 
 */
- (void)callDelegateDidFinish:(MKNetworkOperation *)operation;

/** Invoke delegate's operationDidFailWithError callback
 */
- (void)callDelegateDidFailWithError:(NSError *)error;

/** Check for errorCode returned in JSON response from server
 
 In case of failed API call, serve sometimes would return an JSON array with one single JSON object to represent the error. This JSON error object has an "errorCode" property to outline the reason of failed call. 
 
 To handle this use case, this method will check to see if operation conains a JSON response, if yes, whether it matches the pattern described above. If an error code is detected, it will create an NSError object with `[NSError userInfo]` set to the error JSON object returned from server 
 */
- (NSError *)checkForErrorInResponse:(MKNetworkOperation *)operation;
@end

