//
//  SFNetworkEngine.h
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/24/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Reachability.h"
#import "SFOAuthCoordinator.h"
#import "SFNetworkOperation.h"


extern NSString *SFNetworkOperationGetMethod;
extern NSString *SFNetworkOperationPostMethod;
extern NSString *SFNetworkOperationPutMethod;
extern NSString *SFNetworkOperationDeleteMethod;
extern NSString *SFNetworkOperationPostMethod;

extern NSString *SFNetworkOperationReachabilityChangedNotification;

/**
 Main class used to manage and send `SFNetworkOperation`
 
 Caller of SFNetworkEngine should call `sharedInstance` to initalize the SFNetworkEngine when OAuth is completed successfully and set `coorindator`.
*/
@interface SFNetworkEngine : NSObject 

/** `SFNetworkEngine` relies `SFOAuthCoordinator` to interact with oAuth flow and extrat instanceUrl, accessToken
 */
@property (nonatomic, strong) SFOAuthCoordinator *coordinator;

/** Custom HTTP headers that will be set for all `SFNetworkOperation` before executing
 
 `SFNetworkEngine` will automatically set the following headers if customHeaders is nil or do not contain the specific header key
 - Authorization header with `[[SFOAuthCoordinator credentials] accessToken]`
 - User-Agent header with application name, version and OS information
 */
@property (nonatomic, strong) NSDictionary *customHeaders;

/**Handler that you implement to monitor reachability changes
 
 if `reachabilityChangedHandler` is not set, a `SFNetworkOperationReachabilityChangedNotification` notification will be posted when reachability changed with `NetworkStatus` as the `[notification object]`
 */
@property (nonatomic, copy) void (^reachabilityChangedHandler)(NetworkStatus ns);


/**Set to true to suspsend all pending requests when app enters background. Default is YES*/
@property (nonatomic, assign) BOOL suspendRequestsWhenAppEntersBackground;

/**
 * Returns the singleton instance of `SFNetworkEngine`
 * After a successful oauth login with an SFOAuthCoordinator, you
 * should set it as the coordinator property of this instance.
 */
+ (SFNetworkEngine *)sharedInstance;

/** Returns a `SFNetworkOperation` that can be used to execute the specified remote call
 *
 * @param url Url to the remote service to invoke. This url does not start with HTTP protocol (http or https), `[[SFOAuthCoordinator credentials] instanceUrl]` will be automatically added to the url that will be executed
 * @param params Key & value pair as request parameters
 * @param method the http method to use. Valid value include GET, POST, DELETE, PUT and PATCH
 * @param useSSL Set to YES to use SSL connection
 * @return the `SFNetworkOperation` object that can be executed by calling `enqueueOperation    method
 */
- (SFNetworkOperation *)operationWithUrl:(NSString *)url params:(NSMutableDictionary *)params httpMethod:(NSString *)method ssl:(BOOL)useSSL;

/** Returns a `SFNetworkOperation` that can be used to execute the specified remote request.
 SSL will be used to execute to execute this operation
 *
 * @param url Url to the remote service to invoke. If url does not start with a valid protocol (http or https), it will be treated as relative URL and `[[SFOAuthCoordinator credentials] instanceUrl]` will be automatically added to the url
 * @param params Key & value pair as request parameters
 * @param method the http method to use. Valid value include GET, POST, DELETE, PUT and PATCH
 * @return the `SFNetworkOperation` object that can be executed by calling `enqueueOperation    method
 */
- (SFNetworkOperation *)operationWithUrl:(NSString *)url params:(NSMutableDictionary *)params httpMethod:(NSString *)method;


/**Enqueues `SFNetworkOperation` for execution
 
 Enqueued operation will be executed by `SFNetworkEngine` based on it's priority and dependencies if there is any
 @param operation `SFNetworkOperation` object to be enqueued and executed by `SFNetworkEngine`
 */
-(void)enqueueOperation:(SFNetworkOperation*)operation;


/** Returns YES if `[[SFOAuthCoordinator credentials] instanceUrl]` is reachable
 *	If `coordinator` is not set before this method is called, it will return NO
 */
- (BOOL)isReachable;

/** Cancel all operations that are waiting to be excecuted
 */
- (void)cancellAllOperations;

/**Suspend all operations that are waiting to be excecuted
 */
- (void)supspendAllOperations;

/**Resume all operations that are suspended
 */
- (void)resumeAllOperations;

/**Returns YES of there are pending requests matching the specified operation tag
 */
- (BOOL)hasPendingOperationsWithTag:(NSString *)operationTag;

/**Returns `SFNetworkOperation` for the specified condition
 
 * @param url Url to the remote service to invoke. This url does not start with HTTP protocol (http or https), `[[SFOAuthCoordinator credentials] instanceUrl]` will be automatically added to the url that will be executed
 * @param params Key & value pair as request parameters
 * @param method the http method to use. Valid value include GET, POST, DELETE, PUT and PATCH
 * @return SFNetworkOperation` object if there is a pending or running operation matching the specified url, parameters and HTTP method. If no matching operation object is found in the queue, it will return nil
 */
- (SFNetworkOperation *)activeOperationWithUrl:(NSString *)url params:(NSMutableDictionary *)params httpMethod:(NSString *)method;
@end
