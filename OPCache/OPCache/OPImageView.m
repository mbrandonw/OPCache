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
    [self.cancelHandle cancel];
    self.cancelHandle = nil;
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
    
    [self.cancelHandle cancel];
    
    self.image = placeholder;
    
    [[OPCache sharedCache] fetchImageForURL:url cacheName:cacheName processing:processing completion:^(UIImage *image, BOOL fromCache) {
        
        self.image = image;
        [self setNeedsLayout];
        [self.superview setNeedsLayout];
        
        if (completion)
            completion(image, fromCache);
        
        self.alpha = 0.0f;
        [UIView animateWithDuration:0.3f*(!fromCache)*(self.animation == OPImageViewAnimationFade) animations:^{
            self.alpha = 1.0f;
        }];
    }];
}

@end
