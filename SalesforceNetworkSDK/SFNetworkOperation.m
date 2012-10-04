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
#import "SalesforceCommonUtils.h"
#import "SFNetworkEngine+Internal.h"
#import "SFNetworkUtils.h"

static NSString *kDefaultFileDataMimeType = @"multipart/form-data";
static NSString *kErrorCodeKeyInResponse = @"errorCode";
static NSString *kSFNetworkOperationErrorDomain = @"com.salesforce.SFNetworkSDK.ErrorDomain";
static NSInteger const kFailedWithServerReturnedErrorCode = 999;

@implementation SFNetworkOperation
@synthesize tag = _tag;
@synthesize expectedDownloadSize = _expectedDownloadSize;
@synthesize operationTimeout = _operationTimeout;
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
        [_internalOperation onCompletion:^(MKNetworkOperation *completedOperation) {
            [weakSelf callDelegateDidFinish:completedOperation];
        } onError:^(NSError *error) {
            [weakSelf callDelegateDidFailWithError:error];
        }];
    }
    return self;
}

- (void)dealloc {
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
        [_internalOperation setHeaderValue:value forKey:key];
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
        return [_internalOperation curlCommandLineString];
    }
    else {
        return @"";
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
    if (_internalOperation) {
        [_internalOperation cancel];
        
        __weak SFNetworkOperation *weakSelf = self;
        if (weakSelf.delegate && [weakSelf respondsToSelector:@selector(operationDidCancel:)]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [self.delegate operationDidCancel:weakSelf];
            });
        }
        
        //call cancel blocks
        if (self.cancelBlocks && self.cancelBlocks.count > 0) {
            NSArray *safeCopy = nil;
            @synchronized(self) {
                safeCopy = [self.cancelBlocks copy];
                [self.cancelBlocks removeAllObjects];
            }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                for (SFNetworkOperationCancelBlock cancelBlock in safeCopy) {
                    cancelBlock(weakSelf);
                }
            });
        }
    }
    
    //Locate existing operations that are already in the queue
    MKNetworkEngine *engine = [[SFNetworkEngine sharedInstance] internalNetworkEngine];
    for (MKNetworkOperation *operation in  engine.operations) {
        if ([[operation uniqueIdentifier] isEqualToString:[_internalOperation uniqueIdentifier]] && !operation.isFinished) {
            [operation cancel];
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

#pragma mark - Block Methods
- (void)onCompletion:(SFNetworkOperationCompletionBlock)completionBlock onError:(SFNetworkOperationErrorBlock)errorBlock{
    if (_internalOperation) {
        __weak SFNetworkOperation *weakSelf = self;
        [_internalOperation onCompletion:^(MKNetworkOperation *completedOperation) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                //Perform all callbacks in background queue
                NSError *error = [self checkForErrorInResponse:completedOperation];
                if (nil != error) {
                    if (errorBlock) {
                        errorBlock(error);
                    }
                } else if (completionBlock) {
                    weakSelf.internalOperation = completedOperation;
                    completionBlock(weakSelf);
                };
            });
        } onError:^(NSError *error) {
            if (weakSelf.requiresAccessToken && [SFNetworkUtils typeOfError:error] == SFNetworkOperationErrorTypeSessionTimeOut) {
                //do nothing, queueOperationOnExpiredAccessToken is handled in callDelegateDidFailWithError
                [self log:SFLogLevelError msg:@"Session time out encountered"];
            } else if (errorBlock) {
                if ([SFNetworkUtils typeOfError:error] == SFNetworkOperationErrorTypeAccessDenied) {
                    //Permission denied error
                    NSError *potentialError = [weakSelf checkForErrorInResponse:weakSelf.internalOperation];
                    if (potentialError) {
                        error = potentialError;
                    }
                }
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    errorBlock(error);
                });
            }
        }];
    }
}


- (void)onCancel:(SFNetworkOperationCancelBlock)cancelBlock {
    if (cancelBlock) {
        [self.cancelBlocks addObject:[cancelBlock copy]];
    }
}

