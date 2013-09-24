//
//  SFNetworkEngine.m
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/24/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import "Reachability.h"
#import "SFNetworkEngine.h"
#import "MKNetworkKit.h"
#import "SFNetworkOperation.h"
#import "SFNetworkOperation+Internal.h"
#import "SFNetworkEngine+Internal.h"
#import "SFNetworkUtils.h"

#pragma mark - Operation Method
NSString * const SFNetworkOperationGetMethod = @"GET";
NSString * const SFNetworkOperationPostMethod = @"POST";
NSString * const SFNetworkOperationPutMethod = @"PUT";
NSString * const SFNetworkOperationDeleteMethod = @"DELETE";
NSString * const SFNetworkOperationPatchMethod = @"PATCH";
NSString * const SFNetworkOperationHeadMethod = @"HEAD";

#pragma mark - Notification Name
NSString * const SFNetworkOperationReachabilityChangedNotification = @"SFNetworkOperationReachabilityChangedNotification";
NSString * const SFNetworkOperationEngineOperationCancelledNotification = @"SFNetworkOperationEngineOperationCancelledNotification";
NSString * const SFNetworkOperationEngineSuspendedNotification = @"SFNetworkOperationEngineSuspendedNotification";
NSString * const SFNetworkOperationEngineResumedNotification = @"SFNetworkOperationEngineResumedNotification";

static NSInteger const kDefaultTimeOut = 3 * 60; //3 minutes
static NSInteger const kOAuthErrorCode = 999;
static NSTimeInterval const kDefaultRetryDelay = 30; //30 seconds

static NSString * const kAuthoriationHeader = @"OAuth %@";
static NSString * const kAuthoriationHeaderKey = @"Authorization";

@interface SFNetworkEngine  ()

/** Return YES if the new coordinator passed in should trigger the re-creation of the nework engine

 Condition that should trigger network engine re-creation include
 - Instance URL change
 - User ID change
 - Org ID change
 
 @param coordinator New SFOAuthCoordinator object
*/
- (BOOL)needToRecreateNetworkEngine:(SFNetworkCoordinator *)coordinator;

/** Return default custom HTTP headers
 
 Default HTTP headers include
 - User-Agent string that include application name, version, os version and platform type. See `[NSString userAgentString]` in `NSString+SFAddtions` for more details
 - Authorization header with OAuth type and OAuth access token
 */
- (NSDictionary *)defaultCustomHeaders;

/** Method to be invoked when reachability status changed
 
 @param ns New rechability status
 */
- (void)reachabilityChanged:(NetworkStatus)ns;
@end

@implementation SFNetworkEngine
@synthesize coordinator = _coordinator;
@synthesize remoteHost = _remoteHost;
@synthesize customHeaders = _customHeaders;
@synthesize reachabilityChangedHandler = _reachabilityChangedHandler;
@synthesize operationTimeout = _operationTimeout;
@synthesize suspendRequestsWhenAppEntersBackground = _suspendRequestsWhenAppEntersBackground;
@synthesize internalNetworkEngine = _internalNetworkEngine;
@synthesize operationsWaitingForAccessToken = _operationsWaitingForAccessToken;
@synthesize accessTokenBeingRefreshed = _accessTokenBeingRefreshed;
@synthesize networkChangeShouldTriggerTokenRefresh = _networkChangeShouldTriggerTokenRefresh;
@synthesize enableHttpPipeling = _enableHttpPipeling;
@synthesize supportLocalTestData = _supportLocalTestData;
@synthesize networkStatus = _networkStatus;

#pragma mark - Initialization
- (id)init {
    self = [super init];
    if (self) {
        //Set default value
        _operationTimeout = kDefaultTimeOut;
        _suspendRequestsWhenAppEntersBackground = YES;
        _enableHttpPipeling = YES;
        _supportLocalTestData = NO;
        _operationsWaitingForAccessToken = [[NSMutableArray alloc] init];
        
        _operationsWaitingForNetwork = [[NSMutableArray alloc] init];
        
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
        _coordinator = nil;
        [self.operationsWaitingForAccessToken removeAllObjects];
        
        // Only if we have a internal Network Engine
        if(_internalNetworkEngine) {
            [self.internalNetworkEngine cancelAllOperations];
        }
    }
}

