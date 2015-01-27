//
//  SFNetworkOperation.m
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/25/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import "SFNetworkOperation.h"
#import "MKNetworkKit.h"
#import "SFNetworkOperation+Internal.h"
#import "SFNetworkEngine+Internal.h"
#import "SFNetworkUtils.h"

static NSString *kDefaultFileDataMimeType = @"multipart/form-data";

@implementation SFNetworkOperation
@synthesize tag = _tag;
@synthesize localTestDataPath = _localTestDataPath;
@synthesize expectedDownloadSize = _expectedDownloadSize;
@synthesize operationTimeout = _operationTimeout;
@synthesize maximumNumOfRetriesForNetworkError = _maximumNumOfRetriesForNetworkErrorr;
@synthesize numOfRetriesForNetworkError = _numOfRetriesForNetworkError;
@synthesize useSSL = _useSSL;
@synthesize method = _method;
@synthesize url = _url;
@synthesize error = _error;
@synthesize statusCode = _statusCode;
@synthesize uniqueIdentifier = _uniqueIdentifier;
@synthesize delegate = _delegate;
@synthesize encryptDownloadedFile = _encryptDownloadedFile;
@synthesize customHeaders = _customHeaders;
@synthesize pathToStoreDownloadedContent = _pathToStoreDownloadedContent;
@synthesize cachePolicy = _cachePolicy;
@synthesize internalOperation = _internalOperation;
@synthesize cancelBlocks = _cancelBlocks;
@synthesize retryOnNetworkError = _retryOnNetworkError;

#pragma mark - Initialize Method
- (id)initWithOperation:(MKNetworkOperation *)operation url:(NSString *)url method:(NSString *)method ssl:(BOOL)useSSL {
    self = [super init];
    if (self) {
        _internalOperation = operation;
        
        _cancelBlocks = [[NSMutableArray alloc] init];
        _useSSL = useSSL;
        _method = method;
        _url = url;
        
        //set default values
        self.encryptDownloadedFile = YES;
        self.requiresAccessToken = YES;
        self.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        
        __weak SFNetworkOperation *weakSelf = self;
        [_internalOperation addCompletionHandler:^(MKNetworkOperation *completedOperation) {
            [weakSelf callDelegateDidFinish:completedOperation];
        } errorHandler:^(MKNetworkOperation *operation, NSError *error) {
            [weakSelf callDelegateDidFailWithError:error];
        }];
    }
    return self;
}

- (void)dealloc {
    self.internalOperation = nil;
    self.delegate = nil;
}

- (void)setHeaderValue:(NSString *)value forKey:(NSString *)key {
    if (nil == _internalOperation) {
        return;
    }
    
    if (nil != value && nil != key) {
        NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionaryWithDictionary:[self customHeaders]];
        [mutableHeaders setValue:value forKey:key];
        self.customHeaders = mutableHeaders;
        [_internalOperation setHeader:key withValue:value];
    }
}

#pragma mark - Property Overload
- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[SFNetworkOperation class]]) {
        return NO;
    }
    SFNetworkOperation *otherObj = (SFNetworkOperation *)object;
    if (!self.internalOperation || !otherObj.internalOperation) {
        return NO;
    }
    if ([self.uniqueIdentifier isEqualToString:otherObj.uniqueIdentifier]) {
        return YES;
    }
    return NO;
}

- (NSUInteger)hash {
    if (_internalOperation) {
        return [[_internalOperation uniqueIdentifier] hash];
    }
    else {
        //If internal operation is nil, super hash
        return [super hash];
    }
}

- (NSError *)error {
    if (_internalOperation) {
        return [_internalOperation error];
    }
    else {
        return nil;
    }
}
- (NSInteger)statusCode {
    if (_internalOperation) {
        return [_internalOperation HTTPStatusCode];
    }
    else {
        return 0;
    }
}
- (NSString *)uniqueIdentifier {
    if (_internalOperation) {
        return [_internalOperation uniqueIdentifier];
    }
    else {
        return nil;
    }
}
- (NSString *)description {
    if (_internalOperation) {
        return [_internalOperation shortDescription];
    }
    else {
        return [super description];
    }
}
- (void)setOperationTimeout:(NSTimeInterval)operationTimeout {
    _operationTimeout = operationTimeout;
    if (_internalOperation) {
        _internalOperation.timeout = operationTimeout;
    }
}
- (void)setCustomHeaders:(NSDictionary *)customHeaders {
    _customHeaders = customHeaders;
    if (_internalOperation) {
        [_internalOperation setHeaders:customHeaders];
    }
}

- (NSDictionary*)responseHeaders {
    return _internalOperation.cacheHeaders;
}

