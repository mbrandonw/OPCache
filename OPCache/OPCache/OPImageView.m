//
//  OPImageView.m
//  OPUIKit
//
//  Created by Brandon Williams on 2/10/12.
//  Copyright (c) 2012 Opetopic. All rights reserved.
//

#import "OPImageView.h"
#import "OPCache.h"

@interface OPImageView (/**/)
@property (nonatomic, weak) id<OPCacheCancelable> cancelHandle;
@end

@implementation OPImageView

@synthesize animation = _animation;
@synthesize cancelHandle = _cancelHandle;

-(void) cancel {
    [[OPCache sharedCache] cancelFetchForHandle:self.cancelHandle];
    self.cancelHandle = nil;
    self.image = nil;
}

-(void) loadImageURL:(NSString*)url {
    [self loadImageURL:url placeholder:nil];
}

-(void) loadImageURL:(NSString*)url placeholder:(UIImage*)placeholder {
    [self loadImageURL:url placeholder:placeholder cacheName:nil processing:nil];
}

-(void) loadImageURL:(NSString*)url placeholder:(UIImage*)placeholder cacheName:(NSString*)cacheName processing:(UIImage*(^)(UIImage *image))processing {
    [self loadImageURL:url placeholder:placeholder cacheName:cacheName processing:processing completion:nil];
}

-(void) loadImageURL:(NSString*)url 
         placeholder:(UIImage*)placeholder 
           cacheName:(NSString*)cacheName 
          processing:(UIImage*(^)(UIImage *image))processing
          completion:(OPCacheImageCompletionBlock)completion {
    
    [self cancel];
    self.image = placeholder;
    
    self.cancelHandle = [[OPCache sharedCache] fetchImageForURL:url cacheName:cacheName processing:processing completion:^(UIImage *image, BOOL fromCache) {
        
        self.image = image;
        [self setNeedsLayout];
        [self.superview setNeedsLayout];
        self.cancelHandle = nil;
        
        if (completion)
            completion(image, fromCache);
        
        self.alpha = 0.0f;
        [UIView animateWithDuration:0.3f*(!fromCache)*(self.animation == OPImageViewAnimationFade) animations:^{
            self.alpha = 1.0f;
        }];
    }];
}

-(void) didMoveToWindow {
    if (! self.window)
        [self cancel];
}

@end