#pragma mark - Property Override
- (void)setCoordinator:(SFNetworkCoordinator *)coordinator {
    if (_internalNetworkEngine) {
        //network engine created before
        if ([self needToRecreateNetworkEngine:coordinator]) {
            [self cleanup];
             _internalNetworkEngine = nil;
        }
    }
    _coordinator = coordinator;
    self.remoteHost = [_coordinator host];
    if (!_internalNetworkEngine) {
        //If network engine is not created, create it
        [self internalNetworkEngine];
    }
    
    @synchronized(self) {
        if (self.isAccessTokenBeingRefreshed) {
            _accessTokenBeingRefreshed = NO;
            
            //set OAuth token
            NSString *token = [NSString stringWithFormat:kAuthoriationHeader, _coordinator.accessToken];
            [self setHeaderValue:token forKey:kAuthoriationHeaderKey];
        }
        if (self.operationsWaitingForAccessToken.count > 0) {
            [self log:SFLogLevelInfo msg:@"Start to replay operationsWaitingForAccessToken"];
            [self replayOperationsWaitingForAccessToken];
        }
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
        NSAssert((_coordinator != nil || _remoteHost != nil), @"Either SFOAuthCoordinator or remoteHost must be set first before invoke any network call.");
        
        
        _internalNetworkEngine = [[MKNetworkEngine alloc] initWithHostName:self.remoteHost customHeaderFields:[self customHeaders]];
        
        __weak SFNetworkEngine *weakSelf = self;
        _internalNetworkEngine.reachabilityChangedHandler =  ^ (NetworkStatus ns) {
            [weakSelf reachabilityChanged:ns];
        };
    }
    return _internalNetworkEngine;
}
- (SFNetworkStatus)networkStatus {
    return _networkStatus;
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
    if ([url hasPrefix:@"/"]) {
        //take out the preceding "/"
        url = [url substringFromIndex:1];
    }
    
    NSString *lowerCaseUrl = [url lowercaseString];
    
    if (![lowerCaseUrl hasPrefix:@"http:"] && ![lowerCaseUrl hasPrefix:@"https:"]) {
        //relative URL, construct full URL
        NSString *scheme = useSSL ? @"https" : @"http";
        NSString *portNumber = @"";
        if (useSSL) {
           portNumber =  self.coordinator.sslPortNumber? [NSString stringWithFormat:@":%d", [self.coordinator.sslPortNumber intValue]] : @"";
        } else {
           portNumber =  self.coordinator.portNumber? [NSString stringWithFormat:@":%d", [self.coordinator.portNumber intValue]] : @"";
        }
        
        //If API path is nil or URL already starts with API path, construct with instanceUrl only
        if ([NSString isEmpty:self.apiPath] || [lowerCaseUrl hasPrefix:[self.apiPath lowercaseString]]) {
            url = [NSString stringWithFormat:@"%@://%@%@/%@", scheme, self.remoteHost, portNumber, url];
        }
        else {
            url = [NSString stringWithFormat:@"%@://%@%@/%@/%@",scheme, self.remoteHost, portNumber, self.apiPath, url];
        }
    }
    else {
        useSSL = [lowerCaseUrl hasPrefix:@"https:"];
    }
    
    MKNetworkOperation *internalOperation = [engine operationWithURLString:url params:[NSMutableDictionary dictionaryWithDictionary:params] httpMethod:method];
    internalOperation.enableHttpPipelining = self.enableHttpPipeling;
    internalOperation.freezable = NO;
    SFNetworkOperation *operation = [[SFNetworkOperation alloc] initWithOperation:internalOperation url:url method:method ssl:useSSL];
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

- (SFNetworkOperation *)head:(NSString *)url params:(NSDictionary *)params {
    return [self operationWithUrl:url params:params httpMethod:SFNetworkOperationHeadMethod ssl:YES];
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
    
    //Make sure authorization header is up-to-date
    if (operation.requiresAccessToken) {
        if (self.coordinator) {
            NSString *token = [NSString stringWithFormat:kAuthoriationHeader, self.coordinator.accessToken];
            [operation setHeaderValue:token forKey:kAuthoriationHeaderKey];
        } else {
            // directly queue up the operation as access token is missing
            [self queueOperationOnExpiredAccessToken:operation];
            return;
        }
    }
    
    //Handle testing mode and read data from local test file
    if (self.supportLocalTestData && nil != operation.localTestDataPath && nil != operation.internalOperation) {
        NSData *fileData = [self readDataFromTestFile:operation.localTestDataPath];
        [operation.internalOperation setLocalTestData:fileData];
    }
    
    //add no cache header Cache-control: no-cache, no-store
    [operation setHeaderValue:@"no-cache, no-store" forKey:@"Cache-control"];
    
    MKNetworkEngine *engine = [self internalNetworkEngine];
    [engine enqueueOperation:operation.internalOperation forceReload:YES];
}

- (void)cancelAllOperations {
    if (nil != _internalNetworkEngine) {
        [_internalNetworkEngine cancelAllOperations];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SFNetworkOperationEngineOperationCancelledNotification object:nil userInfo:nil];
}

- (void)cancelAllOperationsWithTag:(NSString *)operationTag {
    if (nil == operationTag || nil == _internalNetworkEngine) {
        return;
    }
//    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"tag = %@", operationTag];
//    NSArray *operations = [[_internalNetworkEngine operations] filteredArrayUsingPredicate:predicate];
    for (MKNetworkOperation *operation in [self operationsWithTag:operationTag]) {
        NSLog(@"operation tag is %@", operationTag);
        if (!operation.isFinished) {
            //only cancel cacheable operation, which means GET only
            [operation cancel];
        }
    }
}

- (NSArray *)operationsWithTag:(NSString *)operationTag {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"tag = %@", operationTag];
    NSArray *operations = [[_internalNetworkEngine operations] filteredArrayUsingPredicate:predicate];
    NSMutableArray *pendingOperations = [NSMutableArray arrayWithCapacity:operations.count];
    
    for (MKNetworkOperation *operation in operations) {
        if (!operation.isFinished) {
            //only cancel cacheable operation, which means GET only
            [pendingOperations addObject:operation];
        }
    }
    return pendingOperations;
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
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"tag = %@", operationTag];
    NSArray *operations = [[_internalNetworkEngine operations] filteredArrayUsingPredicate:predicate];
    for (MKNetworkOperation *operation in operations) {
        if (!operation.isFinished) {
                return YES;
        }
    }
    return NO;
}

