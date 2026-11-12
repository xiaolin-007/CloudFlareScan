#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import "CSFEngine.h"

NS_ASSUME_NONNULL_BEGIN

/* window.webkit.messageHandlers.cfs <-> CSFEngine 的桥。
 * 方法名与 Wails 生成的 window.go.main.App.* 一一对应，前端 JS 无需改动。
 */
@interface CSFBridge : NSObject <WKScriptMessageHandler>

@property (nonatomic, strong, readonly) CSFEngine *engine;

- (instancetype)initWithWebView:(WKWebView *)webView host:(UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
