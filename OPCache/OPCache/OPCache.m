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

OPCacheImageProcessingBlock OPCacheImageProcessingBlockCompose(OPCacheImageProcessingBlock block1, OPCacheImageProcessingBlock block2) {
    return [(UIImage*)^(UIImage *image) {
        
        if (block1 && block2)
            return block2(block1(image));
        if (block1)
            return block1(image);
        if (block2)
            return block2(image);
        
        return image;
        
    } copy];
}

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
@property (nonatomic, strong) NSMutableDictionary *imageFileAttributes;

-(UIImage*) diskImageFromURL:(NSString*)url;
-(UIImage*) diskImageFromURL:(NSString*)url cacheName:(NSString*)cacheName;

-(NSString*) cacheKeyFromImageURL:(NSString*)url;
-(NSString*) cacheKeyFromImageURL:(NSString*)url cacheName:(NSString*)cacheName;

-(NSString*) cachePathForImageURL:(NSString*)url;
-(NSString*) cachePathForImageURL:(NSString*)url cacheName:(NSString*)cacheName;

-(void) cancelFetchForURL:(NSString*)url;
-(void) cancelFetchForURL:(NSString*)url cacheName:(NSString*)cacheName;

-(void) cleanUpPersistedImages;
-(void) flushImageFileAttributesToDisk;
-(void) processImage:(UIImage*)originalImage with:(OPCacheImageProcessingBlock)processing url:(NSString*)url cacheName:(NSString*)cacheName completion:(OPCacheImageCompletionBlock)completion;
@end

@implementation OPCache

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
    self.imagePersistenceTimeInterval = 60.0 * 60.0 * 24.0 * 14.0; // 2 weeks of disk persistence
    self.imagePersistenceMemoryThreshold = ((NSUInteger)[[UIScreen mainScreen] scale] * 20) * 1024 * 1024;
    
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

-(id<OPCacheCancelable>) fetchImageForURL:(NSString*)url completion:(OPCacheImageCompletionBlock)completion {
    return [self fetchImageForURL:url cacheName:kOPCacheDefaultCacheName processing:nil completion:completion];
}

-(id<OPCacheCancelable>) fetchImageForURL:(NSString *)url cacheName:(NSString *)cacheName processing:(OPCacheImageProcessingBlock)processing completion:(OPCacheImageCompletionBlock)completion {
    
    cacheName = cacheName ?: kOPCacheDefaultCacheName;
    
    // early out on bad data
    if (! url)    return nil;
    
    // check if image is already cached in memory or on disk
    id retVal = [self cachedImageForURL:url cacheName:cacheName];
    if (retVal)
    {
        if (completion)
            __opcache_dispatch_main_queue_asap(^{ completion(retVal, YES); });
        return nil;
    }
    
    // check if the original image is cached on disk so that all we have to do is process it
    UIImage *originalImage = [[UIImage alloc] initWithContentsOfFile:[self cachePathForImageURL:url cacheName:kOPCacheOriginalKey]];
    if (originalImage)
    {
        [self processImage:originalImage with:processing url:url cacheName:cacheName completion:completion];
        return nil;
    }
    
    // if there is already an operation running for this image, there's nothing to do. we can just wait till it's done
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    if ([self.imageOperationsByCacheKey objectForKey:cacheKey])
        return nil;
    
    // if we got this far then we gotta load something from the server.
    
    // construct the image request operation, but don't use any caching mechanism. We handle that ourselves.
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0f];
    AFImageRequestOperation *operation = [AFImageRequestOperation imageRequestOperationWithRequest:request imageProcessingBlock:nil success:^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
        if (image)
            [self processImage:image with:processing url:url cacheName:cacheName completion:completion];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
        [self.imageOperationsByCacheKey removeObjectForKey:cacheKey];
    }];
    operation.imageScale = 1.0f;
    
    [self.imageOperationQueue addOperation:operation];
    [self.imageOperationsByCacheKey setObject:operation forKey:cacheKey];
    
    return (id<OPCacheCancelable>)operation;
}

-(UIImage*) cachedImageForURL:(NSString*)url {
    return [self cachedImageForURL:url cacheName:kOPCacheDefaultCacheName];
}

-(UIImage*) cachedImageForURL:(NSString*)url cacheName:(NSString *)cacheName {
    
    // first try finding the image in memory cache
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    UIImage *retVal = [self objectForKey:cacheKey];
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
            size_t size = CGImageGetBytesPerRow(retVal.CGImage) * CGImageGetHeight(retVal.CGImage);
            [self setObject:retVal forKey:cacheKey cost:size];
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
    return [[UIImage alloc] initWithContentsOfFile:[self cachePathForImageURL:url cacheName:cacheName]];
}

-(NSString*) cacheKeyFromImageURL:(NSString*)url {
    return [self cacheKeyFromImageURL:url cacheName:kOPCacheDefaultCacheName];
}

-(NSString*) cacheKeyFromImageURL:(NSString*)url cacheName:(NSString*)cacheName {
    return [[NSString alloc] initWithFormat:@"%u-%@", [url hash], cacheName?cacheName:kOPCacheDefaultCacheName];
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
        if ([file hasSuffix:[NSString stringWithFormat:@"%u", [url hash]]])
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

-(void) removeAllImages {
    
    [self.ioOperationQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:self.imagePersistencePath];
        NSString *file = nil;
        while (file = [enumerator nextObject])
            [[NSFileManager defaultManager] removeItemAtPath:[self.imagePersistencePath stringByAppendingPathComponent:file] error:NULL];
        
    }]];
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

