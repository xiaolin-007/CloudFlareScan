#import "CSFBridge.h"
#import "CSFExport.h"
#import "CSFLog.h"
#import <UIKit/UIKit.h>

static NSString *CSFJSString(NSString *s) {
    if (!s) s = @"";
    NSData *d = [NSJSONSerialization dataWithJSONObject:@[s] options:0 error:nil];
    if (!d) return @"\"\"";
    NSString *arr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (arr.length < 2) return @"\"\"";
    return [arr substringWithRange:NSMakeRange(1, arr.length - 2)];
}

@implementation CSFBridge {
    __weak WKWebView *_webView;
    __weak UIViewController *_host;
    UIBackgroundTaskIdentifier _bgTask;
}

- (instancetype)initWithWebView:(WKWebView *)webView host:(UIViewController *)host {
    self = [super init];
    if (!self) return nil;
    _webView = webView;
    _host = host;
    _bgTask = UIBackgroundTaskInvalid;
    _engine = [[CSFEngine alloc] init];
    [self wireEngine];
    return self;
}

#pragma mark - 后台执行时间

- (void)beginBackgroundWork {
    if (_bgTask != UIBackgroundTaskInvalid) return;
    __weak typeof(self) weakSelf = self;
    _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"cfs-scan" expirationHandler:^{
        __strong typeof(weakSelf) self2 = weakSelf;
        if (!self2) return;
        [self2.engine stopScan];
        [self2.engine stopSpeedTest];
        [self2 endBackgroundWork];
    }];
}

