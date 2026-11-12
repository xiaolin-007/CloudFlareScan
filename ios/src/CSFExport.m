#import "CSFExport.h"

@implementation CSFExport

+ (NSString *)documentsDir {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject;
    if (!dir) dir = NSTemporaryDirectory();
    return dir;
}

+ (NSString *)stamp {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyyMMdd";
    return [f stringFromDate:[NSDate date]];
}

#pragma mark - CSV 字段转义（等价 Go encoding/csv 的 quote 规则）

+ (NSString *)csvField:(NSString *)raw {
    if (!raw) return @"";
    BOOL needQuote = NO;
    if ([raw containsString:@","] || [raw containsString:@"\""] ||
        [raw containsString:@"\n"] || [raw containsString:@"\r"]) {
        needQuote = YES;
    }
    if (raw.length > 0) {
        unichar c = [raw characterAtIndex:0];
        if (c == ' ' || c == '\t') needQuote = YES;
    }
    if (!needQuote) return raw;
    NSString *escaped = [raw stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

#pragma mark - CSV（GBK）

+ (NSString *)writeCSV:(NSArray<NSDictionary *> *)results {
    if (results.count == 0) return nil;

    NSMutableString *text = [NSMutableString string];

    NSArray *headers = @[@"排名", @"IP地址", @"地区码", @"地区", @"延迟(ms)", @"下载速度(MB/s)", @"端口", @"测速类型"];
    NSMutableArray *headCells = [NSMutableArray array];
    for (NSString *h in headers) [headCells addObject:[self csvField:h]];
    [text appendString:[headCells componentsJoinedByString:@","]];
    [text appendString:@"\r\n"];

    for (NSUInteger i = 0; i < results.count; i++) {
        NSDictionary *r = results[i];
        NSArray *cells = @[
            [NSString stringWithFormat:@"%d", (int)(i + 1)],
            r[@"ip"] ?: @"",
            r[@"iataCode"] ?: @"",
            r[@"chineseName"] ?: @"",
            [NSString stringWithFormat:@"%.2f", [r[@"latencyMs"] doubleValue]],
            [NSString stringWithFormat:@"%.2f", [r[@"downloadSpeed"] doubleValue]],
            [NSString stringWithFormat:@"%d", [r[@"port"] intValue]],
            r[@"testType"] ?: @""
        ];
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *c in cells) [out addObject:[self csvField:c]];
        [text appendString:[out componentsJoinedByString:@","]];
        [text appendString:@"\r\n"];
    }

    NSStringEncoding gbk = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    NSData *data = [text dataUsingEncoding:gbk allowLossyConversion:YES];
    if (!data) return nil;

    NSString *name = [NSString stringWithFormat:@"cfs_results_%@.csv", [self stamp]];
    NSString *path = [[self documentsDir] stringByAppendingPathComponent:name];
    if (![data writeToFile:path atomically:YES]) return nil;
    return path;
}

#pragma mark - CM 自定义格式（UTF-8）

+ (NSString *)writeCM:(NSArray<NSDictionary *> *)results {
    if (results.count == 0) return nil;

    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *r in results) {
        NSString *ip = r[@"ip"] ?: @"";
        int port = [r[@"port"] intValue];
        NSString *code = r[@"iataCode"];
        if (code.length == 0) code = @"UNKNOWN";
        NSString *name = r[@"chineseName"];
        if (name.length == 0) name = @"未知地区";
        double lat = [r[@"latencyMs"] doubleValue];
        double spd = [r[@"downloadSpeed"] doubleValue];

        if ([ip containsString:@":"]) {
            [text appendFormat:@"[%@]:%d#%@ %@ (%.0fms  %.0fMB/s)\n", ip, port, code, name, lat, spd];
        } else {
            [text appendFormat:@"%@:%d#%@ %@ (%.0fms  %.0fMB/s)\n", ip, port, code, name, lat, spd];
        }
    }

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;

    NSString *name = [NSString stringWithFormat:@"cfs_cm_%@.txt", [self stamp]];
    NSString *path = [[self documentsDir] stringByAppendingPathComponent:name];
    if (![data writeToFile:path atomically:YES]) return nil;
    return path;
}

@end