- (void)setEncryptDownloadedFile:(BOOL)encryptDownloadedFile {
    _encryptDownloadedFile = encryptDownloadedFile;
    if (_internalOperation) {
        _internalOperation.encryptDownload = encryptDownloadedFile;
    }
}
- (void)setPathToStoreDownloadedContent:(NSString *)pathToStoreDownloadedContent {
    _pathToStoreDownloadedContent = pathToStoreDownloadedContent;
    if (_internalOperation) {
        _internalOperation.downloadFile = pathToStoreDownloadedContent;
    }
}

- (void)setExpectedDownloadSize:(NSUInteger)expectedDownloadSize {
    _expectedDownloadSize = expectedDownloadSize;
    if (_internalOperation) {
        _internalOperation.expectedContentSize = expectedDownloadSize;
    }
}

- (void)cancel {
    [super cancel];
    
    if (!_internalOperation) {
        [self log:SFLogLevelWarning msg:@"Cancel an operation that does not have internal network operation set first"];
        return;
    }
    NSString *operationIdentifier = [_internalOperation uniqueIdentifier];
    [[self class] deleteUnfinishedDownloadFileForOperation:self.internalOperation];
    
    [_internalOperation cancel];

    __weak SFNetworkOperation *weakSelf = self;
    if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(networkOperationDidCancel:)]) {
        if([self canCallback]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [self.delegate networkOperationDidCancel:weakSelf];
            });
        }
    }
    
    //call cancel blocks
    if (self.cancelBlocks && self.cancelBlocks.count > 0) {
        NSArray *safeCopy = nil;
        @synchronized(self) {
            safeCopy = [self.cancelBlocks copy];
            [self.cancelBlocks removeAllObjects];
        }
        if([self canCallback]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                for (SFNetworkOperationCancelBlock cancelBlock in safeCopy) {
                    cancelBlock(weakSelf);
                }
            });
        }
    }
    
    //Locate existing operations that are already in the queue
    //with the same unique ID
    MKNetworkEngine *engine = [[SFNetworkEngine sharedInstance] internalNetworkEngine];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"uniqueIdentifier = %@", operationIdentifier];
    NSArray *operations = [[engine operations] filteredArrayUsingPredicate:predicate];
    for (MKNetworkOperation *operation in operations) {
        if ([operation isCacheable] && !operation.isFinished) {
            //only cancel cacheable operation, which means GET only
            [operation cancel];
                
            //cancel download file if applicable
            [[self class] deleteUnfinishedDownloadFileForOperation:operation];
        }
    }
    
}

- (void)setQueuePriority:(NSOperationQueuePriority)p {
    [super setQueuePriority:p];
    if (_internalOperation) {
        _internalOperation.queuePriority = p;
    }
}
- (NSOperationQueuePriority)queuePriority {
    if (_internalOperation) {
        return _internalOperation.queuePriority;
    } else {
        return [super queuePriority];
    }
}
- (void)addDependency:(NSOperation *)op {
    if (_internalOperation && [op isKindOfClass:[SFNetworkOperation class]]) {
        SFNetworkOperation *dependOp = (SFNetworkOperation *)op;
        if (dependOp.internalOperation) {
            [_internalOperation addDependency:dependOp.internalOperation];
        }
    }
}
- (void)setCachePolicy:(NSURLRequestCachePolicy)cachePolicy {
    _cachePolicy = cachePolicy;
    if (_internalOperation) {
        _internalOperation.cachePolicy = cachePolicy;
    }
}
- (void)setRequiresAccessToken:(BOOL)requiresAccessToken {
    _requiresAccessToken = requiresAccessToken;
    if (_internalOperation) {
        _internalOperation.requiresAccessToken = requiresAccessToken;
    }
}

-(void)setCustomPostDataEncodingHandler:(SFNetworkOperationEncodingBlock)postDataEncodingHandler forType:(NSString*)contentType {
    _customPostDataEncodingContentType = contentType;
    if (_internalOperation) {
        [_internalOperation setCustomPostDataEncodingHandler:postDataEncodingHandler forType:contentType];
    }
}

-(BOOL) canCallback {
    // If we have a coordinator then we can call back.. If not then we are most likely logged out and the block might not be available.
    return [SFNetworkEngine sharedInstance].coordinator?YES:NO;
}

