//
//  OPCache.m
//  OPCache
//
//  Created by Brandon Williams on 1/26/12.
//  Copyright (c) 2012 Opetopic. All rights reserved.
//

#import "OPCache.h"

#define kOPCacheDefaultCacheName    @""

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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cleanUpPersistedImages) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    return self;
}

-(void) fetchImageForURL:(NSString*)url completion:(void(^)(UIImage *image, BOOL isCached))completion {
    [self fetchImageForURL:url cacheName:kOPCacheDefaultCacheName processing:nil completion:completion];
}

-(void) fetchImageForURL:(NSString *)url cacheName:(NSString *)cacheName processing:(UIImage *(^)(UIImage *))processing completion:(void (^)(UIImage *, BOOL))completion {
    
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
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
            NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
                
                // grab the image from the url and process it if necessary
                NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
                UIImage *image = [[UIImage alloc] initWithData:data];
                if (processing)
                    image = processing(image);
                
                // call the completion handler on the main thread
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(image, NO);
                        [self.imageOperationsByCacheKey removeObjectForKey:cacheKey];
                    });
                }
                
                // write the image to disk if needed
                if (self.imagesPersistToDisk) {
                    [self.ioOperationQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
                        [(NSData*)(processing?UIImagePNGRepresentation(image):image) writeToFile:[self cachePathForImageURL:url cacheName:cacheName] 
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
    [(NSOperation*)[self.imageOperationsByCacheKey objectForKey:cacheName] cancel];
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
        
        UIGraphicsBeginImageContext(size);
        [image drawInRect:CGRectMake(0.0f, 0.0f, size.width, size.height)];
        UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return newImage;
        
    } copy];
}

@end