-(void) cancelFetchForHandle:(id<OPCacheCancelable>)handle {
    
    [handle cancel];
    [self.imageOperationsByCacheKey removeObjectsForKeys:[self.imageOperationsByCacheKey allKeysForObject:handle]];
}

+(UIImage*(^)(UIImage *image)) resizeProcessingBlock:(CGSize)size {
    return [[self class] resizeProcessingBlock:size detectRetina:YES];
}

+(OPCacheImageProcessingBlock) resizeProcessingBlock:(CGSize)size detectRetina:(BOOL)detectRetina {
    
    size.width *= detectRetina ? [[UIScreen mainScreen] scale] : 1.0f;;
    size.height *= detectRetina ? [[UIScreen mainScreen] scale] : 1.0f;
    
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
            
            if (sourceImageRef)
                CFRelease(sourceImageRef);
        }
        UIGraphicsEndImageContext();
        return newImage;
        
    } copy];
}

+(OPCacheImageProcessingBlock) roundedCornerProcessingBlock:(CGFloat)radius backgroundColor:(UIColor*)color {
    radius *= [[UIScreen mainScreen] scale];
    
    return [(UIImage*)^(UIImage *image){
        
        UIImage *newImage = nil;
        CGRect rect = (CGRect){CGPointZero, image.size};
        
        UIGraphicsBeginImageContextWithOptions(image.size, YES, 1.0f);
        {
            [color set];
            CGContextFillRect(UIGraphicsGetCurrentContext(), rect);
            
            [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius] addClip];
            [image drawInRect:rect];
            
            newImage = UIGraphicsGetImageFromCurrentImageContext();
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
        
        NSMutableSet *removableFilePaths = [NSMutableSet new];
        __block NSUInteger totalSize = 0;
        
        // grab all of the image files that have expired dates
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-self.imagePersistenceTimeInterval];
        [self.imageFileAttributes enumerateKeysAndObjectsUsingBlock:^(NSString *filePath, NSDictionary *attributes, BOOL *stop) {
            if ([(NSDate*)[attributes objectForKey:@"date"] compare:cutoff] == NSOrderedAscending)
                [removableFilePaths addObject:filePath];
            totalSize += [[attributes objectForKey:@"length"] unsignedIntegerValue];
        }];
        
        // grab all the largest images that put the total cache size over our threshold
        NSArray *filePathsSortedBySize = [[self.imageFileAttributes allKeys] sortedArrayUsingComparator:^NSComparisonResult(id key1, id key2) {
            return [[[self.imageFileAttributes objectForKey:key2] objectForKey:@"length"]
                    compare:[[self.imageFileAttributes objectForKey:key1] objectForKey:@"length"]];
        }];
        [filePathsSortedBySize enumerateObjectsUsingBlock:^(NSString *filePath, NSUInteger idx, BOOL *stop) {
            totalSize -= [[[self.imageFileAttributes objectForKey:filePath] objectForKey:@"length"] unsignedIntegerValue];
            if (totalSize > self.imagePersistenceMemoryThreshold)
                [removableFilePaths addObject:filePath];
            if (totalSize < self.imagePersistenceMemoryThreshold)
                *stop = YES;
        }];
        
        // remove those images from disk
        [removableFilePaths enumerateObjectsUsingBlock:^(NSString *filePath, BOOL *stop) {
            if ([[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL])
                [self.imageFileAttributes removeObjectForKey:filePath];
        }];
        [self flushImageFileAttributesToDisk];
        
        [[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
    }]];
}

-(void) flushImageFileAttributesToDisk {
    if (_imageFileAttributes)
    {
        NSString *directoryPath = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject]
                                   stringByAppendingPathComponent:@"OPCache"];
        [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:NULL];
        
        NSString *filePath = [directoryPath stringByAppendingPathComponent:@"imageFileAttributes.plist"];
        [self.imageFileAttributes writeToFile:filePath atomically:YES];
        self.imageFileAttributes = nil;
    }
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
                {
                    NSData *imageData = UIImageJPEGRepresentation(originalImage, 0.9f);
                    NSDictionary *attributes = @{@"length": @([imageData length]),
                    @"date": [NSDate date]};
                    [self.imageFileAttributes setObject:attributes forKey:originalFilePath];
                    [imageData writeToFile:originalFilePath atomically:YES];
                }
                
                // cache the processed image
                NSData *imageData = UIImageJPEGRepresentation(image, 0.9f);
                NSString *filePath = [self cachePathForImageURL:url cacheName:cacheName];
                NSDictionary *attributes = @{
                    @"length": @([imageData length]),
                    @"date": [NSDate date]
                };
                [self.imageFileAttributes setObject:attributes forKey:filePath];
                [imageData writeToFile:filePath atomically:YES];
            }];
            ioOperation.threadPriority = 0.1f;
            [self.ioOperationQueue addOperation:ioOperation];
        }
    });
}

-(NSDictionary*) imageFileAttributes {
    if (! _imageFileAttributes)
    {
        NSString *filePath = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject]
                              stringByAppendingPathComponent:@"OPCache/imageFileAttributes.plist"];
        _imageFileAttributes = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
        
        if (! _imageFileAttributes)
            _imageFileAttributes = [NSMutableDictionary new];
    }
    return _imageFileAttributes;
}

#pragma mark -
#pragma mark Overridden NSCache methods
#pragma mark -

-(id) objectForKey:(id)key {
    id retVal = [super objectForKey:key];
#if TARGET_IPHONE_SIMULATOR
    if (! retVal)
        NSLog(@"Cache miss for key: %@", key);
    else
        NSLog(@"Cache hit for key: %@", key);
#endif
    return retVal;
}

@end
