#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "CSFBridge.h"
#import "CSFLog.h"

@interface CFSViewController : UIViewController
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation CFSViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:249.0 / 255.0
                                                green:250.0 / 255.0
                                                 blue:251.0 / 255.0
                                                alpha:1.0];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDarkContent;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

@end

@interface CFSAppDelegate : UIResponder <UIApplicationDelegate, WKNavigationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) CFSViewController *rootVC;
@property (nonatomic, strong) CSFBridge *bridge;
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation CFSAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    CFSLog(@"=== launch begin ===");
    CFSLog(@"bundle=%@ ver=%@ os=%@", [[NSBundle mainBundle] bundleIdentifier],
           [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
           [[UIDevice currentDevice] systemVersion]);

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor colorWithRed:249.0 / 255.0
                                                  green:250.0 / 255.0
                                                   blue:251.0 / 255.0
                                                  alpha:1.0];

    self.rootVC = [[CFSViewController alloc] init];
    self.rootVC.view.frame = self.window.bounds;

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.suppressesIncrementalRendering = NO;

    NSString *shimPath = [[NSBundle mainBundle] pathForResource:@"shim" ofType:@"js"];
    CFSLog(@"shimPath=%@", shimPath);
    if (shimPath) {
        NSString *shim = [NSString stringWithContentsOfFile:shimPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
        CFSLog(@"shim length=%d", (int)shim.length);
        if (shim.length > 0) {
            WKUserScript *us = [[WKUserScript alloc] initWithSource:shim
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                   forMainFrameOnly:YES];
            [cfg.userContentController addUserScript:us];
        }
    }

    CGRect bounds = self.window.bounds;
    WKWebView *webView = [[WKWebView alloc] initWithFrame:bounds configuration:cfg];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.scrollView.bounces = NO;
    webView.scrollView.alwaysBounceVertical = NO;
    webView.scrollView.alwaysBounceHorizontal = NO;
    webView.scrollView.showsVerticalScrollIndicator = NO;
    webView.scrollView.showsHorizontalScrollIndicator = NO;
    webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    webView.allowsLinkPreview = NO;
    webView.allowsBackForwardNavigationGestures = NO;
    webView.opaque = NO;
    webView.backgroundColor = self.window.backgroundColor;
    webView.scrollView.backgroundColor = self.window.backgroundColor;
    webView.navigationDelegate = self;
    if ([webView respondsToSelector:@selector(setInspectable:)]) {
        [webView setValue:@NO forKey:@"inspectable"];
    }
    self.webView = webView;

    self.rootVC.webView = webView;
    [self.rootVC.view addSubview:webView];

    self.bridge = [[CSFBridge alloc] initWithWebView:webView host:self.rootVC];
    [cfg.userContentController addScriptMessageHandler:self.bridge name:@"cfs"];
    CFSLog(@"bridge installed; frame=%@", NSStringFromCGRect(webView.frame));

    self.window.rootViewController = self.rootVC;
    [self.window makeKeyAndVisible];

    NSURL *wwwURL = [[NSBundle mainBundle] URLForResource:@"www" withExtension:nil];
    CFSLog(@"wwwURL=%@", wwwURL);
    if (wwwURL) {
        NSURL *indexURL = [wwwURL URLByAppendingPathComponent:@"index.html"];
        BOOL readable = [[NSFileManager defaultManager] isReadableFileAtPath:indexURL.path];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:indexURL.path error:NULL];
        CFSLog(@"indexURL=%@ readable=%d size=%@", indexURL, readable, attrs[NSFileSize]);
        [webView loadFileURL:indexURL allowingReadAccessToURL:wwwURL];
        CFSLog(@"loadFileURL issued");
    } else {
        CFSLog(@"!! www bundle dir not found");
        NSString *msg = @"<html><body style='font-family:-apple-system;padding:24px'>"
                        @"<h3>资源缺失</h3><p>www 目录未打进 App 包。</p></body></html>";
        [webView loadHTMLString:msg baseURL:nil];
    }

    CFSLog(@"=== launch end ===");
    return YES;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)navigation;
    CFSLog(@"nav: didStartProvisionalNavigation url=%@", webView.URL);
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    (void)navigation;
    CFSLog(@"nav: didCommit url=%@", webView.URL);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    CFSLog(@"nav: didFinish url=%@ title=%@", webView.URL, webView.title);
