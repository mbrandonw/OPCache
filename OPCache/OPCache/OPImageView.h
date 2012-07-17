//
//  OPImageView.h
//  OPUIKit
//
//  Created by Brandon Williams on 2/10/12.
//  Copyright (c) 2012 Opetopic. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef enum {
    OPImageViewAnimationNone,
    OPImageViewAnimationFade,
} OPImageViewAnimation;

@interface OPImageView : UIImageView

@property (nonatomic, assign) OPImageViewAnimation animation;

-(void) cancel;

-(void) loadImageURL:(NSString*)url;
-(void) loadImageURL:(NSString*)url placeholder:(UIImage*)placeholder;
-(void) loadImageURL:(NSString*)url placeholder:(UIImage*)placeholder cacheName:(NSString*)cacheName processing:(UIImage*(^)(UIImage *image))processing;

@end
