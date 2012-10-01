//
//  SFNetworkEngine.m
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/24/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import "SFNetworkEngine.h"
#import "MKNetworkKit.h"
#import "SalesforceCommonUtils.h"
#import "SFNetworkOperation.h"
#import "SFNetworkOperation+Internal.h"
#import "SFNetworkEngine+Internal.h"
#import "SFNetworkUtils.h"

#pragma mark - Operation Method
NSString *SFNetworkOperationGetMethod = @"GET";
NSString *SFNetworkOperationPostMethod = @"POST";
NSString *SFNetworkOperationPutMethod = @"PUT";
NSString *SFNetworkOperationDeleteMethod = @"DELETE";
NSString *SFNetworkOperationPatchMethod = @"PATCH";

#pragma mark - Notification Name
NSString *SFNetworkOperationReachabilityChangedNotification = @"SFNetworkOperationReachabilityChangedNotification";
NSString *SFNetworkOperationEngineOperationCancelledNotification = @"SFNetworkOperationEngineOperationCancelledNotification";
NSString *SFNetworkOperationEngineSuspendedNotification = @"SFNetworkOperationEngineSuspendedNotification";
NSString *SFNetworkOperationEngineResumedNotification = @"SFNetworkOperationEngineResumedNotification";

static const NSInteger kDefaultTimeOut = 3 * 60; //3 minutes
static const NSInteger kOAuthErrorCode = 999;
static const NSTimeInterval kDefaultRetryDelay = 30; //30 seconds

@interface SFNetworkEngine  ()
@property (nonatomic, strong) MKNetworkEngine *internalNetworkEngine;
- (BOOL)needToRecreateNetworkEngine:(SFOAuthCoordinator *)coordinator;
- (NSDictionary *)defaultCustomHeaders;
- (void)reachabilityChanged:(NetworkStatus)ns;
@end

@implementation SFNetworkEngine
@synthesize coordinator = _coordinator;
@synthesize customHeaders = _customHeaders;
@synthesize reachabilityChangedHandler = _reachabilityChangedHandler;
@synthesize operationTimeout = _operationTimeout;
@synthesize suspendRequestsWhenAppEntersBackground = _suspendRequestsWhenAppEntersBackground;
@synthesize internalNetworkEngine = _internalNetworkEngine;
@synthesize operationsWaitingForAccessToken = _operationsWaitingForAccessToken;
@synthesize accessTokenBeingRefreshed = _accessTokenBeingRefreshed;
@synthesize previousOAuthDelegate = _previousOAuthDelegate;
@synthesize networkChangeShouldTriggerTokenRefresh = _networkChangeShouldTriggerTokenRefresh;
@synthesize enableHttpPipeling = _enableHttpPipeling;

