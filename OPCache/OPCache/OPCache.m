//
//  OPCache.m
//  OPCache
//
//  Created by Brandon Williams on 1/26/12.
//  Copyright (c) 2012 Opetopic. All rights reserved.
//

#import "OPCache.h"

#define kOPCacheDefaultCacheName    @""
#define kOPCacheOriginalKey         @"__original__"

void __opcache_dispatch_main_queue_asap(dispatch_block_t block);
void __opcache_dispatch_main_queue_asap(dispatch_block_t block) {
    if (dispatch_get_current_queue() == dispatch_get_main_queue())
        block();
    else
        dispatch_async(dispatch_get_main_queue(), block);
}

@interface OPCache (/**/)
@property (nonatomic, strong) NSOperationQueue *ioOperationQueue;
@property (nonatomic, strong) NSMutableDictionary *imageOperationsByCacheKey;
@property (nonatomic, strong) NSOperationQueue *imageOperationQueue;
@property (nonatomic, strong) NSMutableDictionary *imageOperationCompletionsByCacheKey;
-(UIImage*) diskImageFromURL:(NSString*)url;
-(UIImage*) diskImageFromURL:(NSString*)url cacheName:(NSString*)cacheName;
-(NSString*) cacheKeyFromImageURL:(NSString*)url;
-(NSString*) cacheKeyFromImageURL:(NSString*)url cacheName:(NSString*)cacheName;
-(NSString*) cachePathForImageURL:(NSString*)url;
-(NSString*) cachePathForImageURL:(NSString*)url cacheName:(NSString*)cacheName;
-(void) cancelFetchForURL:(NSString*)url;
-(void) cancelFetchForURL:(NSString*)url cacheName:(NSString*)cacheName;
-(void) cleanUpPersistedImages;
@end

@implementation OPCache

@synthesize imagesPersistToDisk = _imagesPersistToDisk;
@synthesize imagePersistencePath = _imagePersistencePath;
@synthesize imagePersistenceTimeInterval = _imagePersistenceTimeInterval;
@synthesize ioOperationQueue = _ioOperationQueue;
@synthesize imageOperationsByCacheKey = _imageOperationsByCacheKey;
@synthesize imageOperationQueue = _imageOperationQueue;
@synthesize imageOperationCompletionsByCacheKey = _imageOperationCompletionsByCacheKey;

+(id) sharedCache {
    static OPCache *__sharedCache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        __sharedCache = [[[self class] alloc] init];
    });
    return __sharedCache;
}

-(id) init {
    if (! (self = [super init]))
        return nil;
    
    self.imagePersistencePath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] 
                                 stringByAppendingPathComponent:@"OPCache"];
    self.imagesPersistToDisk = YES;
    self.imagePersistenceTimeInterval = 60.0f * 60.0f * 24.0f * 14.0f; // 2 weeks of disk persistence
    self.ioOperationQueue = [NSOperationQueue new];
    self.ioOperationQueue.maxConcurrentOperationCount = 1;
    self.imageOperationsByCacheKey = [NSMutableDictionary new];
    self.imageOperationQueue = [NSOperationQueue new];
    self.imageOperationQueue.maxConcurrentOperationCount = 4;
    self.imageOperationCompletionsByCacheKey = [NSMutableDictionary new];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cleanUpPersistedImages) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    return self;
}

-(void) fetchImageForURL:(NSString*)url completion:(void(^)(UIImage *image, BOOL isCached))completion {
    [self fetchImageForURL:url cacheName:kOPCacheDefaultCacheName processing:nil completion:completion];
}