#pragma mark - Private Method
/** Return YES when coordinator has changed 
 
 If coordinator instance URL, user Id or orgId is changed, return YES to indicator that internal network engine needs to be re-created
 */
- (BOOL)needToRecreateNetworkEngine:(SFNetworkCoordinator *)coordinator {
    NSString *newHostName = nil, *newOrgId = nil, *newUserId = nil;
    NSString *currentHostName = nil, *currentOrgId = nil, *currentUserId = nil;
     
    if (coordinator) {
        newHostName = coordinator.host;
        newOrgId = coordinator.organizationId;
        newUserId = coordinator.userId;
    }
    else {
        newHostName = @"";
        newOrgId = @"";
        newUserId = @"";
    }
    
    if (self.coordinator) {
        currentHostName = self.coordinator.host;
        currentOrgId = self.coordinator.organizationId;
        currentUserId = self.coordinator.userId;
        
        BOOL needToRecreate = ![newHostName isEqualToString:currentHostName]
        ||![newOrgId isEqualToString:currentOrgId]
        ||![newUserId isEqualToString:currentUserId];
        
        return needToRecreate;
    }
    else {
        return NO;
    }
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
        NSString *token = [NSString stringWithFormat:kAuthoriationHeader, _coordinator.accessToken];
        [headers setValue:token forKey:kAuthoriationHeaderKey];
    }
    
    [headers setValue:@"gzip" forKey:@"Accept-Encoding"];
    
    //read user agent from user defaults, this value will be populated by mobileSDK if it is used
    NSString *userAgent = [[NSUserDefaults standardUserDefaults] stringForKey:@"UserAgent"];    
   
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
    _networkStatus = (SFNetworkStatus)ns;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SFNetworkOperationReachabilityChangedNotification object:[NSNumber numberWithInt:ns] userInfo:nil];
    if (self.reachabilityChangedHandler) {
        self.reachabilityChangedHandler((SFNetworkStatus)ns);
    }
    
    //If need to trigger token refresh and current network status is not "NotReachable"
    //trigger the oAuth flow again
    if (self.networkChangeShouldTriggerTokenRefresh && ns != NotReachable) {
        [self startRefreshAccessTokenFlow];
    }
    
    if (ns != NotReachable) {
        [self replayOperationsWaitingForNetwork];
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
            if (self.delegate) {
                [self log:SFLogLevelInfo msg:@"start refresh access token flow"];
                [self.delegate refreshSessionForNetworkEngine:self];
            }
        }
    }
}

#pragma mark - Queue and Replay for Access Token
- (void)queueOperationOnExpiredAccessToken:(SFNetworkOperation *)operation {
    if (nil == operation) {
        return;
    }
    
    NSString *hostName = [self remoteHost];
    
    // add logic to check for mismatching host name to prevent trying to re-queue request that errors out
    // with invalid session due to mis-matched host
    if ([operation.url rangeOfString:hostName].location == NSNotFound) {
        [self log:SFLogLevelError format:@"Ignore session timeout error callback as host URL changed, request URL is %@, login host is [%@]", operation.url, hostName];
        return;
    }
    
    [self startRefreshAccessTokenFlow];
    
    SFNetworkOperation *newOperation = [self cloneInternalOperation:operation];
    if (newOperation) {
        @synchronized(self) {
            [self.operationsWaitingForAccessToken addObject:newOperation];
        }
    }
}

