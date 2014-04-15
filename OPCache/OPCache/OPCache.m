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

    if (block1 && block2) {
      return block2(block1(image));
    } else if (block1) {
      return block1(image);
    } else if (block2) {
      return block2(image);
    }

    return image;

  } copy];
}

@interface OPCache (/**/)
@property (atomic, strong, readwrite) NSOperationQueue *ioOperationQueue;
@property (atomic, strong) NSMutableDictionary *imageOperationsByCacheKey;
@property (atomic, strong) NSOperationQueue *imageOperationQueue;
@property (atomic, strong) NSMutableOrderedSet *filesToTouch;

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

-(UIImage*) decompressedImageWithContentsOfFile:(NSString*)path;
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
  self.imagePersistenceMemoryThreshold = ((NSUInteger)[[UIScreen mainScreen] scale] * 50) * 1024 * 1024;
  self.cachePNGs = NO;
  self.filesToTouch = [NSMutableOrderedSet new];

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

  // also clear out the cache when preferred content size changes, since we often
  // store computed metrics in a cache
  if ([UIApplication instancesRespondToSelector:@selector(preferredContentSizeCategory)]) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeAllObjects) name:UIContentSizeCategoryDidChangeNotification object:nil];
  }

  return self;
}

-(id<OPCacheCancelable>) fetchImageForURL:(NSString*)url completion:(OPCacheImageCompletionBlock)completion {
  return [self fetchImageForURL:url cacheName:kOPCacheDefaultCacheName processing:nil completion:completion];
}

-(id<OPCacheCancelable>) fetchImageForURL:(NSString *)url cacheName:(NSString *)cacheName processing:(OPCacheImageProcessingBlock)processing completion:(OPCacheImageCompletionBlock)completion {

  // early out on bad data
  if (! url) {
    return nil;
  }

  cacheName = cacheName ?: kOPCacheDefaultCacheName;
  NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];

  // early out when image can be pulled from memory
  UIImage *imageFromMemory = [self objectForKey:cacheKey];
  if (imageFromMemory) {
    completion(imageFromMemory, YES);
    return nil;
  }

  // construct the image request operation, but don't use any caching mechanism. We handle that ourselves.
  NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0f];
  AFImageRequestOperation *operation = [AFImageRequestOperation imageRequestOperationWithRequest:request imageProcessingBlock:nil success:^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
    if (image) {
      [self processImage:image with:processing url:url cacheName:cacheName completion:completion];
    }
  } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
    [self.imageOperationsByCacheKey removeObjectForKey:cacheKey];
  }];
  operation.imageScale = 1.0f;

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

    // check if image is already cached in memory or on disk
    id retVal = [self cachedImageForURL:url cacheName:cacheName];
    if (retVal) {
      [self.filesToTouch addObject:[self cachePathForImageURL:url cacheName:cacheName]];
      if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
          completion(retVal, YES);
        });
      }
      return;
    }

    // check if the original image is cached on disk so that all we have to do is process it
    UIImage *originalImage = [[UIImage alloc] initWithContentsOfFile:[self cachePathForImageURL:url cacheName:kOPCacheOriginalKey]];
    if (originalImage) {
      [self processImage:originalImage with:processing url:url cacheName:cacheName completion:completion];
      return;
    }

    // if there is already an operation running for this image, there's nothing to do. we can just wait till it's done
    if ([self.imageOperationsByCacheKey objectForKey:cacheKey]) {
      return;
    }

    [self.imageOperationQueue addOperation:operation];
    [self.imageOperationsByCacheKey setObject:operation forKey:cacheKey];
  });

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

  NSString *path = [self cachePathForImageURL:url cacheName:cacheName];
  [self.filesToTouch addObject:path];
  return [self decompressedImageWithContentsOfFile:path];
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
  return [[self.imagePersistencePath stringByAppendingPathComponent:[self cacheKeyFromImageURL:url cacheName:cacheName]]
          stringByAppendingPathExtension:self.cachePNGs ? @"png" : @"jpg"];
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
      if (cacheName) {
        [self removeImageForURL:url cacheName:cacheName];
      }
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
    while (file = [enumerator nextObject]) {
      [[NSFileManager defaultManager] removeItemAtPath:[self.imagePersistencePath stringByAppendingPathComponent:file] error:NULL];
    }

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

    if (sourceWidth <= targetWidth && sourceHeight <= targetHeight) {
      return image;
    }

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

      if (sourceImageRef) {
        CFRelease(sourceImageRef);
      }
    }
    UIGraphicsEndImageContext();
    return newImage;

  } copy];
}

+(OPCacheImageProcessingBlock) roundedCornerProcessingBlock:(CGFloat)radius backgroundColor:(UIColor*)color {
  return [[self class] roundedCornerProcessingBlock:radius corners:UIRectCornerAllCorners backgroundColor:color];
}

+(OPCacheImageProcessingBlock) roundedCornerProcessingBlock:(CGFloat)radius corners:(UIRectCorner)corners backgroundColor:(UIColor *)color {
  radius *= [[UIScreen mainScreen] scale];

  return [(UIImage*)^(UIImage *image){

    UIImage *newImage = nil;
    CGRect rect = (CGRect){CGPointZero, image.size};

    UIGraphicsBeginImageContextWithOptions(image.size, (color != nil), 1.0f);
    {
      if (color) {
        [color set];
        CGContextFillRect(UIGraphicsGetCurrentContext(), rect);
      } else {
        CGContextClearRect(UIGraphicsGetCurrentContext(), rect);
      }

      [[UIBezierPath bezierPathWithRoundedRect:rect byRoundingCorners:corners cornerRadii:CGSizeMake(radius, radius)] addClip];
      [image drawInRect:rect];

      newImage = UIGraphicsGetImageFromCurrentImageContext();
    }
    UIGraphicsEndImageContext();

    return newImage;

  } copy];
}

