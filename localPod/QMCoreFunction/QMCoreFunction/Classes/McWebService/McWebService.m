//
//  McWebService.m
//  UserSystem
//
//  
//  Copyright (c) 2012 Magican Software Ltd. All rights reserved.
//

#import "McWebService.h"
#import "McWebDefine.h"

@implementation McWebService
@synthesize delegate=_delegate;
@synthesize url=_url;
@synthesize timeoutInterval=_timeoutInterval;
@synthesize webServiceBlock;

+ (NSData *)dataWithURL:(NSURL *)url
{
    McWebService *service = [[[self class] alloc] init];
    service.url = url;
    return [service startSynchronous];
}

+ (void)serviceWithURL:(NSURL *)url handler:(McWebServiceBlock)block
{
    McWebService *service = [[[self class] alloc] init];
    service.url = url;
    [service startWithHandler:block];
}

- (id)init
{
    self = [super init];
    if (self) {
        _timeoutInterval = kMcWebServiceTimeoutInterval;
    }
    return self;
}

- (void)stop
{
    [_con cancel];
    _con = nil;
}

- (NSURLRequest *)setUpRequest:(NSError **)error
{
    // 纯本地零联网：禁用底层 HTTP 请求构造
    if (error)
    {
        *error = [NSError errorWithDomain:NSStringFromClass(self.class)
                                     code:kMcWebServiceErrorCodeURLBad
                                 userInfo:@{NSLocalizedDescriptionKey:@"Network disabled in offline mode"}];
    }
    return nil;
}

- (BOOL)startAsynchronous
{
    [self stop];
    NSError *error = nil;
    [self setUpRequest:&error];
    if ([_delegate respondsToSelector:@selector(webServiceFail:didFailWithError:)])
    {
        [_delegate webServiceFail:self didFailWithError:error];
    }
    return NO;
}

- (NSData *)startSynchronous
{
    [self stop];
    return nil;
}

- (void)startWithHandler:(McWebServiceBlock)block
{
    [self stop];
    self.webServiceBlock = block;
    if (self.webServiceBlock)
    {
        NSError *error = nil;
        [self setUpRequest:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.webServiceBlock(nil, error, nil);
        });
    }
}

#pragma mark -
#pragma mark NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	if ([_delegate respondsToSelector:@selector(webServiceBegin:)])
    {
		[_delegate webServiceBegin:self];
	}
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)aData
{
    if(_con!=nil)
    {
	    [_data appendData:aData];
	}
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    if ([_delegate respondsToSelector:@selector(webServiceFail:didFailWithError:)])
    {
		[_delegate webServiceFail:self didFailWithError:error];
	}
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if ([_delegate respondsToSelector:@selector(webServiceFinish:didReceiveData:)])
    {
		[_delegate webServiceFinish:self didReceiveData:_data];
	}
}

@end
