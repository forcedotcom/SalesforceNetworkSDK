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
#import "SFOAuthCoordinator.h"
@interface SFNetworkEngine () <SFOAuthCoordinatorDelegate>

@property (nonatomic, strong) MKNetworkEngine *internalNetworkEngine;

/** Queue to store all operations queued up due to expired access token
 
 This queue will contain all operations that failed due to expired token and all incoming pending operations that requires access token
 */
@property NSMutableArray *operationsWaitingForAccessToken;


/** Flag to indicate whether or not `SFNetworkEngine` token refresh flow is in progress or not
 */
@property (nonatomic, assign, readonly, getter = isAccessTokenBeingRefreshed) BOOL accessTokenBeingRefreshed;

/** Flag to indicate whether network status change should trigger access token refresh 
 */
@property (nonatomic, assign) BOOL networkChangeShouldTriggerTokenRefresh;

/** Store previous delegate of `coordinator`.
 
 `SFNetworkEngine` will set itself as `coordinator` delegate during `refreshAccessToken`. This property is used to remember and restore `coordinator` after refresh token is finished
 */
@property (nonatomic, assign) id<SFOAuthCoordinatorDelegate> previousOAuthDelegate;


/** Start refresh access token flow
*/
- (void)startRefreshAccessTokenFlow;

/** Access token refresh flow stop
 
 @param willAutoRetryRefreshFlow YES if `SFNetworkEngine` will auto-retry access token refresh flow
 */
- (void)refreshAccessTokenFlowStopped:(BOOL)willAutoRetryRefreshFlow;

/**Method to be invoked when access token is refreshed
 
 Upon calling of this method, `SFNetworkEngine` will retrieve the updated access token from the `coordinator` property and replay all requests that are queued up due to access token expiration
 
 @param coordinator `​SFOAuth​Coordinator` return by OAuth flow when access token is refreshed
 */
- (void)accessTokenRefreshed:(SFOAuthCoordinator *)coordinator;

/** Queue `SFNetworkOperation` due to expired access token 
 */
- (void)queueOperationOnExpiredAccessToken:(SFNetworkOperation *)operation;

/** Replay all operations stored in `operationsWaitingForAccessToken` queue
 */
- (void)replayOperationsWaitingForAccessToken;

/** Fatal OAuth error happened. Call error block of all operations stored in `operationsWaitingForAccessToken` queue 
 */
- (void)failOperationsWaitingForAccessTokenWithError:(NSError *)error;

/** Restore the original OAuth delegate after access token fresh flow stopped 
 
 See `previousOAuthDelegate` for more details
 */
- (void)restoreOAuthDelegate;

/**Clone an operation. Used to re-queue a failed operation
 
@param operation Existing `SFNetworkOperation` to clone from
 */
- (SFNetworkOperation *)cloneOperation:(SFNetworkOperation *)operation;
@end
