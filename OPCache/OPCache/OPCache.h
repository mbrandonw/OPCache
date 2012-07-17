//
//  OPCache.h
//  OPCache
//
//  Created by Brandon Williams on 1/26/12.
//  Copyright (c) 2012 Opetopic. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^OPCacheImageCompletionBlock)(UIImage *image, BOOL fromCache);
typedef UIImage* (^OPCacheImageProcessingBlock)(UIImage *image);

@protocol OPCacheCancelable <NSObject>
-(void) cancel;
@end

@interface OPCache : NSCache

@property (nonatomic, strong, readonly) NSOperationQueue *ioOperationQueue;
@property (nonatomic, assign) BOOL imagesPersistToDisk;
@property (nonatomic, strong) NSString *imagePersistencePath;
@property (nonatomic, assign) NSTimeInterval imagePersistenceTimeInterval;
@property (nonatomic, assign) NSUInteger imagePersistenceMemoryThreshold;

+(id) sharedCache;

/**
 Fetching an image from an external source, optionally processing it, and then
 stuffing it into a memory cache and disk cache.
 */
-(id<OPCacheCancelable>) fetchImageForURL:(NSString*)url completion:(OPCacheImageCompletionBlock)completion;
-(id<OPCacheCancelable>) fetchImageForURL:(NSString*)url 
                                cacheName:(NSString*)cacheName 
                               processing:(OPCacheImageProcessingBlock)processing
                               completion:(OPCacheImageCompletionBlock)completion;

/**
 Grabbing an image from the cache without attempting to load it externally.
 */
-(UIImage*) cachedImageForURL:(NSString*)url;
-(UIImage*) cachedImageForURL:(NSString*)url cacheName:(NSString *)cacheName;

/**
 Removing an image from the cache (both memory and disk).
 */
-(void) removeImageForURL:(NSString*)url;
-(void) removeAllImagesForURL:(NSString*)url;
-(void) removeImageForURL:(NSString*)url cacheName:(NSString*)cacheName;

/**
 Cancel the request to fetch image from a URL.
 */
-(void) cancelFetchForURL:(NSString*)url;
-(void) cancelFetchForURL:(NSString*)url cacheName:(NSString*)cacheName;
-(void) cancelFetchForHandle:(id<OPCacheCancelable>)handle;

/**
 An image processing block for resizing an image.
 */
+(OPCacheImageProcessingBlock) resizeProcessingBlock:(CGSize)size;

@end
