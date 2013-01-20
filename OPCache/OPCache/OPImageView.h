//
//  OPImageView.h
//  OPUIKit
//
//  Created by Brandon Williams on 2/10/12.
//  Copyright (c) 2012 Opetopic. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "OPCache.h"

typedef enum {
    OPImageViewAnimationNone,
    OPImageViewAnimationFade,
    OPImageViewAnimationAuto,
} OPImageViewAnimation;

@interface OPImageView : UIImageView

@property (nonatomic, assign) OPImageViewAnimation animation;
@property (nonatomic, strong, readonly) NSString *imageURL;

-(void) cancel;

-(void) loadImageURL:(NSString*)url;
-(void) loadImageURL:(NSString*)url placeholder:(UIImage*)placeholder;
-(void) loadImageURL:(NSString*)url 
         placeholder:(UIImage*)placeholder 
           cacheName:(NSString*)cacheName 
          processing:(UIImage*(^)(UIImage *image))processing;
-(void) loadImageURL:(NSString*)url 
         placeholder:(UIImage*)placeholder 
           cacheName:(NSString*)cacheName 
          processing:(UIImage*(^)(UIImage *image))processing
          completion:(OPCacheImageCompletionBlock)completion;

@end