+(OPCacheImageProcessingBlock) circleProcessingBlockWithBackgroundColor:(UIColor*)color {

  return [(UIImage*)^(UIImage *image){

    UIImage *newImage = nil;
    CGRect rect = (CGRect){CGPointZero, image.size};

    UIGraphicsBeginImageContextWithOptions(image.size, (color != nil), 1.0f);
    {
      if (color) {
        [color set];
        CGContextFillRect(UIGraphicsGetCurrentContext(), rect);
      } else {
        CGContextClearRect(UIGraphicsGetCurrentContext(), rect);
      }

      CGFloat radius = image.size.width / 2.0f;
      [[UIBezierPath bezierPathWithRoundedRect:rect byRoundingCorners:UIRectCornerAllCorners cornerRadii:CGSizeMake(radius, radius)] addClip];
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

    // touch all the files we've seen to bump the last for clearance in the cache
    for (NSString *path in [self.filesToTouch reverseObjectEnumerator]) {
      [[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate: [NSDate date] }
                                       ofItemAtPath:path
                                              error:NULL];
    }

    NSArray *files = [[NSFileManager defaultManager]
                      contentsOfDirectoryAtURL:[NSURL fileURLWithPath:self.imagePersistencePath]
                      includingPropertiesForKeys:@[NSURLAttributeModificationDateKey]
                      options:NSDirectoryEnumerationSkipsHiddenFiles
                      error:NULL];

    // get the total size of files we have cached
    NSUInteger totalSize = 0;
    for (NSURL *url in files) {
      @autoreleasepool {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:NULL];
        totalSize += [attributes[NSFileSize] unsignedIntegerValue];
      }
    }

    // sort the cached files by modification date
    NSArray *sortedFiles = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *url1, NSURL *url2) {
      NSDate *date1 = nil, *date2 = nil;
      NSError *error1 = nil, *error2 = nil;
      if ([url1 getResourceValue:&date1 forKey:NSURLAttributeModificationDateKey error:&error1] &&
          [url2 getResourceValue:&date2 forKey:NSURLAttributeModificationDateKey error:&error2]) {
        return [date1 compare:date2];
      }
      return NSOrderedSame;
    }];

    // remove old files until we get under our cache size limit
    for (NSURL *url in sortedFiles) {
      @autoreleasepool {
        if (totalSize >= self.imagePersistenceMemoryThreshold)
        {
          NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:NULL];
          NSUInteger size = [attributes[NSFileSize] unsignedIntegerValue];
          totalSize -= size;
          [[NSFileManager defaultManager] removeItemAtPath:[url path] error:NULL];
        }
        else
        {
          break ;
        }
      }
    }

    [self.filesToTouch removeAllObjects];
    [[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
  }]];
}

-(void) processImage:(UIImage*)originalImage with:(OPCacheImageProcessingBlock)processing url:(NSString*)url cacheName:(NSString*)cacheName completion:(OPCacheImageCompletionBlock)completion {

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

    // process the image if needed
    UIImage *image = originalImage;
    if (processing) {
      image = processing(image);
    }
    if (! image) {
      return ;
    }

    // stick the processed image into memory cache
    NSString *cacheKey = [self cacheKeyFromImageURL:url cacheName:cacheName];
    [self setObject:image forKey:cacheKey];

    // call all the completion blocks on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion) {
        completion(image, NO);
      }
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
          NSData *imageData = self.cachePNGs ? UIImagePNGRepresentation(originalImage) : UIImageJPEGRepresentation(originalImage, 0.9f);
          [imageData writeToFile:originalFilePath atomically:YES];
        }

        // cache the processed image
        NSData *imageData = self.cachePNGs ? UIImagePNGRepresentation(image) : UIImageJPEGRepresentation(image, 0.9f);
        NSString *filePath = [self cachePathForImageURL:url cacheName:cacheName];
        [imageData writeToFile:filePath atomically:YES];
      }];
      ioOperation.threadPriority = 0.1f;
      [self.ioOperationQueue addOperation:ioOperation];
    }
  });
}

-(UIImage*) decompressedImageWithContentsOfFile:(NSString*)path {

  UIImage *image = [[UIImage alloc] initWithContentsOfFile:path];
  if (! image) {
    return nil;
  }

  CGImageRef imageRef = image.CGImage;
  CGRect rect = CGRectMake(0.f, 0.f, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
  CGContextRef bitmapContext = CGBitmapContextCreate(NULL,
                                                     rect.size.width,
                                                     rect.size.height,
                                                     CGImageGetBitsPerComponent(imageRef),
                                                     CGImageGetBytesPerRow(imageRef),
                                                     CGImageGetColorSpace(imageRef),
                                                     CGImageGetBitmapInfo(imageRef)
                                                     );
  CGContextDrawImage(bitmapContext, rect, imageRef);
  CGImageRef decompressedImageRef = CGBitmapContextCreateImage(bitmapContext);
  UIImage *decompressedImage = [UIImage imageWithCGImage:decompressedImageRef];
  CGImageRelease(decompressedImageRef);
  CGContextRelease(bitmapContext);

  return decompressedImage;
}

#pragma mark -
#pragma mark Overridden NSCache methods
#pragma mark -

-(id) objectForKey:(id)key {
  id retVal = [super objectForKey:key];
#if TARGET_IPHONE_SIMULATOR
  if (! retVal) {
    NSLog(@"Cache miss for key: %@", key);
  } else {
    NSLog(@"Cache hit for key: %@", key);
  }
#endif
  return retVal;
}

@end