- (void)replayOperationsWaitingForAccessToken {
    if (self.isAccessTokenBeingRefreshed) {
        return;
    }
    
    NSArray *safeCopy = nil;
    @synchronized(self) {
        if (self.operationsWaitingForAccessToken.count == 0) {
            return;
        }
        
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
        NSArray *errorBlocks = [internalOperation errorBlocksType2];
        for (MKNKResponseErrorBlock errorBlock in errorBlocks) {
            errorBlock(internalOperation, error);
        }
    }
}

#pragma mark - Queue and Replay for Network 
- (void)queueOperationOnNetworkError:(SFNetworkOperation *)operation {
    if (nil == operation) {
        return;
    }
    
    SFNetworkOperation *newOperation = [self cloneInternalOperation:operation];
    if (newOperation) {
        @synchronized(self) {
            [self.operationsWaitingForNetwork addObject:newOperation];
        }
    }
}

- (void)replayOperationsWaitingForNetwork {
    NSMutableArray *safeCopy = nil;
    @synchronized(self) {
        if (self.operationsWaitingForNetwork.count == 0) {
            return;
        }
        
        safeCopy = [NSMutableArray  arrayWithArray:[self.operationsWaitingForNetwork copy]];
        
        [self.operationsWaitingForNetwork removeAllObjects];
        
        // Check for access token and if there is not any then move the operation to the waiting for token queue.
        BOOL needsAccessToken = NO;
        NSString* accessToken = self.coordinator.accessToken;
        for(SFNetworkOperation * operation in safeCopy) {
            if(!accessToken && operation.requiresAccessToken) {
                needsAccessToken = YES;
                [self.operationsWaitingForAccessToken addObject:operation];
            }
        }
            
        [safeCopy removeObjectsInArray:self.operationsWaitingForAccessToken];
        
        if (needsAccessToken) {
            [self startRefreshAccessTokenFlow];
        }
    }
    
    for (SFNetworkOperation *operation in safeCopy) {
        [self enqueueOperation:operation];
    }

}

- (BOOL)operationAlreadyInWaitingQueue:(SFNetworkOperation *)operation {
    for (SFNetworkOperation *existingOperation in self.operationsWaitingForAccessToken) {
        if ([existingOperation isEqual:operation]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Clone Operation
#pragma mark - Copying Protocol
- (SFNetworkOperation *)cloneInternalOperation:(SFNetworkOperation *)operation {
    if (nil == operation) {
        return nil;
    }
    MKNetworkOperation *internalOperation = operation.internalOperation;
    
    if (nil == internalOperation) {
        return nil;
    }

    // Cloning internal operation
    MKNetworkOperation *newInternalOperation = [[self internalNetworkEngine] operationWithURLString:operation.url params:internalOperation.fieldsToBePosted httpMethod:operation.method];
    newInternalOperation.enableHttpPipelining = self.enableHttpPipeling;
    newInternalOperation.freezable = NO;
    [newInternalOperation updateHandlersFromOperation:internalOperation];
    
    //Add file data if exists
    if (internalOperation.dataToBePosted.count > 0) {
        for (NSDictionary *fileDict in internalOperation.dataToBePosted) {
            NSString *paramName = [fileDict valueForKey:@"name"];
            NSString *fileName = [fileDict valueForKey:@"filename"];
            NSData *fileData = [fileDict objectForKey:@"data"];
            NSString *mimeType = [fileDict valueForKey:@"mimetype"];
            [newInternalOperation addData:fileData forKey:paramName mimeType:mimeType fileName:fileName];
        }
    }
    
    //Clone custom encoding handler
    if (internalOperation.postDataEncodingHandler) {
        [newInternalOperation setCustomPostDataEncodingHandler:internalOperation.postDataEncodingHandler forType:operation.customPostDataEncodingContentType];
    }

    // Have operation use the new internal operation
    operation.internalOperation = newInternalOperation;
    
    return operation;
}

#pragma mark - Local Test Data Support
- (NSData *)readDataFromTestFile:(NSString *)localDataFilePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:localDataFilePath]){
        return nil;
    }
    NSData *fileData = [NSData dataWithContentsOfFile:localDataFilePath];
    
    return fileData;
}
@end
