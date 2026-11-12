#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* 导出测速结果。返回落盘完整路径；失败返回 nil。
 * CSV 用 GB18030 编码 + CRLF（Excel 打开中文不乱码），与 Go 版 exportCSV 一致。
 * CM 为 UTF-8 自定义订阅格式，与 Go 版 exportCM 一致。
 */
@interface CSFExport : NSObject

+ (nullable NSString *)writeCSV:(NSArray<NSDictionary *> *)results;
+ (nullable NSString *)writeCM:(NSArray<NSDictionary *> *)results;

@end

NS_ASSUME_NONNULL_END
