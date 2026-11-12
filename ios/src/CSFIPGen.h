#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Cloudflare IP 段里按 /24（v4）或每段 sample 个（v6）生成随机 IP。
 * 与 Go 版 ipgen.go 的 generateIPv4List / generateIPv6List 逐条等价。
 */
NSArray<NSString *> *CSFGenerateIPv4(int sample);
NSArray<NSString *> *CSFGenerateIPv6(int sample);

NS_ASSUME_NONNULL_END
