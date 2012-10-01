//
//  SFNetworkOperation.h
//  NetworkSDK
//
//  Created by Qingqing Liu on 9/25/12.
//  Copyright (c) 2012 salesforce.com. All rights reserved.
//

#import <Foundation/Foundation.h>
@class SFNetworkOperation;

typedef void (^SFNetworkOperationProgressBlock)(double progress);
typedef void (^SFNetworkOperationCompletionBlock)(SFNetworkOperation* operation);
typedef void (^SFNetworkOperationCancelBlock)(SFNetworkOperation* operation);
typedef void (^SFNetworkOperationErrorBlock)(NSError* error);

@protocol SFNetworkOperationDelegate <NSObject>

@optional
- (void)operationDidFinish:(SFNetworkOperation *)operation;
- (void)operation:(SFNetworkOperation *)operation didFailWithError:(NSError *)error;
- (void)operationDidCancel:(SFNetworkOperation *)operation;
- (void)operationDidTimeout:(SFNetworkOperation *)operation;
@end
/**
 Main class used to create and execute remote network call
 
 `SFNetworkEngine` should be used to create instance of `SFNetworkOperation`
 */
@interface SFNetworkOperation : NSOperation

/**Custom tag for this operation
 
 Tag can be used to categorize `SFNetworkOperation` and used together with `[SFNetworkEngine hasPendingOperationsWithTag]`
 */
@property (nonatomic, strong) NSString *tag;

/**Expected download size
 
 Set this property to the expected download size when running a SFNetworkOperation for downloading a binary content. If this property is not set, `SFNetworkOperation` will rely on the "Content-Length" in response header to properly invoke the `SFNetworkOperationProgressBlock` download progress block
 
 As of 180 release, salesforce content download API does not set "Content-Length" response header properly,  make sure set this property before start a download operation
 */
@property (nonatomic, assign) NSUInteger expectedDownloadSize;

/** Network timeout setting in seconds. Default value is 180 seconds
 */
@property (nonatomic, assign) NSTimeInterval operationTimeout;

/** Request URL Property
 */
@property (nonatomic, readonly, strong) NSString *url;

/** If the operation results in an error, this will hold the response error, otherwise it will be nil */
@property (nonatomic, readonly, strong) NSError *error;

/** Returns the operation response's status code.
 
 Returns 0 when the operation has not yet started and the response is not available.
 */
@property (nonatomic, readonly, assign) NSInteger statusCode;

/** Returns an uniqueIdentifer for this operation
 
 uniqueIdentifier is generated based on operation's method, url and parameters*/
@property (nonatomic, readonly, strong) NSString *uniqueIdentifier;

/**Delegate can be used to monitor operation status (complete, error, cancel or timeout) in lieu of using blocks
 */
@property (nonatomic, weak) id <SFNetworkOperationDelegate> delegate;

/**Set to YES to encrypt all downloaded content. Default value is YES*/
@property (nonatomic, assign) BOOL encryptDownloadedFile;

/**Set to YES if the operation requires an access token. Default value is YES*/
@property (nonatomic, assign) BOOL requiresAccessToken;

/** Custom HTTP headers that will be used by this operation
 
 CustomHeaders Value specified by this parameter will override value set by `[SFNetworkEngine customHeaders]`
 */
@property (nonatomic, strong) NSDictionary *customHeaders;

/**Set path to store downloaded content
 
Path to store downloaded content. If this value is set, all content downloaded by this operation will be stored at the path specified. And  if `encryptDownloadedFile` is set to true, file content will be encrypted
 */
@property (nonatomic, strong) NSString *pathToStoreDownloadedContent;


/** Set value for the specified HTTP header
 
 @param value Header value. If value is nil, this method will remove value for the specified key from the headers
 @param key Header key
 */
- (void)setHeaderValue:(NSString *)value forKey:(NSString *)key;

/**Cache policy for this operation. Default value is NSURLRequestReloadIgnoringLocalCacheData*/
@property (nonatomic, assign) NSURLRequestCachePolicy cachePolicy;


///---------------------------------------------------------------
/// @name Method for File Upload
///---------------------------------------------------------------
/** Attach file data as multipart/​form POST data
 
 This method can be used to upload binary file. A multi-part form data will be constructured based on the value passed in with format
 
 Content-Disposition: form-data; name=`name`; filename=`fileName` (if name is not nil)
 Content-Disposition: form-data; filename=`fileName` (if name is nil)
 Content-Type: `mimeType`
 `fileData`
 
 @param fileData File raw data
 @param paramName Parameter name to be used in the multi-part form data for this file. nil is accepted
 @param fileName File name to be used in the multi-part form data for this file
 @param mimeType File mimetype. Nil is accpeted. If nil is passed, 'multipart/form-data' will be used by default as the mimetype. Server side will use the fileName to figure out the proper mimetype for the file
 */
- (void)addPostFileData:(NSData *)fileData paramName:(NSString *)paramName fileName:(NSString *)fileName mimeType:(NSString *)mimeType;

///---------------------------------------------------------------
/// @name Block Methods
///---------------------------------------------------------------
/** Add block Handler for completion
 
 An operation can have multiple completion and error blocks attached to it. 
 When the operation completes successfully each registered completion block will be executed on a background thread.
 When operation errors out or operation response contains single JSON array with errorCode, each registered error block will be executed on a background thread
 @param completionBlock Completion block to be invoked when operation is completed successfully
 */
- (void)onCompletion:(SFNetworkOperationCompletionBlock)completionBlock onError:(SFNetworkOperationErrorBlock)errorBlock;


/** Add block Handler for cancel
 
 An operation can have multiple cancel blocks attached to it. When an operation is cancelled each registered block will be executed on a background thread. 
 @param cancelBlock Error block to be invoked when operation is cancelled
 */
- (void)onCancel:(SFNetworkOperationCancelBlock)cancelBlock;


/** Add Block Handler for tracking upload progress
 
 An operation can have multiple upload progress blocks attached to it. When upload process changes each registered block will be executed on a background thread
 @param uploadProgressBlock Block to be invoked when upload progress is changed
 */
- (void)onUploadProgressChanged:(SFNetworkOperationProgressBlock)uploadProgressBlock;

/** Add Block Handler for tracking download progress
 
 An operation can have multiple download progress blocks attached to it. When download process changes each registered block will be executed on a background thread
 @param downloadProgressBlock Block to be invoked when download progress is changed
 */
- (void)onDownloadProgressChanged:(SFNetworkOperationProgressBlock)downloadProgressBlock;


///---------------------------------------------------------------
/// @name Response Object Helper Methods
///---------------------------------------------------------------
/** Returns the downloaded data as a string.
 *
 * @return the response as a string; nil if the operation is in progress
 */
- (NSString *)responseAsString;

/** Returns the response as a JSON object.
 *
 * @return the response as an NSDictionary or an NSArray; nil if the operation is in progress or the response is not valid JSON
 */
- (id)responseAsJSON;

/** Returns the response as NSData.
 *
 * @return returns the response as raw data
 */
- (NSData *)responseAsData;

/** Returns the downloaded data as a UIImage.
 *
 * @return the respoonse as an image; nil if the operation is in progress or the response is not a valid image
 */
- (UIImage *)responseAsImage;

@end
