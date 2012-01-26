//
//  OPCache.h
//  OPCache
//
//  Created by Brandon Williams on 1/26/12.
//  Copyright (c) 2012 Opetopic. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OPCache : NSCache

@property (nonatomic, assign) BOOL imagesPersistToDisk;
@property (nonatomic, strong) NSString *imagePersistencePath;
@property (nonatomic, assign) NSTimeInterval imagePersistenceTimeInterval;

+(id) sharedCache;

-(void) fetchImageForURL:(NSString*)url completion:(void(^)(UIImage *image, BOOL isCached))completion;
-(void) fetchImageForURL:(NSString*)url 
               cacheName:(NSString*)cacheName 
              processing:(UIImage*(^)(UIImage *image))processing
              completion:(void(^)(UIImage *image, BOOL isCached))completion;

-(UIImage*) cachedImageForURL:(NSString*)url;
-(UIImage*) cachedImageForURL:(NSString*)url cacheName:(NSString *)cacheName;

-(void) removeImageForURL:(NSString*)url;
-(void) removeAllImagesForURL:(NSString*)url;
-(void) removeImageForURL:(NSString*)url cacheName:(NSString*)cacheName;

/**
 Cancel the request to fetch image from a URL.
 */
-(void) cancelFetchForURL:(NSString*)url;
-(void) cancelFetchForURL:(NSString*)url cacheName:(NSString*)cacheName;

/**
 An image processing block for resizing an image.
 */
+(UIImage*(^)(UIImage *image)) resizeProcessingBlock:(CGSize)size;

@end
