#import "SZLoader.h"
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <mach/machine.h>
#import <objc/runtime.h>

NSErrorDomain const SZLoaderErrorDomain = @"SZLoaderErrorDomain";

static NSError *SZError(SZLoaderError code, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static NSError *SZError(SZLoaderError code, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [NSError errorWithDomain:SZLoaderErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *SZArchName(cpu_type_t type) {
    switch (type) {
        case CPU_TYPE_ARM64: return @"arm64";
        case CPU_TYPE_X86_64: return @"x86_64";
        case CPU_TYPE_ARM: return @"arm";
        case CPU_TYPE_X86: return @"i386";
        default: return [NSString stringWithFormat:@"cputype %d", type];
    }
}

static cpu_type_t SZHostCPUType(void) {
#if defined(__arm64__)
    return CPU_TYPE_ARM64;
#elif defined(__x86_64__)
    return CPU_TYPE_X86_64;
#else
#error unsupported host
#endif
}

@implementation SZLoader

+ (NSString *)executablePathForPath:(NSString *)path error:(NSError **)error {
    BOOL isDir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir]) {
        if (error) *error = SZError(SZLoaderErrorNotFound, @"No file at %@", path);
        return nil;
    }
    if (!isDir) return path;
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"app"]) {
        if (error) *error = SZError(SZLoaderErrorMainExecutable, @"%@ is an application. App main executables cannot be loaded into another process; choose a framework, dylib or plug-in bundle inside it instead.", path.lastPathComponent);
        return nil;
    }
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    NSString *exe = bundle.executablePath;
    if (!exe) {
        if (error) *error = SZError(SZLoaderErrorNoExecutable, @"%@ has no executable (missing CFBundleExecutable or binary)", path.lastPathComponent);
        return nil;
    }
    return exe;
}

static BOOL SZCheckThinHeader(NSData *data, NSUInteger offset, NSString *path, NSError **error) {
    if (data.length < offset + sizeof(struct mach_header_64)) {
        if (error) *error = SZError(SZLoaderErrorNotMachO, @"%@ is truncated", path.lastPathComponent);
        return NO;
    }
    const struct mach_header_64 *header = (const struct mach_header_64 *)((const uint8_t *)data.bytes + offset);
    if (header->magic == MH_MAGIC || header->magic == MH_CIGAM || header->magic == MH_CIGAM_64) {
        if (error) *error = SZError(SZLoaderErrorWrongArchitecture, @"%@ is not built for %@", path.lastPathComponent, SZArchName(SZHostCPUType()));
        return NO;
    }
    if (header->magic != MH_MAGIC_64) {
        if (error) *error = SZError(SZLoaderErrorNotMachO, @"%@ is not a Mach-O file", path.lastPathComponent);
        return NO;
    }
    if (header->cputype != SZHostCPUType()) {
        if (error) *error = SZError(SZLoaderErrorWrongArchitecture, @"%@ is built for %@, this process is %@", path.lastPathComponent, SZArchName(header->cputype), SZArchName(SZHostCPUType()));
        return NO;
    }
    if (header->filetype == MH_EXECUTE) {
        if (error) *error = SZError(SZLoaderErrorMainExecutable, @"%@ is a main executable (MH_EXECUTE) and cannot be dlopen'd; choose a framework, dylib or plug-in bundle.", path.lastPathComponent);
        return NO;
    }
    if (header->filetype != MH_DYLIB && header->filetype != MH_BUNDLE) {
        if (error) *error = SZError(SZLoaderErrorNotMachO, @"%@ has Mach-O file type %u, which is not loadable", path.lastPathComponent, header->filetype);
        return NO;
    }
    return YES;
}

+ (BOOL)checkMachOAtPath:(NSString *)path error:(NSError **)error {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) {
        if (error) *error = SZError(SZLoaderErrorNotFound, @"Cannot open %@", path);
        return NO;
    }
    NSData *data = [fh readDataUpToLength:64 * 1024 error:NULL];
    [fh closeFile];
    if (data.length < sizeof(uint32_t)) {
        if (error) *error = SZError(SZLoaderErrorNotMachO, @"%@ is not a Mach-O file", path.lastPathComponent);
        return NO;
    }
    uint32_t magic = *(const uint32_t *)data.bytes;
    if (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        BOOL is64 = (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
        const struct fat_header *fat = data.bytes;
        uint32_t count = OSSwapBigToHostInt32(fat->nfat_arch);
        NSMutableArray<NSString *> *arches = [NSMutableArray array];
        for (uint32_t i = 0; i < count; i++) {
            cpu_type_t cputype;
            uint64_t offset;
            if (is64) {
                const struct fat_arch_64 *arch = (const struct fat_arch_64 *)((const uint8_t *)data.bytes + sizeof(struct fat_header)) + i;
                if ((const uint8_t *)(arch + 1) > (const uint8_t *)data.bytes + data.length) break;
                cputype = (cpu_type_t)OSSwapBigToHostInt32((uint32_t)arch->cputype);
                offset = OSSwapBigToHostInt64(arch->offset);
            } else {
                const struct fat_arch *arch = (const struct fat_arch *)((const uint8_t *)data.bytes + sizeof(struct fat_header)) + i;
                if ((const uint8_t *)(arch + 1) > (const uint8_t *)data.bytes + data.length) break;
                cputype = (cpu_type_t)OSSwapBigToHostInt32((uint32_t)arch->cputype);
                offset = OSSwapBigToHostInt32(arch->offset);
            }
            [arches addObject:SZArchName(cputype)];
            if (cputype == SZHostCPUType()) {
                NSFileHandle *slice = [NSFileHandle fileHandleForReadingAtPath:path];
                [slice seekToFileOffset:offset];
                NSData *sliceData = [slice readDataUpToLength:sizeof(struct mach_header_64) error:NULL];
                [slice closeFile];
                return SZCheckThinHeader(sliceData, 0, path, error);
            }
        }
        if (error) *error = SZError(SZLoaderErrorWrongArchitecture, @"%@ contains %@ but not %@", path.lastPathComponent, [arches componentsJoinedByString:@", "], SZArchName(SZHostCPUType()));
        return NO;
    }
    return SZCheckThinHeader(data, 0, path, error);
}

+ (BOOL)loadBundleAtPath:(NSString *)path loadedImagePath:(NSString *__autoreleasing *)loadedImagePath error:(NSError **)error {
    NSString *exe = [self executablePathForPath:path error:error];
    if (!exe) return NO;
    if (![self checkMachOAtPath:exe error:error]) return NO;

    void *handle = dlopen(exe.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *msg = dlerror();
        if (error) *error = SZError(SZLoaderErrorDlopenFailed, @"dlopen failed: %s", msg ?: "unknown error");
        return NO;
    }

    char resolved[PATH_MAX];
    NSString *real = realpath(exe.fileSystemRepresentation, resolved) ? @(resolved) : exe;
    NSString *match = nil;
    unsigned count = 0;
    const char **names = objc_copyImageNames(&count);
    for (unsigned i = 0; i < count && !match; i++) {
        NSString *candidate = @(names[i]);
        if ([candidate isEqualToString:real] || [candidate isEqualToString:exe]) {
            match = candidate;
        } else {
            char other[PATH_MAX];
            if (realpath(names[i], other) && strcmp(other, resolved) == 0) match = candidate;
        }
    }
    free(names);
    if (loadedImagePath) *loadedImagePath = match ?: real;
    return YES;
}

@end
