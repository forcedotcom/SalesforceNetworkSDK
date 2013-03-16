//
//  SFNetworkEngine+Internal.h
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/24/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SFNetworkOperation.h"
#import "SFNetworkEngine.h"

@interface SFNetworkEngine ()

@property (nonatomic, strong) MKNetworkEngine *internalNetworkEngine;

/** Queue to store all operations queued up due to expired access token
 
 This queue will contain all operations that failed due to expired token and all incoming pending operations that requires access token
 */
@property NSMutableArray *operationsWaitingForAccessToken;


/** Queue to store all operations queued up due to network error
 
 This queue will contain all operations that failed due to network error, has greater than 0 `[SFNetworkOperation maximumNumOfRetriesForNetworkError]` value and `[SFNetworkOperation numOfRetriesForNetworkError]` is less than `[SFNetworkOperation maximumNumOfRetriesForNetworkError]
 */
@property NSMutableArray *operationsWaitingForNetwork;


/** Flag to indicate whether or not `SFNetworkEngine` token refresh flow is in progress or not
 */
@property (nonatomic, assign, readonly, getter = isAccessTokenBeingRefreshed) BOOL accessTokenBeingRefreshed;

/** Flag to indicate whether network status change should trigger access token refresh 
 */
@property (nonatomic, assign) BOOL networkChangeShouldTriggerTokenRefresh;


/** Read and return data from local test file
 
 See `supportLocalTestData` for more details
 
 @param localDataFilePath Path to the local test data file. Full path must be provided
 */
- (NSData *)readDataFromTestFile:(NSString *)localDataFilePath;

///---------------------------------------------------------------
/// @name Access Token Refresh Method
///---------------------------------------------------------------
/** Start refresh access token flow
*/
- (void)startRefreshAccessTokenFlow;

///---------------------------------------------------------------
/// @name Queue & Replay Operation Methods
///---------------------------------------------------------------
/** Queue `SFNetworkOperation` due to expired access token 
 */
- (void)queueOperationOnExpiredAccessToken:(SFNetworkOperation *)operation;

/** Fatal OAuth error happened. Call error block of all operations stored in `operationsWaitingForAccessToken` queue
 */
- (void)failOperationsWaitingForAccessTokenWithError:(NSError *)error;

/** Queue `SFNetworkOperation` due to network error
 */
- (void)queueOperationOnNetworkError:(SFNetworkOperation *)operation;

/** Replay all operations stored in `operationsWaitingForNetwork` queue
 */
- (void)replayOperationsWaitingForNetwork;

/**Clone an operation. Used to re-queue a failed operation
 
@param operation Existing `SFNetworkOperation` to clone from
 */
- (SFNetworkOperation *)cloneOperation:(SFNetworkOperation *)operation;
@end