- (void)endBackgroundWork {
    if (_bgTask == UIBackgroundTaskInvalid) return;
    [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
    _bgTask = UIBackgroundTaskInvalid;
}

#pragma mark - 引擎事件 -> JS

- (void)emitEvent:(NSString *)name args:(NSArray *)args {
    NSData *d = [NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
    NSString *json = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"[]";
    NSString *js = [NSString stringWithFormat:@"window.__cfs_emit && window.__cfs_emit(%@,%@);",
                    CSFJSString(name), json];

    dispatch_async(dispatch_get_main_queue(), ^{
        WKWebView *wv = self->_webView;
        if (!wv) return;
        [wv evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)resolve:(NSNumber *)reqId ok:(BOOL)ok value:(id)value {
    NSString *js;
    if ([value isKindOfClass:[NSString class]]) {
        js = [NSString stringWithFormat:@"window.__cfs_resolve && window.__cfs_resolve(%@,%@,%@);",
              reqId, ok ? @"true" : @"false", CSFJSString((NSString *)value)];
    } else {
        NSData *d = [NSJSONSerialization dataWithJSONObject:(value ?: [NSNull null]) options:0 error:nil];
        NSString *json = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null";
        js = [NSString stringWithFormat:@"window.__cfs_resolve && window.__cfs_resolve(%@,%@,%@);",
              reqId, ok ? @"true" : @"false", json];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        WKWebView *wv = self->_webView;
        if (!wv) return;
        [wv evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)wireEngine {
    __weak typeof(self) weakSelf = self;
    CSFEngine *e = self.engine;

    e.onLog = ^(NSString *msg) {
        [weakSelf emitEvent:@"log-message" args:@[msg ?: @""]];
    };

    e.onProgress = ^(NSInteger cur, NSInteger total, NSInteger found, double speed) {
        [weakSelf emitEvent:@"scan-progress" args:@[@(cur), @(total), @(found), @(speed)]];
    };

    e.onResult = ^(NSDictionary *row) {
        [weakSelf emitEvent:@"scan-result" args:@[row]];
    };

    e.onScanComplete = ^(NSArray<NSDictionary *> *rows) {
        [weakSelf emitEvent:@"scan-completed" args:@[rows ?: @[]]];
        [weakSelf endBackgroundWork];
    };

    e.onSpeedProgress = ^(NSInteger cur, NSInteger total) {
        [weakSelf emitEvent:@"speed-progress" args:@[@(cur), @(total)]];
    };

    e.onSpeedComplete = ^(NSArray<NSDictionary *> *rows) {
        [weakSelf emitEvent:@"speed-completed" args:@[rows ?: @[]]];
        [weakSelf endBackgroundWork];
    };
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"cfs"]) return;
    if (![message.body isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *body = message.body;
    NSString *method = body[@"method"];
    NSNumber *reqId = body[@"id"];
    NSArray *args = body[@"args"];
    if (![args isKindOfClass:[NSArray class]]) args = @[];
    if (![method isKindOfClass:[NSString class]]) return;
    if (![method isEqualToString:@"Log"]) CFSLog(@"[BRIDGE] %@ args=%@", method, args);

    /* 非 Promise 方法（id=0 表示不等回包） */
    if ([method isEqualToString:@"Log"]) {
        NSString *m = args.count > 0 ? [args[0] description] : @"";
        CFSLog(@"[JS] %@", m);
        return;
    }

    if ([method isEqualToString:@"Copy"]) {
        NSString *text = args.count > 0 && [args[0] isKindOfClass:[NSString class]] ? args[0] : @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = text;
        });
        return;
    }

    if ([method isEqualToString:@"StartScan"]) {
        int version   = args.count > 0 ? [args[0] intValue] : 4;
        int port      = args.count > 1 ? [args[1] intValue] : 443;
        int workers   = args.count > 2 ? [args[2] intValue] : 150;
        int threshold = args.count > 3 ? [args[3] intValue] : 1000;
        int v4        = args.count > 4 ? [args[4] intValue] : 1;
        int v6        = args.count > 5 ? [args[5] intValue] : 100;
        [self beginBackgroundWork];
        [self.engine startScanWithVersion:version port:port maxWorkers:workers
                         latencyThreshold:threshold v4Sample:v4 v6Sample:v6];
        [self resolve:reqId ok:YES value:@""];
        return;
    }

    if ([method isEqualToString:@"StopScan"]) {
        [self.engine stopScan];
        [self resolve:reqId ok:YES value:@""];
        return;
    }

    if ([method isEqualToString:@"StartFullSpeedTest"]) {
        int maxCount = args.count > 0 ? [args[0] intValue] : 10;
        int port     = args.count > 1 ? [args[1] intValue] : 443;
        [self beginBackgroundWork];
        [self.engine startFullSpeedTestWithMaxCount:maxCount port:port];
        [self resolve:reqId ok:YES value:@""];
        return;
    }

    if ([method isEqualToString:@"StartRegionSpeedTest"]) {
        NSString *region = args.count > 0 && [args[0] isKindOfClass:[NSString class]] ? args[0] : @"";
        int maxCount = args.count > 1 ? [args[1] intValue] : 10;
        int port     = args.count > 2 ? [args[2] intValue] : 443;
        [self beginBackgroundWork];
        [self.engine startRegionSpeedTestWithRegion:region maxCount:maxCount port:port];
        [self resolve:reqId ok:YES value:@""];
        return;
    }

    if ([method isEqualToString:@"StopSpeedTest"]) {
        [self.engine stopSpeedTest];
        [self resolve:reqId ok:YES value:@""];
        return;
    }

    if ([method isEqualToString:@"ExportResults"]) {
        NSArray *rows = args.count > 0 && [args[0] isKindOfClass:[NSArray class]] ? args[0] : @[];
        NSString *mode = args.count > 1 && [args[1] isKindOfClass:[NSString class]] ? args[1] : @"csv";

        if (rows.count == 0) {
            [self resolve:reqId ok:NO value:@"没有测速结果可导出"];
            return;
        }

        NSString *path = [mode isEqualToString:@"cm"] ? [CSFExport writeCM:rows] : [CSFExport writeCSV:rows];
        if (!path) {
            [self resolve:reqId ok:NO value:@"写入文件失败"];
            return;
        }

        [self presentShareForPath:path];
        [self resolve:reqId ok:YES value:[NSString stringWithFormat:@"已保存：%@", path.lastPathComponent]];
        return;
    }

    [self resolve:reqId ok:NO value:[NSString stringWithFormat:@"未知方法 %@", method]];
}

#pragma mark - 分享

- (void)presentShareForPath:(NSString *)path {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *host = self->_host;
        if (!host) return;
        NSURL *url = [NSURL fileURLWithPath:path];
        UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                                                        applicationActivities:nil];
        if (vc.popoverPresentationController) {
            vc.popoverPresentationController.sourceView = host.view;
            vc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds),
                                                                    CGRectGetMidY(host.view.bounds), 1, 1);
            vc.popoverPresentationController.permittedArrowDirections = 0;
        }
        [host presentViewController:vc animated:YES completion:nil];
    });
}

@end
