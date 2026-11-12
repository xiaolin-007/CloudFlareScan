#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* 同时写 NSLog 与 Documents/cfs.log，便于在 iSH 侧用 MCP 读文件排查 */
void CFSLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);

NS_ASSUME_NONNULL_END
