#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const SZLoaderErrorDomain;

typedef NS_ERROR_ENUM(SZLoaderErrorDomain, SZLoaderError) {
    SZLoaderErrorNotFound = 1,
    SZLoaderErrorNoExecutable,
    SZLoaderErrorMainExecutable,
    SZLoaderErrorNotMachO,
    SZLoaderErrorWrongArchitecture,
    SZLoaderErrorDlopenFailed,
};

/// Loads frameworks, dylibs and plug-in bundles into the current process after checking they can be loaded.
@interface SZLoader : NSObject
/// Resolves a .framework / .bundle directory to its executable, or returns the path unchanged for a plain file.
+ (nullable NSString *)executablePathForPath:(NSString *)path error:(NSError **)error;
/// Validates the Mach-O header: must be a loadable file type built for this process's architecture.
+ (BOOL)checkMachOAtPath:(NSString *)path error:(NSError **)error;
/// dlopen the target. On success `loadedImagePath` is the path the objc runtime reports for it.
+ (BOOL)loadBundleAtPath:(NSString *)path loadedImagePath:(NSString *_Nullable __autoreleasing *_Nullable)loadedImagePath error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