-(void) fetchImageForURL:(NSString *)url cacheName:(NSString *)cacheName processing:(UIImage *(^)(UIImage *))processing completion:(void (^)(UIImage *, BOOL))completion {
    
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    
    if (! [self.imageOperationCompletionsByCacheKey objectForKey:cacheKey])
        [self.imageOperationCompletionsByCacheKey setObject:[NSMutableArray new] forKey:cacheKey];
    [[self.imageOperationCompletionsByCacheKey objectForKey:cacheKey] addObject:[completion copy]];
    
    // check if image is cached in memory
    id retVal = [self objectForKey:cacheKey];
    if (retVal)
    {
        // call the completion handler on the main thread
        if (completion) {
            __opcache_dispatch_main_queue_asap(^{
                completion(retVal, YES);
            });
        }
    }
    else
    {
        // check if image is cached on disk
        retVal = [self diskImageFromURL:url cacheName:cacheName];
        if (retVal)
        {
            // call the completion handler on the main thread
            [self setObject:retVal forKey:cacheKey];
            if (completion) {
                __opcache_dispatch_main_queue_asap(^{
                    completion(retVal, YES);
                });
            }
        }
        else
        {
            // if there is already an operation running for this image, there's nothing to do. we can just wait till it's done
            if ([self.imageOperationsByCacheKey objectForKey:cacheKey])
                return ;
            
            NSBlockOperation *operation = [NSBlockOperation new];
            [operation addExecutionBlock:^{
                
                // grab the image data from the url
                NSData *data = [[NSData alloc] initWithContentsOfFile:[self cachePathForImageURL:url cacheName:kOPCacheOriginalKey]];
                if (! data)
                    data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
                
                // turn the data into an image
                UIImage *image = [[UIImage alloc] initWithData:data];
                
                // process the image if needed
                if (processing)
                    image = processing(image);
                
                // call the completion handler on the main thread
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        // call all of the completion handlers associated with this operation
                        for (OPCacheImageCompletion block in [self.imageOperationCompletionsByCacheKey objectForKey:cacheKey])
                            block(image, NO);
                        
                        // clean up cache dictionaries
                        [self.imageOperationsByCacheKey removeObjectForKey:cacheKey];
                        [self.imageOperationCompletionsByCacheKey removeObjectForKey:cacheKey];
                    });
                }
                
                // write the image to disk if needed
                if (self.imagesPersistToDisk)
                {
                    [self.ioOperationQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
                        
                        [data writeToFile:[self cachePathForImageURL:url cacheName:kOPCacheOriginalKey] atomically:YES];
                        [(NSData*)(processing?UIImagePNGRepresentation(image):data) writeToFile:[self cachePathForImageURL:url cacheName:cacheName] 
                                                                                      atomically:YES];
                    }]];
                }
                
            }];
            operation.threadPriority = 0.1f;
            [self.imageOperationQueue addOperation:operation];
            [self.imageOperationsByCacheKey setObject:operation forKey:cacheKey];
        }
    }
}

-(UIImage*) cachedImageForURL:(NSString*)url {
    return [self cachedImageForURL:url cacheName:kOPCacheDefaultCacheName];
}

-(UIImage*) cachedImageForURL:(NSString*)url cacheName:(NSString *)cacheName {
    
    // first try finding the image in memory cache
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    id retVal = [self objectForKey:cacheKey];
    if (retVal)
    {
        return retVal;
    }
    else
    {
        // then trying reviving the image from disk cache
        retVal = [self diskImageFromURL:url cacheName:cacheName];
        if (retVal)
        {
            return retVal;
        }
    }
    return nil;
}

-(void) setImagePersistencePath:(NSString *)imagePersistencePath {
    _imagePersistencePath = imagePersistencePath;
    [[NSFileManager defaultManager] createDirectoryAtPath:imagePersistencePath withIntermediateDirectories:YES attributes:nil error:NULL];
}

-(UIImage*) diskImageFromURL:(NSString*)url {
    return [self diskImageFromURL:url cacheName:kOPCacheDefaultCacheName];
}

-(UIImage*) diskImageFromURL:(NSString*)url cacheName:(NSString*)cacheName {
    NSData *data = [[NSData alloc] initWithContentsOfFile:[self cachePathForImageURL:url cacheName:cacheName]];
    return [[UIImage alloc] initWithData:data];
}

-(NSString*) cacheKeyFromImageURL:(NSString*)url {
    return [self cacheKeyFromImageURL:url cacheName:kOPCacheDefaultCacheName];
}

-(NSString*) cacheKeyFromImageURL:(NSString*)url cacheName:(NSString*)cacheName {
    return [[NSString alloc] initWithFormat:@"OPCache-%@-%u", cacheName?cacheName:kOPCacheDefaultCacheName, [url hash]];
}

-(NSString*) cachePathForImageURL:(NSString*)url {
    return [self cachePathForImageURL:url cacheName:kOPCacheDefaultCacheName];
}

