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

/**Set custom tag on `SFNetworkOperation`
 
Tag can be used to categorize `SFNetworkOperation` and used together with `[SFNetworkEngine hasPendingOperationsWithTag]`
 */
@property (nonatomic, strong) NSString *tag;
@property (nonatomic, readonly) NSString *url;
@property (nonatomic, assign) NSUInteger expectedDownloadSize;

@property (nonatomic, readonly, strong) NSError *error;
@property (nonatomic, readonly, assign) NSInteger statusCode;
@property (nonatomic, readonly, strong) NSString *uniqueIdentifier;

/**Delegate can be used to monitor operation status (complete, error, cancel or timeout) in lieu of using blocks
 */
@property (nonatomic, weak) id <SFNetworkOperationDelegate> delegate;

/**Set to YES if want to encrypt downloaded content. Default value is YES*/
@property (nonatomic, assign) BOOL encryptDownloadedFile;

/**Set to YES if want operation requires access token. Default value is YES*/
@property (nonatomic, assign) BOOL requiresAccessToken;

/** Custom HTTP headers that will be used by this operation
 
 @param customHeaders Value specified by this parameter will override value set by `[SFNetworkEngine customHeaders]`
 */
- (void)customHeaders:(NSDictionary *)customHeaders;

///---------------------------------------------------------------
/// @name Upload and Download Methods
///---------------------------------------------------------------
/**Set path for the download file 
 
 @param downloadFilePath Path to store downloaded content. If this value is set and `encryptDownloadedFile` is set to true, all content downloaded by this operation will be encrypted and stored in the file specified by the path
 */
- (void)downloadFile:(NSString *)downloadFilePath;

/**  Attach a file data as multi-form post data to this operation
 
 This method can be used to upload binary file. A multi-part form data will be constructured based on the value passed in with format
 
 Content-Disposition: form-data; name=`name`; filename=`fileName` (if name is not nil)
 Content-Disposition: form-data; filename=`fileName` (if name is nil)
 Content-Type: `mimeType`
 `fileData`
 
 @param fileData File raw data
 @param paramName Parameter name to be used in the multi-part form data for this file. Nil is accepted
 @param fileName File name to be used in the multi-part form data for this file
 @param mimeType File mimetype. Nil is accpeted. If nil is passed, 'multipart/form-data' will be used by default as the mimetype. Server side will use the fileName to figure out the proper mimetype for the file
 */
-(void)addPostFileData:(NSData *)fileData paramName:(NSString *)paramName fileName:(NSString *)fileName mimeType:(NSString *)mimeType;

///---------------------------------------------------------------
/// @name Block Methods
///---------------------------------------------------------------
/** Add block Handler for completion, error and cancel
 
 An operation can have multiple completion, error and cancel blocks attached to it. Upon completion, error or error, each registered block will be executed
 @param completionBlock Completion block to be invoked when operation is completed successfully
 @param errorBlock Error block to be invoked when operation errors out
 @param cancelBlock Cancel block to be invoked when operation is canceld
 @param callOnMainThread Set to YES to run block call block on main thread
 */
- (void)onCompletion:(SFNetworkOperationCompletionBlock)completionBlock onError:(SFNetworkOperationErrorBlock)errorBlock onCancel:(SFNetworkOperationCancelBlock)cancelBlock callOnMainThread:(BOOL)callOnMainThread;

/** Add Block Handler for tracking upload progress
 
 An operation can have multiple upload progress blocks and error blocks attached to it. Upon upload progress change, each uploadProgressBlock will be executed
 @param uploadProgressBlock Block to be invoked when upload progress is changed
 @param callOnMainThread Set to YES to run block call block on main thread
 */
- (void)onUploadProgressChanged:(SFNetworkOperationProgressBlock)uploadProgressBlock callOnMainThread:(BOOL)callOnMainThread;

/** Add Block Handler for tracking download progress
 
 An operation can have multiple download progress blocks and error blocks attached to it. Upon upload progress change, each downloadProgressBlock will be executed
 @param downloadProgressBlock Block to be invoked when download progress is changed
 @param callOnMainThread Set to YES to run block call block on main thread
 */
- (void)onDownloadProgressChanged:(SFNetworkOperationProgressBlock)downloadProgressBlock callOnMainThread:(BOOL)callOnMainThread;


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