#pragma mark - Block Methods
- (void)addCompletionBlock:(SFNetworkOperationCompletionBlock)completionBlock errorBlock:(SFNetworkOperationErrorBlock)errorBlock{
    if (_internalOperation) {
        __weak SFNetworkOperation *weakSelf = self;
        [_internalOperation addCompletionHandler:^(MKNetworkOperation *completedOperation) {
            if([weakSelf canCallback]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    //Perform all callbacks in background queue
                    NSError *error = [weakSelf checkForErrorInResponse:completedOperation];
                    if (nil != error) {
                        if (errorBlock) {
                            errorBlock(error);
                        }
                    } else if (completionBlock) {
                        weakSelf.internalOperation = completedOperation;
                        completionBlock(weakSelf);
                    };
                });
            }
        } errorHandler:^(MKNetworkOperation *operation, NSError *error) {
            NSError *serviceError = [weakSelf checkForErrorInResponseStr:weakSelf.responseAsString withError:error];
            if (serviceError) {
                error = serviceError;
            }
            
            if (weakSelf.requiresAccessToken && [SFNetworkUtils typeOfError:error] == SFNetworkOperationErrorTypeSessionTimeOut) {
                //do nothing, queueOperationOnExpiredAccessToken is handled in callDelegateDidFailWithError
                [weakSelf log:SFLogLevelError format:@"Session time out encountered. Actual error: [%@]. Will be retried in callDelegateDidFailWithError", [error localizedDescription]];
                return;
            }
            if ([weakSelf shouldRetryOperation:weakSelf onNetworkError:error]) {
                //do nothing, queueOperationOnNetworkError is handled in callDelegateDidFailWithError
                [weakSelf log:SFLogLevelError format:@"Network time out encountered. Actual error: [%@]. Will be retried in callDelegateDidFailWithError", [error localizedDescription]];
                return;
            }
            
            if (errorBlock) {
                if([weakSelf canCallback]) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                        errorBlock(error);
                    });
                }
            }
        }];
    }
}


- (void)addCancelBlock:(SFNetworkOperationCancelBlock)cancelBlock {
    if (cancelBlock) {
        [self.cancelBlocks addObject:[cancelBlock copy]];
    }
}

- (void)addUploadProgressBlock:(SFNetworkOperationProgressBlock)uploadProgressBlock {
    if (_internalOperation) {
        [_internalOperation onUploadProgressChanged:^(double progress) {
            //Perform all callbacks in background queue
            if (uploadProgressBlock && [self canCallback]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    uploadProgressBlock(progress);
                });
            }
        }];
    }
}

- (void)addDownloadProgressBlock:(SFNetworkOperationProgressBlock)downloadProgressBlock {
    if (_internalOperation) {
        [_internalOperation onDownloadProgressChanged:^(double progress) {
            //Perform all callbacks in background queue
            if (downloadProgressBlock && [self canCallback]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    downloadProgressBlock(progress);
                });
            }
        }];
    }
}

#pragma mark - Upload Methods
- (void)addPostFileData:(NSData *)fileData paramName:(NSString *)paramName fileName:(NSString *)fileName mimeType:(NSString *)mimeType {
    if (fileData == nil) {
        return;
    }
    if ([NSString isEmpty:paramName]) {
        return;
    }
    if (nil == mimeType) {
        mimeType = kDefaultFileDataMimeType;
    }
    
    if (_internalOperation) {
        [_internalOperation addData:fileData forKey:paramName mimeType:mimeType fileName:fileName];
        fileData = nil;
    }
}

- (void)addFile:(NSString *)file forKey:(NSString *)key {
    if (file == nil) {
        return;
    }
    
    if (_internalOperation) {
        [_internalOperation addFile:file forKey:key];
    }
}

#pragma mark - Response Methods
- (NSString *)responseAsString {
    if (_internalOperation) {
        if (_internalOperation.isFinished) {
            return _internalOperation.responseString;
        }
    }
    return nil;
}
- (id)responseAsJSON {
    NSString *responseStr = [self responseAsString];
    if (nil == responseStr || (![responseStr hasPrefix:@"{"] && ![responseStr hasPrefix:@"["])) {
        //Not JSON format
        return nil;
    }
    if (_internalOperation) {
        return _internalOperation.responseJSON;
    }
    return nil;
}
- (NSData *)responseAsData {
    if (_internalOperation) {
        return _internalOperation.responseData;
    }
    return nil;
}
- (id)responseAsImage {
    if (_internalOperation) {
        return _internalOperation.responseImage;
    }
    return nil;
}

