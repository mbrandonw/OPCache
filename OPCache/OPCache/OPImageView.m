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
@property (nonatomic, strong, readwrite) NSString *imageURL;
@property (nonatomic, strong) UIImageView *placeholderImageView;
@end

@implementation OPImageView

-(void) cancel {
    [[OPCache sharedCache] cancelFetchForHandle:self.cancelHandle];
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
    
    self.image = nil;
    self.imageURL = url;
    [self cancel];
    if (placeholder) {
        self.placeholderImageView.image = placeholder;
        self.placeholderImageView.alpha = 1.0f;
    } else {
        _placeholderImageView.image = nil;
    }
    
    self.cancelHandle = [[OPCache sharedCache] fetchImageForURL:url cacheName:cacheName processing:processing completion:^(UIImage *image, BOOL fromCache) {
        
        self.image = image;
        [self setNeedsLayout];
        [self.superview setNeedsLayout];
        self.cancelHandle = nil;
        
        if (completion) {
            completion(image, fromCache);
        }
        
        if (placeholder) {
            _placeholderImageView.alpha = 1.0f;
        } else {
            self.alpha = 0.0f;
        }
        [UIView animateWithDuration:0.3f*(!fromCache)*(self.animation == OPImageViewAnimationFade) animations:^{
            if (placeholder) {
                _placeholderImageView.alpha = 0.0f;
            } else {
                self.alpha = 1.0f;
            }
        }];
    }];
}

-(void) didMoveToWindow {
    if (! self.window) {
        [self cancel];
    }
}

-(UIImageView*) placeholderImageView {
    if (! _placeholderImageView)
    {
        self.placeholderImageView = [UIImageView new];
        self.placeholderImageView.frame = self.bounds;
        self.placeholderImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.placeholderImageView];
    }
    return _placeholderImageView;
}

@end