-(NSString*) cachePathForImageURL:(NSString*)url cacheName:(NSString*)cacheName {
    return [self.imagePersistencePath stringByAppendingPathComponent:[self cacheKeyFromImageURL:url cacheName:cacheName]];
}

-(void) removeImageForURL:(NSString*)url {
    [self removeImageForURL:url cacheName:kOPCacheDefaultCacheName];
}

-(void) removeAllImagesForURL:(NSString*)url {
    
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:self.imagePersistencePath];
    NSString *file = nil;
    while (file = [enumerator nextObject])
    {
        if ([file hasSuffix:[NSString stringWithFormat:@"%u", [url hash]]])
        {
            NSString *cacheName = [[file componentsSeparatedByString:@"-"] objectAtIndex:1];
            [self removeImageForURL:url cacheName:cacheName];
        }
    }
}

-(void) removeImageForURL:(NSString*)url cacheName:(NSString*)cacheName {
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    [self removeObjectForKey:cacheKey];
    [[NSFileManager defaultManager] removeItemAtPath:[self cachePathForImageURL:url cacheName:cacheName] error:NULL];
}

-(void) cancelFetchForURL:(NSString*)url {
    [self cancelFetchForURL:url cacheName:kOPCacheDefaultCacheName];
}

-(void) cancelFetchForURL:(NSString*)url cacheName:(NSString*)cacheName {
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    [(NSOperation*)[self.imageOperationsByCacheKey objectForKey:cacheKey] cancel];
    [self.imageOperationsByCacheKey removeObjectForKey:cacheKey];
}

-(void) cleanUpPersistedImages {
    
    // clean up the old image files in the IO queue, and let the OS know this may take some time.
    UIBackgroundTaskIdentifier taskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
    [self.ioOperationQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-self.imagePersistenceTimeInterval];
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:self.imagePersistencePath];
        NSString *file = nil;
        while (file = [enumerator nextObject])
        {
            NSString *filePath = [self.imagePersistencePath stringByAppendingPathComponent:file];
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL];
            if ([cutoff compare:[attributes objectForKey:NSFileModificationDate]] == NSOrderedDescending)
            {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
            }
        }
        
        [[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
    }]];
}

+(UIImage*(^)(UIImage *image)) resizeProcessingBlock:(CGSize)size {
    
    return [(UIImage*)^(UIImage *image){
        
        CGFloat sourceWidth = image.size.width;
        CGFloat sourceHeight = image.size.height;
        CGFloat targetWidth = size.width;
        CGFloat targetHeight = size.height;
        CGFloat sourceRatio = sourceWidth / sourceHeight;
        CGFloat targetRatio = targetWidth / targetHeight;
        BOOL scaleWidth = sourceRatio <= targetRatio;
        
        CGFloat scalingFactor, scaledWidth, scaledHeight;
        if (scaleWidth)
        {
            scalingFactor = 1.0f / sourceRatio;
            scaledWidth = targetWidth;
            scaledHeight = roundf(targetWidth * scalingFactor);
        }
        else
        {
            scalingFactor = sourceRatio;
            scaledWidth = roundf(targetHeight * scalingFactor);
            scaledHeight = targetHeight;
        }
        CGFloat scaleFactor = scaledHeight / sourceHeight;
        
        CGRect sourceRect = CGRectMake(roundf(scaledWidth-targetWidth)/2.0f/scaleFactor, (scaledHeight-targetHeight)/2.0f/scaleFactor, 
                                       targetWidth/scaleFactor, targetHeight/scaleFactor);
        
        UIImage *newImage = nil;
        UIGraphicsBeginImageContextWithOptions(size, NO, 1.0f);
        {
            CGImageRef sourceImageRef = CGImageCreateWithImageInRect(image.CGImage, sourceRect);
            newImage = [UIImage imageWithCGImage:sourceImageRef scale:1.0f orientation:image.imageOrientation];
            [newImage drawInRect:CGRectMake(0.0f, 0.0f, targetWidth, targetHeight)];
            newImage = UIGraphicsGetImageFromCurrentImageContext();
        }
        UIGraphicsEndImageContext();
        return newImage;
        
    } copy];
}

@end
