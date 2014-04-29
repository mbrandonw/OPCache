//
//  OPImageView.m
//  OPUIKit
//
//  Created by Brandon Williams on 2/10/12.
//  Copyright (c) 2012 Opetopic. All rights reserved.
//

#import "OPImageView.h"
#import "OPCache.h"
#import <sys/sysctl.h>

@interface OPImageView (/**/)
@property (nonatomic, weak) id<OPCacheCancelable> cancelHandle;
@property (nonatomic, strong, readwrite) NSString *imageURL;
@property (nonatomic, strong) UIImageView *placeholderImageView;
-(BOOL) deviceIsFast;
@end

@implementation OPImageView

-(id) initWithFrame:(CGRect)frame {
  if (! (self = [super initWithFrame:frame])) {
    return nil;
  }

  self.animation = OPImageViewAnimationAuto;

  return self;
}

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

  [self.cancelHandle cancel];
  self.cancelHandle = [[OPCache sharedCache] fetchImageForURL:url cacheName:cacheName processing:processing completion:^(UIImage *image, BOOL fromCache) {

    self.image = image;
    self.cancelHandle = nil;

    if (completion) {
      completion(image, fromCache);
    }

    if (placeholder) {
      _placeholderImageView.alpha = 1.0f;
    } else {
      self.alpha = 0.0f;
    }
    BOOL animate = self.animation == OPImageViewAnimationFade || (self.animation == OPImageViewAnimationAuto && [self deviceIsFast]);
    [UIView animateWithDuration:0.3f*(!fromCache)*animate animations:^{
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
  if (! _placeholderImageView) {
    self.placeholderImageView = [[UIImageView alloc] initWithFrame:self.bounds];
    self.placeholderImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.placeholderImageView];
  }
  return _placeholderImageView;
}

-(UIImage*) image {
  return super.image ?: _placeholderImageView.image;
}

-(BOOL) deviceIsFast {
  static NSInteger fastFlag = -1;
  if (fastFlag >= 0) {
    return fastFlag == 1;
  }

#if TARGET_IPHONE_SIMULATOR
  fastFlag = 1;
  return YES;
#endif

  size_t size;
  sysctlbyname("hw.machine", NULL, &size, NULL, 0);
  char *answer = malloc(size);
  sysctlbyname("hw.machine", answer, &size, NULL, 0);
  NSString *platform = [NSString stringWithCString:answer encoding: NSUTF8StringEncoding];
  free(answer);

  if ([platform hasPrefix:@"iPhone"]) {
    fastFlag = [platform compare:@"iPhone4"] == NSOrderedDescending ? 1 : 0;
  } else if ([platform hasPrefix:@"iPod"]) {
    fastFlag = [platform compare:@"iPod5"] == NSOrderedDescending ? 1 : 0;
  } else if ([platform hasPrefix:@"iPad"]) {
    fastFlag = [platform compare:@"iPad2"] == NSOrderedDescending ? 1 : 0;
  } else {
    fastFlag = 1;
  }
  return fastFlag == 1;
}

@end