#ifdef CFS_DEBUG
    [self probePage:@"didFinish"];
#endif
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)navigation;
    CFSLog(@"nav: didFail %@ %@", error.domain, @(error.code));
    CFSLog(@"nav: didFail desc=%@", error.localizedDescription);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)navigation;
    CFSLog(@"nav: didFailProvisional %@ %@", error.domain, @(error.code));
    CFSLog(@"nav: didFailProvisional desc=%@", error.localizedDescription);
    CFSLog(@"nav: failing url=%@", error.userInfo[NSURLErrorFailingURLStringErrorKey]);
}

#ifdef CFS_DEBUG
- (void)probePage:(NSString *)tag {
    NSString *js =
        @"JSON.stringify({"
        @"ready:document.readyState,"
        @"title:document.title,"
        @"scripts:document.scripts.length,"
        @"appLen:(document.getElementById('app')||{innerHTML:''}).innerHTML.length,"
        @"bodyLen:document.body?document.body.innerHTML.length:-1,"
        @"hasGo:(typeof window.go),"
        @"hasRuntime:(typeof window.runtime),"
        @"appChildren:(document.getElementById('app')||{children:[]}).children.length,"
        @"bundleRan:(window.__cfs_bundle_ran||0),"
        @"ua:navigator.userAgent,iw:window.innerWidth,ih:window.innerHeight,dpr:window.devicePixelRatio,"
        @"text:(document.body.innerText||'').slice(0,260),"
        @"ctrl:(function(){try{var a=[];document.querySelectorAll('button,.btn,[class*=btn],[class*=tab],[class*=Tab],[class*=card],[class*=log]').forEach(function(b){var r=b.getBoundingClientRect();if(r.width>0&&r.height>0){a.push(((b.textContent||'').trim().slice(0,10)||b.className.toString().slice(0,14))+'@'+Math.round(r.x)+','+Math.round(r.y)+','+Math.round(r.width)+'x'+Math.round(r.height));}});return a.join(' | ');}catch(e){return 'ERR '+e.message}})()"
        @"})";
    [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        CFSLog(@"PROBE[%@] => %@ err=%@", tag, result, error.localizedDescription);
    }];
}
#endif

#pragma mark - cfscan:// 触发（测试与快捷指令）

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    (void)application;
    (void)options;
    CFSLog(@"openURL: %@", url.absoluteString);
    if (![url.scheme.lowercaseString isEqualToString:@"cfscan"]) return NO;

    NSURLComponents *comp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSString *> *q = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in comp.queryItems) {
        if (item.name && item.value) q[item.name.lowercaseString] = item.value;
    }

    NSString *action = url.host.lowercaseString ?: @"";
    int port = q[@"port"] ? q[@"port"].intValue : 443;

    if ([action isEqualToString:@"scan"]) {
        int v = q[@"v"] ? q[@"v"].intValue : 4;
        int w = q[@"w"] ? q[@"w"].intValue : 150;
        int sample = q[@"sample"] ? q[@"sample"].intValue : 1;
        int th = q[@"th"] ? q[@"th"].intValue : 1000;
        CFSLog(@"URL scan v=%d port=%d w=%d sample=%d th=%d", v, port, w, sample, th);
        if (v == 4) {
            [self.bridge.engine startScanWithVersion:4 port:port maxWorkers:w
                                    latencyThreshold:th v4Sample:sample v6Sample:1];
        } else {
            [self.bridge.engine startScanWithVersion:6 port:port maxWorkers:w
                                    latencyThreshold:th v4Sample:1 v6Sample:sample];
        }
        return YES;
    }
    if ([action isEqualToString:@"speed"]) {
        int n = q[@"n"] ? q[@"n"].intValue : 3;
        NSString *region = q[@"region"];
        CFSLog(@"URL speed n=%d port=%d region=%@", n, port, region);
        if (region.length) {
            [self.bridge.engine startRegionSpeedTestWithRegion:region maxCount:n port:port];
        } else {
            [self.bridge.engine startFullSpeedTestWithMaxCount:n port:port];
        }
        return YES;
    }
    if ([action isEqualToString:@"stop"]) {
        [self.bridge.engine stopScan];
        [self.bridge.engine stopSpeedTest];
        return YES;
    }
    return NO;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CFSAppDelegate class]));
    }
}
