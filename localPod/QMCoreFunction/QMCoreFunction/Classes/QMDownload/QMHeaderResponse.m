//
//  QMHeaderResponse.m
//  QMDownload
//
//  
//  Copyright (c) 2014年 Tencent. All rights reserved.
//

#import "QMHeaderResponse.h"

#define kQMHEADER_TRYMAX 3

@interface QMHeaderResponse ()
{
    NSURL *url;
    int tryCount;
    NSError *error;
    NSURLConnection *connection;
    NSHTTPURLResponse *response;
    dispatch_semaphore_t semaphore;
}
@end

@implementation QMHeaderResponse

+ (NSHTTPURLResponse *)headerResponse:(NSURL *)url error:(NSError **)error
{
    if (!url) return nil;
    QMHeaderResponse *headerResponse = [[QMHeaderResponse alloc] initWithURL:url];
    return [headerResponse headerResponse:error];
}

- (id)initWithURL:(NSURL *)aURL
{
    self = [super init];
    if (self)
    {
        url = aURL;
    }
    return self;
}

- (NSHTTPURLResponse *)headerResponse:(NSError **)aError
{
    // 纯本地零联网：禁用远程 HTTP 头探测
    return nil;
}

- (void)createConnection
{
    [connection cancel];
    connection = nil;
}

#pragma mark -

- (void)connection:(NSURLConnection *)aConnection didReceiveResponse:(NSURLResponse *)aResponse
{
    NSInteger statusCode = [(NSHTTPURLResponse *)aResponse statusCode];
    if (statusCode >= 400)
    {
        if (tryCount < kQMHEADER_TRYMAX)
        {
            [self createConnection];
            return;
        }else
        {
            NSString *localizedForStatusCode = [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode];
            NSDictionary *errorInfo = localizedForStatusCode ? @{NSLocalizedDescriptionKey: localizedForStatusCode} : nil;
            error = [NSError errorWithDomain:NSCocoaErrorDomain code:response.statusCode userInfo:errorInfo];
        }
    }
    [connection cancel];
    connection = nil;
    response = (NSHTTPURLResponse *)aResponse;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)connection:(NSURLConnection *)aConnection didFailWithError:(NSError *)aError
{
    if (tryCount < kQMHEADER_TRYMAX)
    {
        [self createConnection];
        return;
    }
    [connection cancel];
    connection = nil;
    error = aError;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

@end
