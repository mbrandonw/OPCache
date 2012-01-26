//
//  OPCache.h
//  Kickstarter
//
//  Created by Brandon Williams on 1/26/12.
//  Copyright (c) 2012 Kickstarter. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OPCache : NSCache

@property (nonatomic, assign) BOOL imagesPersistToDisk;
@property (nonatomic, strong) NSString *imagePersistencePath;

+(id) sharedCache;

-(void) fetchImageForURL:(NSString*)url completion:(void(^)(UIImage *image, BOOL isCached))completion;
-(void) fetchImageForURL:(NSString*)url 
               cacheName:(NSString*)cacheName 
              processing:(UIImage*(^)(UIImage *image))processing
              completion:(void(^)(UIImage *image, BOOL isCached))completion;

-(void) removeImageForURL:(NSString*)url;
-(void) removeAllImagesForURL:(NSString*)url;
-(void) removeImageForURL:(NSString*)url cacheName:(NSString*)cacheName;

-(void) cancelFetchForURL:(NSString*)url;
-(void) cancelFetchForURL:(NSString*)url cacheName:(NSString*)cacheName;

@end