#pragma mark - Delegate Methods
- (void)callDelegateDidFinish:(MKNetworkOperation *)operation {
    __weak SFNetworkOperation *weakSelf = self;
    if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(networkOperationDidFinish:)]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSError *error = [weakSelf checkForErrorInResponse:operation];
            if (nil != error) {
                [weakSelf callDelegateDidFailWithError:error];
            }
            else {
                weakSelf.internalOperation = operation;
                if([self canCallback]) {
                    [weakSelf.delegate networkOperationDidFinish:weakSelf];
                }
            }
        });
    }
}
- (void)callDelegateDidFailWithError:(NSError *)error {
    if (nil == error) {
        [self log:SFLogLevelError format:@"callDelegateDidFailWithError invoked with nil error"];
        return;
    }
    
    // Ignore 304 (not modified) error to avoid deleting any data associated with this operation
    if (304 == error.code) {
        return;
    }
    
    NSError *serviceError = [self checkForErrorInResponseStr:self.responseAsString withError:error];
    if (serviceError) {
        error = serviceError;
    }
    
    [self log:SFLogLevelError format:@"callDelegateDidFailWithError %@", [error localizedDescription]];
    __weak SFNetworkOperation *weakSelf = self;
    [[self class] deleteUnfinishedDownloadFileForOperation:weakSelf.internalOperation];
    
    if (weakSelf.requiresAccessToken && [SFNetworkUtils typeOfError:error] == SFNetworkOperationErrorTypeSessionTimeOut) {
        if ([SFNetworkEngine sharedInstance].delegate) {
            // queue failed operation if networkengine has delegate assigned
            // if delegate is not assigned, treat timeout as regular error
            [weakSelf log:SFLogLevelError format:@"Session timeout encountered. Requeue % for retry later", weakSelf];
            [[SFNetworkEngine sharedInstance] queueOperationOnExpiredAccessToken:weakSelf];
            return;
        }
        
    }
    
    
    if ([weakSelf shouldRetryOperation:weakSelf onNetworkError:error]) {
        [weakSelf log:SFLogLevelError format:@"Network error encountered. Requeue % for retry later", weakSelf];
        //Increase the current retry count
        _numOfRetriesForNetworkError++;
        [[SFNetworkEngine sharedInstance] queueOperationOnNetworkError:weakSelf];
        return;
    }
    
    if (weakSelf.delegate) {
        if (error.code == kCFURLErrorTimedOut) {
            if ([weakSelf.delegate respondsToSelector:@selector(networkOperationDidTimeout:)]) {
                if([self canCallback]) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                        [weakSelf.delegate networkOperationDidTimeout:weakSelf];
                    });
                }
                return;
            }
        }
        
        //If delegate did not implement operationDidTimeout or error is not timedout error
        if ([weakSelf.delegate respondsToSelector:@selector(networkOperation:didFailWithError:)]) {
            if([self canCallback]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    [weakSelf.delegate networkOperation:weakSelf didFailWithError:error];
                });
            }
            return;
        }
    }
}

#pragma mark - Error Methods
//Check to if an operation's json response contains error code
- (NSError *)checkForErrorInResponse:(MKNetworkOperation *)operation {
    if (nil != operation) {
        return nil;
    }
    NSString *responseStr = [operation responseString];
    
    return [self checkForErrorInResponseStr:responseStr withError:operation.error];
}

- (NSError *)checkForErrorInResponseStr:(NSString *)responseStr withError:(NSError * )error {
    if (nil == responseStr || (![responseStr hasPrefix:@"{"] && ![responseStr hasPrefix:@"["])) {
        //Not JSON format
        return error;
    }
    
    
    id jsonResponse = [self responseAsJSON];
    if (jsonResponse && [jsonResponse isKindOfClass:[NSArray class]]) {
        if ([jsonResponse count] > 0) {
            id potentialError = [jsonResponse objectAtIndex:0];
            if ([potentialError isKindOfClass:[NSDictionary class]]) {
                NSDictionary *errorDictionary = (NSDictionary *)potentialError;
                NSString *potentialErrorCode = errorDictionary[kErrorCodeKeyInResponse];
                NSString *potentialErrorMessage  = errorDictionary[kErrorMessageKeyInResponse];
                if (nil != potentialErrorCode && nil != potentialErrorMessage) {
                    NSDictionary *errorDictionary = @{
                                                      NSLocalizedDescriptionKey : potentialErrorMessage,
                                                      NSLocalizedFailureReasonErrorKey : potentialErrorCode,
                                                      kSFOriginalApiError : jsonResponse };
                    NSError *translatedError = [NSError errorWithDomain:error.domain code:error.code userInfo:errorDictionary];
                    return translatedError;
                }
            }
        }
    }
    return error;
}

- (BOOL)shouldRetryOperation:(SFNetworkOperation *)operation onNetworkError:(NSError *)error {
    if ([SFNetworkUtils typeOfError:error] == SFNetworkOperationErrorTypeNetworkError) {
        BOOL retryOnNetworkError = NO;
        if (operation.retryOnNetworkError) {
            if (operation.maximumNumOfRetriesForNetworkError == 0 || operation.numOfRetriesForNetworkError < operation.maximumNumOfRetriesForNetworkError) {
                retryOnNetworkError = YES;
            }
        }
        return retryOnNetworkError;
    } else {
        return NO;
    }
}
+ (void)deleteUnfinishedDownloadFileForOperation:(MKNetworkOperation *)operation {
    if (nil == operation || nil == operation.downloadFile) {
        return;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:operation.downloadFile]) {
        [fileManager removeItemAtPath:operation.downloadFile error:nil];
    }
}
@end