#pragma mark - Initialization
- (id)init {
    self = [super init];
    if (self) {
        //Set default value
        _operationTimeout = kDefaultTimeOut;
        _suspendRequestsWhenAppEntersBackground = YES;
        _enableHttpPipeling = YES;
        
        _operationsWaitingForAccessToken = [[NSMutableArray alloc] init];
        
        //Monitor application enters and exist background
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appEnteredBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (SFNetworkEngine *)sharedInstance {
    static dispatch_once_t pred;
    static SFNetworkEngine *networkEngine = nil;
	
    dispatch_once(&pred, ^{
		networkEngine = [[self alloc] init];
	});
    return networkEngine;
}

- (void)cleanup {
    @synchronized(self) {
        _accessTokenBeingRefreshed = NO;
        _networkChangeShouldTriggerTokenRefresh = NO;
        [self restoreOAuthDelegate];
        [self.operationsWaitingForAccessToken removeAllObjects];
        [self.internalNetworkEngine cancellAllOperations];
    }
}

#pragma mark - Property Override
- (void)setCoordinator:(SFOAuthCoordinator *)coordinator {
    if (_internalNetworkEngine) {
        //network engine created before
        if ([self needToRecreateNetworkEngine:coordinator]) {
            [self cleanup];
        }
        _internalNetworkEngine = nil;
    }
    _coordinator = coordinator;
    if (!_internalNetworkEngine) {
        //If network engine is not created, create it
        [self internalNetworkEngine];
    }
}

- (void)setCustomHeaders:(NSDictionary *)customHeaders {
    _customHeaders = customHeaders;
    if (_internalNetworkEngine) {
        [_internalNetworkEngine updateCustomHeaders:_customHeaders];
    }
}

- (NSDictionary *)customHeaders {
    if (_customHeaders) {
        return _customHeaders;
    }
    else {
        return [self defaultCustomHeaders];
    }
}

- (MKNetworkEngine *)internalNetworkEngine {
    if (!_internalNetworkEngine) {
        //Assert the condition that has to be met
        NSAssert(_coordinator != nil, @"SFOAuthCoordinator must be set first before invoke any network call.");
        
        SFOAuthCredentials *credentials = _coordinator.credentials;
        NSString *currentHostName = [credentials.instanceUrl host];
        
        
        _internalNetworkEngine = [[MKNetworkEngine alloc] initWithHostName:currentHostName customHeaderFields:[self customHeaders]];
        
        __weak SFNetworkEngine *weakSelf = self;
        _internalNetworkEngine.reachabilityChangedHandler =  ^ (NetworkStatus ns) {
            [weakSelf reachabilityChanged:ns];
        };

    }
    return _internalNetworkEngine;
}

#pragma mark - Http Header Method
- (void)setHeaderValue:(NSString *)value forKey:(NSString *)key {
    if (nil == key) {
        return;
    }
    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionaryWithDictionary:[self customHeaders]];
    if (nil == value) {
        //remove
        [mutableHeaders removeObjectForKey:key];
    } else {
        [mutableHeaders setValue:value forKey:key];
    }
    _customHeaders = mutableHeaders;
    if (_internalNetworkEngine) {
        [_internalNetworkEngine updateCustomHeaders:_customHeaders];
    }
}

#pragma mark - Remote Request Methods 
- (SFNetworkOperation *)operationWithUrl:(NSString *)url params:(NSDictionary *)params httpMethod:(NSString *)method ssl:(BOOL)useSSL {
    MKNetworkEngine *engine = [self internalNetworkEngine];
    
    if ([NSString isEmpty:url]) {
        [self log:SFLogLevelError format:@"Remote request URL is nil for params %@", params];
        return nil;
    }
    NSString *lowerCaseUrl = [url lowercaseString];
    if (![lowerCaseUrl hasPrefix:@"http:"] && ![lowerCaseUrl hasPrefix:@"https:"]) {
        //relative URL, construct full URL
        //If API path is nil or URL already starts with API path, construct with instanceUrl only
        if ([NSString isEmpty:self.apiPath] || [lowerCaseUrl hasPrefix:[self.apiPath lowercaseString]]) {
            url = [NSString stringWithFormat:@"%@/%@", self.coordinator.credentials.instanceUrl, url];
        }
        else {
            url = [NSString stringWithFormat:@"%@/%@/%@", self.coordinator.credentials.instanceUrl, self.apiPath, url];
        }
    }
    MKNetworkOperation *internalOperation = [engine operationWithURLString:url params:[NSMutableDictionary dictionaryWithDictionary:params] httpMethod:method];
    internalOperation.enableHttpPipelining = self.enableHttpPipeling;
    
    SFNetworkOperation *operation = [[SFNetworkOperation alloc] initWithOperation:internalOperation];
    operation.operationTimeout = self.operationTimeout;
    operation.customHeaders = self.customHeaders;
    return operation;
}

- (SFNetworkOperation *)operationWithUrl:(NSString *)url params:(NSDictionary *)params httpMethod:(NSString *)method {
    return [self operationWithUrl:url params:params httpMethod:method ssl:YES];
}

- (SFNetworkOperation *)get:(NSString *)url params:(NSDictionary *)params {
    return [self operationWithUrl:url params:params httpMethod:SFNetworkOperationGetMethod ssl:YES];
}

- (SFNetworkOperation *)post:(NSString *)url params:(NSDictionary *)params {
    return [self operationWithUrl:url params:params httpMethod:SFNetworkOperationPostMethod ssl:YES];
}

- (SFNetworkOperation *)put:(NSString *)url params:(NSDictionary *)params {
    return [self operationWithUrl:url params:params httpMethod:SFNetworkOperationPutMethod ssl:YES];
}
- (SFNetworkOperation *)delete:(NSString *)url params:(NSDictionary *)params {
    return [self operationWithUrl:url params:params httpMethod:SFNetworkOperationDeleteMethod ssl:YES];
}

- (SFNetworkOperation *)patch:(NSString *)url params:(NSDictionary *)params {
    return [self operationWithUrl:url params:params httpMethod:SFNetworkOperationPatchMethod ssl:YES];
}

#pragma mark - Operations Methods
- (SFNetworkOperation *)activeOperationWithUrl:(NSString *)url params:(NSDictionary *)params httpMethod:(NSString *)method {
    if ([NSString isEmpty:url]) {
        return nil;
    }
    
    MKNetworkEngine *engine = [self internalNetworkEngine];
    
    NSArray *operations = [engine operations];
    if (operations == nil || operations.count == 0) {
        return nil;
    }
    MKNetworkOperation *checkForOperation = [engine operationWithPath:url params:[NSMutableDictionary dictionaryWithDictionary:params] httpMethod:method];
    MKNetworkOperation *operationFound = nil;
    for (MKNetworkOperation *operation in operations) {
        if ([operation uniqueIdentifier] == [checkForOperation uniqueIdentifier]) {
            operationFound = operation;
            break;
        }
    }
    if (operationFound) {
        SFNetworkOperation *operation = [[SFNetworkOperation alloc] init];
        operation.internalOperation = operationFound;
        return operation;
    }
    return nil;
}

- (void)enqueueOperation:(SFNetworkOperation*)operation {
    if (nil == operation || nil == operation.internalOperation) {
        return;
    }
    
    @synchronized(self) {
        if (self.isAccessTokenBeingRefreshed) {
            if (operation.requiresAccessToken) {
                [self.operationsWaitingForAccessToken addObject:operation];
                return;
            }
        }
    }
    
    MKNetworkEngine *engine = [self internalNetworkEngine];
    [engine enqueueOperation:operation.internalOperation];
}

- (void)cancelAllOperations {
    if (nil != _internalNetworkEngine) {
        [_internalNetworkEngine cancellAllOperations];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SFNetworkOperationEngineOperationCancelledNotification object:nil userInfo:nil];
}

- (void)suspendAllOperations {
    if (nil != _internalNetworkEngine) {
        [_internalNetworkEngine suspendAllOperations];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SFNetworkOperationEngineSuspendedNotification object:nil userInfo:nil];
}

- (void)resumeAllOperations {
    if (nil != _internalNetworkEngine) {
        [_internalNetworkEngine resumeAllOperations];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SFNetworkOperationEngineResumedNotification object:nil userInfo:nil];
}

- (BOOL)hasPendingOperationsWithTag:(NSString *)operationTag {
    if (nil == operationTag || nil == _internalNetworkEngine) {
       return NO;
    }
    NSArray *operations = [_internalNetworkEngine operations];
    for (MKNetworkOperation *operation in operations) {
        if ([operation.tag isEqualToString:operationTag]) {
            if (!operation.isFinished) {
                return YES;
            }
        }
    }
    return NO;
}

//Access Token Method
- (void)accessTokenRefreshed:(SFOAuthCoordinator *)coordinator {
    if (nil == coordinator) {
        return;
    }
    
    @synchronized(self) {
        self.coordinator = coordinator;
        
        //set OAuth token
        NSString *token = [NSString stringWithFormat:@"OAuth %@", _coordinator.credentials.accessToken];
        [self setHeaderValue:token forKey:@"Authorization"];
        
        if (self.isAccessTokenBeingRefreshed) {
            _accessTokenBeingRefreshed = NO;
            [self replayOperationsWaitingForAccessToken];
        }
    }
}

#pragma mark - Private Method
/** Return YES when coordinator has changed 
 
 If coordinator instance URL, user Id or orgId is changed, return YES to indicator that internal network engine needs to be re-created
 */
- (BOOL)needToRecreateNetworkEngine:(SFOAuthCoordinator *)coordinator {
    NSString *newHostName = nil, *newOrgId = nil, *newUserId = nil;
    NSString *currentHostName = nil, *currentOrgId = nil, *currentUserId = nil;
    SFOAuthCredentials *credentials = nil;
    
    if (coordinator) {
        credentials = coordinator.credentials;
        newHostName = [credentials.instanceUrl host];
        newOrgId = credentials.organizationId;
        newUserId = credentials.userId;
    }
    else {
        newHostName = @"";
        newOrgId = @"";
        newUserId = @"";
    }
    
    if (self.coordinator) {
        credentials = self.coordinator.credentials;
        currentHostName = [credentials.instanceUrl host];
        currentOrgId = credentials.organizationId;
        currentUserId = credentials.userId;
    }
    else {
        currentHostName = @"";
        currentOrgId = @"";
        currentUserId = @"";
    }
    BOOL needToRecreate = ![newHostName isEqualToString:currentHostName]
    ||![newOrgId isEqualToString:currentOrgId]
    ||![newUserId isEqualToString:currentUserId];
    
    return needToRecreate;
}

/** Return default custom headers to use for the internal network engine 
 
 If `customHeaders` property is to a not nil value, it will return `customHeaders`. If not, it will populate headers by default
 */
- (NSDictionary *)defaultCustomHeaders {
    if (_customHeaders) {
        return _customHeaders;
    }
    
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (_coordinator) {
        //set OAuth token
        NSString *token = [NSString stringWithFormat:@"OAuth %@", _coordinator.credentials.accessToken];
        [headers setValue:token forKey:@"Authorization"];
    }
    
    [headers setValue:@"gzip" forKey:@"Accept-Encoding"];
    
    //read user agent from user defaults, this value will be populated by mobileSDK if it is used
    NSString *userAgent = [[NSUserDefaults standardUserDefaults] valueForKey:@"UserAgent"];
    if (nil == userAgent) {
        //If not populated info.plist, generate the common user agent with includes app product name, version, OS version and device type
        userAgent = [NSString userAgentString];
    }
    if (nil != userAgent) {
        [headers setValue:userAgent forKey:@"User-Agent"];
    }
    return headers;
}

#pragma mark - Life Cycle Notification Methods
- (void)appEnteredBackground:(NSNotification *)notification {
    if (self.shouldSuspendRequestsWhenAppEntersBackground) {
        [self suspendAllOperations];
    }
}
- (void)appBecomeActive:(NSNotification *)notification {
    if (self.shouldSuspendRequestsWhenAppEntersBackground) {
        [self resumeAllOperations];
    }
}

#pragma mark - Reachability Methods
- (void)reachabilityChanged:(NetworkStatus)ns {
    [[NSNotificationCenter defaultCenter] postNotificationName:SFNetworkOperationReachabilityChangedNotification object:[NSNumber numberWithInt:ns] userInfo:nil];
    if (self.reachabilityChangedHandler) {
        self.reachabilityChangedHandler(ns);
    }
    
    //If need to trigger token refresh and current network status is not "NotReachable"
    //trigger the oAuth flow again
    if (self.networkChangeShouldTriggerTokenRefresh && ns != NotReachable) {
        [self startRefreshAccessTokenFlow];
    }
}
- (BOOL)isReachable {
    if (_internalNetworkEngine) {
        return [_internalNetworkEngine isReachable];
    }
    return NO;
}

#pragma mark - Access Token Methods
- (void)startRefreshAccessTokenFlow {
    @synchronized(self) {
        if (!self.isAccessTokenBeingRefreshed) {
            _accessTokenBeingRefreshed = YES;
            _networkChangeShouldTriggerTokenRefresh = NO;
            self.previousOAuthDelegate = self.coordinator.delegate;
            
            //start authentication progress to refresh token
            if (self.coordinator.isAuthenticating) {
                [self.coordinator stopAuthentication];
            }
            [self.coordinator authenticate];
        }
    }
}

- (void)refreshAccessTokenFlowStopped:(BOOL)willAutoRetryRefreshFlow {
    @synchronized(self) {
        _accessTokenBeingRefreshed = NO;
        _networkChangeShouldTriggerTokenRefresh = NO;
        if (!willAutoRetryRefreshFlow) {
            [self restoreOAuthDelegate];
            if (self.coordinator.isAuthenticating) {
               [self.coordinator stopAuthentication];
            }
        }
    }
}

- (void)queueOperationOnExpiredAccessToken:(SFNetworkOperation *)operation {
    if (nil == operation) {
        return;
    }
    [self startRefreshAccessTokenFlow];
    [self.operationsWaitingForAccessToken addObject:operation];
}

- (void)replayOperationsWaitingForAccessToken {
    if (self.isAccessTokenBeingRefreshed) {
        return;
    }
    if (self.operationsWaitingForAccessToken.count == 0) {
        return;
    }
    NSArray *safeCopy = nil;
    @synchronized(self) {
        safeCopy = [self.operationsWaitingForAccessToken copy];
        [self.operationsWaitingForAccessToken removeAllObjects];
    }
    for (SFNetworkOperation *operation in safeCopy) {
        [self enqueueOperation:operation];
    }
}

- (void)failOperationsWaitingForAccessTokenWithError:(NSError *)error {
    NSArray *safeCopy = nil;
    @synchronized(self) {
        _accessTokenBeingRefreshed = NO;
        safeCopy = [self.operationsWaitingForAccessToken copy];
        [self.operationsWaitingForAccessToken removeAllObjects];
    }
    
    for (SFNetworkOperation *operation in safeCopy) {
        MKNetworkOperation *internalOperation = operation.internalOperation;
        NSArray *errorBlocks = [internalOperation errorBlocks];
        for (MKNKErrorBlock errorBlock in errorBlocks) {
            errorBlock(error);
        }
    }
}

- (void)restoreOAuthDelegate {
    if (nil != self.previousOAuthDelegate && nil != self.coordinator) {
        self.coordinator.delegate = self.previousOAuthDelegate;
        self.previousOAuthDelegate = nil;
    }
}

#pragma mark - SFOAuthCoordinatorDelegate
- (void)oauthCoordinator:(SFOAuthCoordinator *)coordinator didBeginAuthenticationWithView:(UIWebView *)view {
    NSLog(@"oauthCoordinator:didBeginAuthenticationWithView");
    // we are in the token exchange flow so this should never happen
    //TODO we should probably hand back control to the original coordinator delegate at this point,
    //since we don't expect to be able to handle this condition!
    [self refreshAccessTokenFlowStopped:NO];
    
    NSError *newError = [NSError errorWithDomain:kSFOAuthErrorDomain code:kOAuthErrorCode userInfo:nil];
    [self failOperationsWaitingForAccessTokenWithError:newError];
    
    // we are creating a temp view here since the oauth library verifies that the view
    // has a subview after calling oauthCoordinator:didBeginAuthenticationWithView:
    UIView *tempView = [[UIView alloc] initWithFrame:CGRectZero];
    [tempView addSubview:view];
}

- (void)oauthCoordinatorDidAuthenticate:(SFOAuthCoordinator *)coordinator {
    NSLog(@"oauthCoordinatorDidAuthenticate");
    // the token exchange worked.
    
    //mark the stop of the refrsh access token flow
    [self refreshAccessTokenFlowStopped:NO];
    
    //re-set to ensure we are sharing the same coordinator (and update credentials)
    [self accessTokenRefreshed:coordinator];
}

- (void)oauthCoordinator:(SFOAuthCoordinator *)coordinator didFailWithError:(NSError *)error {
    NSLog(@"oauthCoordinator:didFailWithError: %@", error);
    if ([SFNetworkUtils isOAuthError:error]) {
        //OAuth error occurs
        [self restoreOAuthDelegate];
        [coordinator revokeAuthentication];
        return;
    }
    
    //Mark refresh access token as stopped with auto-retry flag set to YES
    [self refreshAccessTokenFlowStopped:YES];
    
    //Other error should trigger a retry at pre-defined schedule
    //TDOO: Should it be triggered by reachability
    //Check to see if OAuth failed due to connection error
    @synchronized(self) {
        self.networkChangeShouldTriggerTokenRefresh = [SFNetworkUtils isNetworkError:error];
    }
    
    //Schedule to run startRefreshAccessTokenFlow even if network status change can trigger the
    //token refresh flow. This is the cover the edge case where network status change is not
    //accurately monitored
    //`accessTokenBeingRefreshed` flag will ensure either network status or scheduled task would
    //trigger token refresh
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, kDefaultRetryDelay * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^{
        [self startRefreshAccessTokenFlow];
    });
}
@end
