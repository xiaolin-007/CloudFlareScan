#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CSFLogBlock)(NSString *msg);
typedef void (^CSFScanProgressBlock)(NSInteger current, NSInteger total, NSInteger found, double speed);
typedef void (^CSFScanResultBlock)(NSDictionary *result);
typedef void (^CSFSpeedProgressBlock)(NSInteger current, NSInteger total);
typedef void (^CSFSpeedCompleteBlock)(NSArray<NSDictionary *> *results);
typedef void (^CSFScanCompleteBlock)(NSArray<NSDictionary *> *results);

/* CloudFlareScan 扫描 / 测速引擎（Go 版逻辑的 ObjC 移植）
 * 回调可能在后台线程触发，调用方负责切主线程。
 */
@interface CSFEngine : NSObject

@property (nonatomic, copy, nullable) CSFLogBlock onLog;
@property (nonatomic, copy, nullable) CSFScanProgressBlock onProgress;
@property (nonatomic, copy, nullable) CSFScanResultBlock onResult;
@property (nonatomic, copy, nullable) CSFSpeedProgressBlock onSpeedProgress;
@property (nonatomic, copy, nullable) CSFSpeedCompleteBlock onSpeedComplete;
@property (nonatomic, copy, nullable) CSFScanCompleteBlock onScanComplete;

- (void)startScanWithVersion:(int)version
                        port:(int)port
                  maxWorkers:(int)maxWorkers
            latencyThreshold:(int)threshold
                  v4Sample:(int)v4Sample
                  v6Sample:(int)v6Sample;

- (void)stopScan;

- (void)startFullSpeedTestWithMaxCount:(int)maxCount port:(int)port;
- (void)startRegionSpeedTestWithRegion:(NSString *)region maxCount:(int)maxCount port:(int)port;
- (void)stopSpeedTest;

- (NSArray<NSDictionary *> *)lastScanResults;

/* IATA -> 中文名，与 Go 版 utils.go 同表 */
+ (NSString *)chineseNameForIata:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
