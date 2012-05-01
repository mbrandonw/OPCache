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
@property (nonatomic, strong, readwrite) NSOperationQueue *ioOperationQueue;
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
-(void) processImage:(UIImage*)originalImage with:(OPCacheImageProcessingBlock)processing url:(NSString*)url cacheName:(NSString*)cacheName completion:(OPCacheImageCompletionBlock)completion;
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
    
    // some reasonable defaults
    
    self.imagePersistencePath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] 
                                 stringByAppendingPathComponent:@"OPCache"];
    self.imagesPersistToDisk = YES;
    self.imagePersistenceTimeInterval = 60.0f * 60.0f * 24.0f * 14.0f; // 2 weeks of disk persistence
    
    self.ioOperationQueue = [NSOperationQueue new];
    self.ioOperationQueue.maxConcurrentOperationCount = 1;
    self.imageOperationsByCacheKey = [NSMutableDictionary new];
    self.imageOperationQueue = [NSOperationQueue new];
    self.imageOperationQueue.maxConcurrentOperationCount = 8;
    
    // remove old disk cached items when app is terminated
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cleanUpPersistedImages) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    // you would think that NSCache's would be emptied when the app receives memory warnings, but apparently not.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeAllObjects) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeAllObjects) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    return self;
}

-(void) fetchImageForURL:(NSString*)url completion:(OPCacheImageCompletionBlock)completion {
    [self fetchImageForURL:url cacheName:kOPCacheDefaultCacheName processing:nil completion:completion];
}

-(void) fetchImageForURL:(NSString *)url cacheName:(NSString *)cacheName processing:(OPCacheImageProcessingBlock)processing completion:(OPCacheImageCompletionBlock)completion {
    
    // early out on bad data
    if (! url)    return ;
    
    // check if image is already cached in memory or on disk
    id retVal = [self cachedImageForURL:url cacheName:cacheName];
    if (retVal)
    {
        if (completion)
            __opcache_dispatch_main_queue_asap(^{ completion(retVal, YES); });
        return ;
    }
    
    
    // check if the original image is cached on disk so that all we have to do is process it
    UIImage *originalImage = [[UIImage alloc] initWithContentsOfFile:[self cachePathForImageURL:url cacheName:kOPCacheOriginalKey]];
    if (originalImage)
    {
        [self processImage:originalImage with:processing url:url cacheName:cacheName completion:completion];
        return ;
    }
    
    // if there is already an operation running for this image, there's nothing to do. we can just wait till it's done
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    if ([self.imageOperationsByCacheKey objectForKey:cacheKey])
        return ;
    
    // if we got this far then we gotta load something from the server. 
    
    // construct the image request operation, but don't use any caching mechanism. We handle that ourselves.
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0f];
    AFImageRequestOperation *operation = [AFImageRequestOperation imageRequestOperationWithRequest:request imageProcessingBlock:nil cacheName:nil success:^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
        if (image)
            [self processImage:image with:processing url:url cacheName:cacheName completion:completion];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
        [self.imageOperationsByCacheKey removeObjectForKey:cacheKey];
    }];
    operation.imageScale = 1.0f;
    operation.threadPriority = 0.1f;
    
    [self.imageOperationQueue addOperation:operation];
    [self.imageOperationsByCacheKey setObject:operation forKey:cacheKey];
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
            // put image into memory cache
            [self setObject:retVal forKey:cacheKey];
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
    return [[NSString alloc] initWithFormat:@"%lu-%@", [url hash], cacheName?cacheName:kOPCacheDefaultCacheName];
}

-(NSString*) cachePathForImageURL:(NSString*)url {
    return [self cachePathForImageURL:url cacheName:kOPCacheDefaultCacheName];
}

-(NSString*) cachePathForImageURL:(NSString*)url cacheName:(NSString*)cacheName {
    return [[self.imagePersistencePath stringByAppendingPathComponent:[self cacheKeyFromImageURL:url cacheName:cacheName]] stringByAppendingPathExtension:@"jpg"];
}

-(void) removeImageForURL:(NSString*)url {
    [self removeImageForURL:url cacheName:kOPCacheDefaultCacheName];
}

-(void) removeAllImagesForURL:(NSString*)url {
    
    // early out on bad data
    if (! url)    return ;
    
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:self.imagePersistencePath];
    NSString *file = nil;
    while (file = [enumerator nextObject])
    {
        if ([file hasSuffix:[NSString stringWithFormat:@"%lu", [url hash]]])
        {
            NSString *cacheName = [[file componentsSeparatedByString:@"-"] lastObject];
            if (cacheName)
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
    
    // early out on bad data
    if (! url)    return ;
    
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    [(NSOperation*)[self.imageOperationsByCacheKey objectForKey:cacheKey] cancel];
    [self.imageOperationsByCacheKey removeObjectForKey:cacheKey];
}

+(UIImage*(^)(UIImage *image)) resizeProcessingBlock:(CGSize)size {
    
    size.width *= [[UIScreen mainScreen] scale];
    size.height *= [[UIScreen mainScreen] scale];
    
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
        
        CGRect sourceRect = CGRectMake(roundf(scaledWidth-targetWidth)/2.0f/scaleFactor, 
                                       (scaledHeight-targetHeight)/2.0f/scaleFactor, 
                                       targetWidth/scaleFactor, 
                                       targetHeight/scaleFactor);
        
        UIImage *newImage = nil;
        UIGraphicsBeginImageContextWithOptions(size, YES, 1.0f);
        {
            CGImageRef sourceImageRef = CGImageCreateWithImageInRect(image.CGImage, sourceRect);
            newImage = [UIImage imageWithCGImage:sourceImageRef scale:1.0f orientation:image.imageOrientation];
            [newImage drawInRect:CGRectMake(0.0f, 0.0f, targetWidth, targetHeight)];
            newImage = UIGraphicsGetImageFromCurrentImageContext();
            CFRelease(sourceImageRef);
        }
        UIGraphicsEndImageContext();
        return newImage;
        
    } copy];
}

#pragma mark -
#pragma mark Private methods
#pragma mark -

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

-(void) processImage:(UIImage*)originalImage with:(OPCacheImageProcessingBlock)processing url:(NSString*)url cacheName:(NSString*)cacheName completion:(OPCacheImageCompletionBlock)completion {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // process the image if needed
        UIImage *image = originalImage;
        if (processing)
            image = processing(image);
        if (! image)
            return ;
        
        // stick the processed image into memory cache
        NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
        [self setObject:image forKey:cacheKey];
        
        // call all the completion blocks on the main queue
        __opcache_dispatch_main_queue_asap(^{
            
            completion(image, NO);
            [self.imageOperationsByCacheKey removeObjectForKey:cacheKey];
        });
        
        // save the image data to the disk
        if (self.imagesPersistToDisk)
        {
            NSBlockOperation *ioOperation = [NSBlockOperation blockOperationWithBlock:^{
                
                // cache the original image
                NSString *originalFilePath = [self cachePathForImageURL:url cacheName:kOPCacheOriginalKey];
                if (! [[NSFileManager defaultManager] fileExistsAtPath:originalFilePath])
                    [UIImageJPEGRepresentation(originalImage, 0.9f) writeToFile:originalFilePath atomically:YES];
                
                // cache the processed image
                [UIImageJPEGRepresentation(image, 0.9f) writeToFile:[self cachePathForImageURL:url cacheName:cacheName] atomically:YES];
            }];
            ioOperation.threadPriority = 0.1f;
            [self.ioOperationQueue addOperation:ioOperation];
        }
    });
}

@end
