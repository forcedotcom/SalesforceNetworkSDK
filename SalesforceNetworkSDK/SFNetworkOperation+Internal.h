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
@property (nonatomic, strong) MKNetworkOperation *internalOperation;
@property (nonatomic, strong) NSMutableArray *cancelBlocks;

- (id)initWithOperation:(MKNetworkOperation *)operation;
- (void)callDelegateDidFinish:(MKNetworkOperation *)operation;
- (void)callDelegateDidFailWithError:(NSError *)error;
- (NSError *)checkForErrorInResponse:(MKNetworkOperation *)operation;
@end

