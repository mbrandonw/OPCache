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

  self.imageURL = url;
  self.image = placeholder;

  [self.cancelHandle cancel];
  self.cancelHandle = [[OPCache sharedCache] fetchImageForURL:url cacheName:cacheName processing:processing completion:^(UIImage *image, BOOL fromCache) {

    self.cancelHandle = nil;

    if (completion) {
      completion(image, fromCache);
    }

    BOOL animate = self.animation == OPImageViewAnimationFade || (self.animation == OPImageViewAnimationAuto && [self deviceIsFast]);

    [UIView transitionWithView:self duration:0.3 * (!fromCache && animate) options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
      self.image = image;
    } completion:nil];
  }];
}

-(void) didMoveToWindow {
  [super didMoveToWindow];
  
  if (! self.window) {
    [self cancel];
  }
}

-(BOOL) deviceIsFast {
  static NSInteger fastFlag = -1;
  if (fastFlag >= 0) {
    return fastFlag == 1;
  }

#if TARGET_IPHONE_SIMULATOR
  fastFlag = 1;
  return YES;
#else
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
#endif
}

@end