- (void)onUploadProgressChanged:(SFNetworkOperationProgressBlock)uploadProgressBlock {
    if (_internalOperation) {
        [_internalOperation onUploadProgressChanged:^(double progress) {
            //Perform all callbacks in background queue
            if (uploadProgressBlock) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    uploadProgressBlock(progress);
                });
            }
        }];
    }
}

- (void)onDownloadProgressChanged:(SFNetworkOperationProgressBlock)downloadProgressBlock {
    if (_internalOperation) {
        [_internalOperation onDownloadProgressChanged:^(double progress) {
            //Perform all callbacks in background queue
            if (downloadProgressBlock) {
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
    if ([NSString isEmpty:fileName]) {
        return;
    }
    if (nil == mimeType) {
        mimeType = kDefaultFileDataMimeType;
    }
    if (_internalOperation) {
        [_internalOperation addData:fileData forKey:paramName mimeType:mimeType fileName:fileName];
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
    if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(operationDidFinish:)]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSError *error = [weakSelf checkForErrorInResponse:operation];
            if (nil != error) {
                [weakSelf callDelegateDidFinish:operation];
            }
            else {
                weakSelf.internalOperation = operation;
                [weakSelf.delegate operationDidFinish:weakSelf];
            }
        });
    }
}
- (void)callDelegateDidFailWithError:(NSError *)error {
    [self log:SFLogLevelError format:@"callDelegateDidFailWithError %@", error];
    __weak SFNetworkOperation *weakSelf = self;
    if (nil != error) {
        if (nil != self.pathToStoreDownloadedContent) {
            //Download failed, remove the file if it exists to prevent partial file content
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if ([fileManager fileExistsAtPath:self.pathToStoreDownloadedContent]) {
                [fileManager removeItemAtPath:self.pathToStoreDownloadedContent error:nil];
            }
        }
    }
    if (nil != error) {
        if (weakSelf.requiresAccessToken && [SFNetworkUtils typeOfError:error] == SFNetworkOperationErrorTypeSessionTimeOut) {
            [self log:SFLogLevelError msg:@"Session time out encountered"];
            [[SFNetworkEngine sharedInstance] queueOperationOnExpiredAccessToken:weakSelf];
            return;
        }
    }
    if (nil != error && weakSelf.delegate) {
        if ([SFNetworkUtils typeOfError:error] == SFNetworkOperationErrorTypeAccessDenied) {
            //Permission denied error
            NSError *potentialError = [weakSelf checkForErrorInResponse:weakSelf.internalOperation];
            if (potentialError) {
                error = potentialError;
            }
        }
        if (error.code == kCFURLErrorTimedOut) {
            if ([weakSelf.delegate respondsToSelector:@selector(operationDidTimeout:)]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    if (error.code == kCFURLErrorTimedOut) {
                        [weakSelf.delegate operationDidTimeout:weakSelf];
                    }
                });
                return;
            }
        }
        
        //If delegate did not implement operationDidTimeout or error is not timedout error
        if ([weakSelf.delegate respondsToSelector:@selector(operation:didFailWithError:)]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                if (error.code == kCFURLErrorTimedOut) {
                    [weakSelf.delegate operation:weakSelf didFailWithError:error];
                }
            });
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
    if (nil == responseStr || ![responseStr hasPrefix:@"{"] || ![responseStr hasPrefix:@"["]) {
        //Not JSON format
        return nil;
    }
    id jsonResponse = [operation responseJSON];
    if (jsonResponse && [jsonResponse isKindOfClass:[NSArray class]]) {
        if ([jsonResponse count] == 1) {
            id potentialError = [jsonResponse objectAtIndex:0];
            if ([potentialError isKindOfClass:[NSDictionary class]]) {
                NSString *potentialErrorCode = [potentialError objectForKey:kErrorCodeKeyInResponse];
                if (nil != potentialErrorCode) {
                    // we have an error
                    NSError *error = [NSError errorWithDomain:kSFNetworkOperationErrorDomain code:kFailedWithServerReturnedErrorCode userInfo:potentialError];
                    return error;
                }
            }
        }
    }
    return nil;
}



@end
