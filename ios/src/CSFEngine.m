#import "CSFEngine.h"
#import "CSFIPGen.h"
#import "CSFLog.h"

#import <Network/Network.h>
#import <Security/Security.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <time.h>
#include <arpa/inet.h>

#pragma mark - 时间

static inline double cfs_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

#pragma mark - 地址解析

static BOOL cfs_resolve(const char *ip, int port, struct sockaddr_storage *ss, socklen_t *slen) {
    memset(ss, 0, sizeof(*ss));
    if (strchr(ip, ':')) {
        struct sockaddr_in6 *a = (struct sockaddr_in6 *)ss;
        a->sin6_family = AF_INET6;
        a->sin6_port = htons((uint16_t)port);
        if (inet_pton(AF_INET6, ip, &a->sin6_addr) != 1) return NO;
        *slen = sizeof(*a);
    } else {
        struct sockaddr_in *a = (struct sockaddr_in *)ss;
        a->sin_family = AF_INET;
        a->sin_port = htons((uint16_t)port);
        if (inet_pton(AF_INET, ip, &a->sin_addr) != 1) return NO;
        *slen = sizeof(*a);
    }
    return YES;
}

#pragma mark - TCP 握手测速（对应 Go 的 tcpPing）

static double cfs_tcp_ping(const char *ip, int port, double timeoutMs) {
    struct sockaddr_storage ss;
    socklen_t slen = 0;
    if (!cfs_resolve(ip, port, &ss, &slen)) return 0.0;

    int fd = socket(ss.ss_family, SOCK_STREAM, 0);
    if (fd < 0) return 0.0;

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) { close(fd); return 0.0; }

    double t0 = cfs_now_ms();
    int rc = connect(fd, (struct sockaddr *)&ss, slen);
    if (rc < 0 && errno != EINPROGRESS) { close(fd); return 0.0; }
    if (rc < 0) {
        struct pollfd pfd;
        pfd.fd = fd;
        pfd.events = POLLOUT;
        pfd.revents = 0;
        int pr = poll(&pfd, 1, (int)timeoutMs);
        if (pr <= 0) { close(fd); return 0.0; }
        int soerr = 0;
        socklen_t el = sizeof(soerr);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &el) < 0 || soerr != 0) { close(fd); return 0.0; }
    }
    double t1 = cfs_now_ms();
    close(fd);
    return t1 - t0;
}

#pragma mark - 裸 socket 收发（明文 colo 探测回退路径）

static NSData *cfs_plain_http(const char *ip, int port, const char *req, double connectMs, double readMs, NSUInteger maxBytes) {
    struct sockaddr_storage ss;
    socklen_t slen = 0;
    if (!cfs_resolve(ip, port, &ss, &slen)) return nil;

    int fd = socket(ss.ss_family, SOCK_STREAM, 0);
    if (fd < 0) return nil;

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) { close(fd); return nil; }

    int rc = connect(fd, (struct sockaddr *)&ss, slen);
    if (rc < 0 && errno != EINPROGRESS) { close(fd); return nil; }
    if (rc < 0) {
        struct pollfd pfd = { fd, POLLOUT, 0 };
        if (poll(&pfd, 1, (int)connectMs) <= 0) { close(fd); return nil; }
        int soerr = 0;
        socklen_t el = sizeof(soerr);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &el) < 0 || soerr != 0) { close(fd); return nil; }
    }

    size_t rl = strlen(req);
    size_t sent = 0;
    double deadline = cfs_now_ms() + connectMs + readMs;
    while (sent < rl) {
        ssize_t n = send(fd, req + sent, rl - sent, 0);
        if (n > 0) { sent += (size_t)n; continue; }
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd pfd = { fd, POLLOUT, 0 };
            if (poll(&pfd, 1, 500) <= 0) { close(fd); return nil; }
            continue;
        }
        close(fd);
        return nil;
    }

    NSMutableData *acc = [NSMutableData data];
    while (cfs_now_ms() < deadline && acc.length < maxBytes) {
        uint8_t buf[16384];
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n > 0) { [acc appendBytes:buf length:(NSUInteger)n]; continue; }
        if (n == 0) break;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            struct pollfd pfd = { fd, POLLIN, 0 };
            int pr = poll(&pfd, 1, 200);
            if (pr < 0) break;
            continue;
        }
        break;
    }
    close(fd);
    return acc;
}

#pragma mark - Network.framework 连接封装

@interface CSFNwConn : NSObject {
    nw_connection_t _conn;
    dispatch_queue_t _q;
}
@property (nonatomic, readonly) double readyMs;
- (instancetype)initWithHost:(NSString *)ip port:(int)port tls:(BOOL)tls SNI:(NSString *)sni;
- (BOOL)waitReadyMs:(double)timeoutMs;
- (BOOL)sendText:(NSString *)text timeoutMs:(double)t;
- (NSData *)readAllMaxBytes:(NSUInteger)maxBytes timeoutMs:(double)t;
- (int64_t)drainBodySeconds:(double)sec headerLen:(NSUInteger *)headerLenOut elapsedMs:(double *)elapsedOut;
- (void)cancel;
@end

@implementation CSFNwConn {
    double _readyMs;
}

- (instancetype)initWithHost:(NSString *)ip port:(int)port tls:(BOOL)tls SNI:(NSString *)sni {
    self = [super init];
    if (!self) return nil;
    _readyMs = -1.0;
    _q = dispatch_queue_create("cfs.nwconn", DISPATCH_QUEUE_SERIAL);

    NSString *portStr = [NSString stringWithFormat:@"%d", port];
    nw_endpoint_t ep = nw_endpoint_create_host(ip.UTF8String, portStr.UTF8String);

    nw_parameters_t params = NULL;
    if (tls) {
        NSString *sniCopy = [sni copy];
        params = nw_parameters_create_secure_tcp(^(nw_protocol_options_t tls_opt) {
            sec_protocol_options_t sec = nw_tls_copy_sec_protocol_options(tls_opt);
            if (sniCopy.length) {
                sec_protocol_options_set_tls_server_name(sec, sniCopy.UTF8String);
            }
            sec_protocol_options_set_verify_block(sec, ^(sec_protocol_metadata_t md, sec_trust_t tr, sec_protocol_verify_complete_t done) {
                done(true);
            }, _q);
            sec_protocol_options_add_tls_application_protocol(sec, "http/1.1");
        }, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    } else {
        params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    }
    /* TCP_NODELAY 由 Network.framework 默认处理 */

    _conn = nw_connection_create(ep, params);
    nw_connection_set_queue(_conn, _q);
    return self;
}

- (double)readyMs { return _readyMs; }

- (BOOL)waitReadyMs:(double)timeoutMs {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL ok = NO;
    double t0 = cfs_now_ms();
    nw_connection_set_state_changed_handler(_conn, ^(nw_connection_state_t st, nw_error_t err) {
        (void)err;
        if (st == nw_connection_state_ready) {
            ok = YES;
            self->_readyMs = cfs_now_ms() - t0;
            dispatch_semaphore_signal(sem);
        } else if (st == nw_connection_state_failed || st == nw_connection_state_cancelled) {
            dispatch_semaphore_signal(sem);
        }
    });
    nw_connection_start(_conn);
    dispatch_time_t dl = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutMs * (double)NSEC_PER_MSEC));
    if (dispatch_semaphore_wait(sem, dl) != 0) {
        nw_connection_cancel(_conn);
        return NO;
    }
    return ok;
}

- (BOOL)sendText:(NSString *)text timeoutMs:(double)t {
    NSData *d = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!d) return NO;
    dispatch_data_t dd = dispatch_data_create(d.bytes, d.length, _q, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL ok = NO;
    nw_connection_send(_conn, dd, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t err) {
        ok = (err == NULL);
        dispatch_semaphore_signal(sem);
    });
    dispatch_time_t dl = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * (double)NSEC_PER_MSEC));
    if (dispatch_semaphore_wait(sem, dl) != 0) return NO;
    return ok;
}

- (NSData *)readAllMaxBytes:(NSUInteger)maxBytes timeoutMs:(double)t {
    NSMutableData *acc = [NSMutableData data];
    double deadline = cfs_now_ms() + t;
    while (cfs_now_ms() < deadline && acc.length < maxBytes) {
        double left = deadline - cfs_now_ms();
        if (left < 1.0) break;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block BOOL fin = NO;
        nw_connection_receive(_conn, 1, 65536, ^(dispatch_data_t content, nw_content_context_t ctx, bool isComplete, nw_error_t err) {
            (void)ctx;
            if (content) {
                dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t off, const void *buf, size_t len) {
                    (void)region; (void)off;
                    [acc appendBytes:buf length:len];
                    return true;
                });
            }
            fin = (err != NULL || isComplete);
            dispatch_semaphore_signal(sem);
        });
        dispatch_time_t dl = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(left * (double)NSEC_PER_MSEC));
        if (dispatch_semaphore_wait(sem, dl) != 0) break;
        if (fin) break;
    }
    return acc;
}

/* 读到 HTTP header 结束，然后计时 sec 秒收 body。
 * headerLenOut 返回 header 总长（含空行），elapsedOut 返回实际计时时长。 */
- (int64_t)drainBodySeconds:(double)sec headerLen:(NSUInteger *)headerLenOut elapsedMs:(double *)elapsedOut {
    NSMutableData *acc = [NSMutableData data];
    NSData *sep = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger headerLen = 0;
    int64_t bodyBytes = 0;
    double t0 = 0.0;
    BOOL headerDone = NO;
    double deadline = cfs_now_ms() + 4000.0;   /* header 阶段最多 4 秒 */

    while (YES) {
        double now = cfs_now_ms();
        if (headerDone) {
            if (now - t0 >= sec * 1000.0) break;
        } else if (now > deadline) {
            break;
        }
        double wait = headerDone ? (sec * 1000.0 - (now - t0)) : 800.0;
        if (wait < 20.0) break;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block BOOL fin = NO;
        __block NSUInteger got = 0;
        nw_connection_receive(_conn, 1, 65536, ^(dispatch_data_t content, nw_content_context_t ctx, bool isComplete, nw_error_t err) {
            (void)ctx;
            if (content) {
                got = dispatch_data_get_size(content);
                if (!headerDone) {
                    dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t off, const void *buf, size_t len) {
                        (void)region; (void)off;
                        [acc appendBytes:buf length:len];
                        return true;
                    });
                }
            }
            fin = (err != NULL || isComplete);
            dispatch_semaphore_signal(sem);
        });
        dispatch_time_t dl = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * (double)NSEC_PER_MSEC));
        if (dispatch_semaphore_wait(sem, dl) != 0) {
            if (!headerDone) break;
            continue;   /* body 阶段：等不到数据继续等，直到窗口结束 */
        }

        if (!headerDone) {
            NSRange r = [acc rangeOfData:sep options:0 range:NSMakeRange(0, acc.length)];
            if (r.location != NSNotFound) {
                headerDone = YES;
                headerLen = r.location + r.length;
                bodyBytes = (int64_t)acc.length - (int64_t)headerLen;
                [acc setLength:0];
                t0 = cfs_now_ms();
            }
        } else {
            bodyBytes += (int64_t)got;
        }
        if (fin) break;
    }

    if (!headerDone && headerLen == 0) {
        NSRange r = [acc rangeOfData:sep options:0 range:NSMakeRange(0, acc.length)];
        if (r.location != NSNotFound) {
            headerLen = r.location + r.length;
            bodyBytes = (int64_t)acc.length - (int64_t)headerLen;
            t0 = cfs_now_ms();
            headerDone = YES;
        }
    }

    if (headerLenOut) *headerLenOut = headerLen;
    if (elapsedOut) *elapsedOut = headerDone ? (cfs_now_ms() - t0) : 0.0;
    return bodyBytes;
}

- (void)cancel {
    if (_conn) nw_connection_cancel(_conn);
}

@end

#pragma mark - colo 探测（对应 Go 的 getIataCodeSocket）

static NSString *cfs_colo_code(const char *ip, int port) {
    const char *req = "GET /cdn-cgi/trace HTTP/1.1\r\n"
                      "Host: speed.cloudflare.com\r\n"
                      "User-Agent: Mozilla/5.0\r\n"
                      "Connection: close\r\n\r\n";
    NSString *host = [NSString stringWithUTF8String:ip];

    for (int attempt = 0; attempt < 2; attempt++) {
        BOOL useTLS = (attempt == 0);
        NSData *resp = nil;

        if (useTLS) {
            CSFNwConn *c = [[CSFNwConn alloc] initWithHost:host port:port tls:YES SNI:@"speed.cloudflare.com"];
            if ([c waitReadyMs:2000.0] && [c sendText:[NSString stringWithUTF8String:req] timeoutMs:2000.0]) {
                resp = [c readAllMaxBytes:8192 timeoutMs:3000.0];
            }
            [c cancel];
        } else {
            resp = cfs_plain_http(ip, port, req, 2000.0, 3000.0, 8192);
        }

        if (resp.length == 0) continue;

        NSString *text = [[NSString alloc] initWithData:resp encoding:NSUTF8StringEncoding];
        if (!text) continue;

        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([trimmed hasPrefix:@"colo="]) {
                NSString *code = [[trimmed substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (code.length > 0 && ![code isEqualToString:@"UNKNOWN"]) {
                    return code.uppercaseString;
                }
            }
        }
    }
    return @"";
}

#pragma mark - 下载测速（对应 Go 的 downloadSpeedSocket）

static double cfs_download_speed(const char *ip, int port, double seconds) {
    const char *req = "GET /__down?bytes=50000000 HTTP/1.1\r\n"
                      "Host: speed.cloudflare.com\r\n"
                      "User-Agent: Mozilla/5.0\r\n"
                      "Accept: */*\r\n"
                      "Connection: close\r\n\r\n";
    NSString *host = [NSString stringWithUTF8String:ip];
    NSString *reqStr = [NSString stringWithUTF8String:req];

    BOOL tlsFirst = (port == 443 || port == 8443 || port == 2096);
    BOOL tried[2] = { tlsFirst, NO };

    for (int i = 0; i < 2; i++) {
        BOOL useTLS = tried[i];
        if (i == 1 && !tried[0] && !tried[1]) break;   /* 与 Go 相同：非 TLS 端口第二次是重复尝试，跳过 */

        CSFNwConn *c = [[CSFNwConn alloc] initWithHost:host port:port tls:useTLS SNI:(useTLS ? @"speed.cloudflare.com" : nil)];
        BOOL ready = [c waitReadyMs:3000.0];
        if (!ready) { [c cancel]; continue; }
        if (![c sendText:reqStr timeoutMs:3000.0]) { [c cancel]; continue; }

        NSUInteger headerLen = 0;
        double elapsedMs = 0.0;
        int64_t bodyBytes = [c drainBodySeconds:seconds headerLen:&headerLen elapsedMs:&elapsedMs];
        [c cancel];

        if (headerLen == 0) continue;

        double e = elapsedMs / 1000.0;
        if (e < 0.1) e = 0.1;
        return (double)bodyBytes / (1024.0 * 1024.0) / e;
    }
    return 0.0;
}

#pragma mark - 排序（照抄 Go 的冒泡实现）

static NSArray<NSDictionary *> *cfs_sort_by_latency(NSArray<NSDictionary *> *arr) {
    NSMutableArray *a = [arr mutableCopy];
    NSUInteger n = a.count;
    for (NSUInteger i = 0; i + 1 < n; i++) {
        for (NSUInteger j = i + 1; j < n; j++) {
            double li = [a[i][@"latencyMs"] doubleValue];
            double lj = [a[j][@"latencyMs"] doubleValue];
            if (li > lj) [a exchangeObjectAtIndex:i withObjectAtIndex:j];
        }
    }
    return a;
}

static NSArray<NSDictionary *> *cfs_sort_by_speed_desc(NSArray<NSDictionary *> *arr) {
    NSMutableArray *a = [arr mutableCopy];
    NSUInteger n = a.count;
    for (NSUInteger i = 0; i + 1 < n; i++) {
        for (NSUInteger j = i + 1; j < n; j++) {
            double si = [a[i][@"downloadSpeed"] doubleValue];
            double sj = [a[j][@"downloadSpeed"] doubleValue];
            if (si < sj) [a exchangeObjectAtIndex:i withObjectAtIndex:j];
        }
    }
    return a;
}

#pragma mark - CSFEngine

@interface CSFEngine ()
@property (atomic) BOOL scanning;
@property (atomic) BOOL speedTesting;
@property (atomic) BOOL scanStopFlag;
@property (atomic) BOOL speedStopFlag;
@end

@implementation CSFEngine {
    NSMutableArray<NSDictionary *> *_lastResults;
    NSLock *_stateLock;
    double _lastProgressMs;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _lastResults = [NSMutableArray array];
    _stateLock = [NSLock new];
    _lastProgressMs = 0.0;
    return self;
}

- (void)logLine:(NSString *)msg {
    CFSLog(@"[ENGINE] %@", msg);
    CSFLogBlock cb = self.onLog;
    if (cb) cb(msg);
}

- (void)emitScanProgress:(NSInteger)cur total:(NSInteger)total found:(NSInteger)found startMs:(double)start {
    if (cur != total) {
        double now = cfs_now_ms();
        if (now - _lastProgressMs < 100.0) return;
        _lastProgressMs = now;
    }
    double elapsed = (cfs_now_ms() - start) / 1000.0;
    double speed = (elapsed > 0.0) ? ((double)cur / elapsed) : 0.0;
    CSFScanProgressBlock cb = self.onProgress;
    if (cb) cb(cur, total, found, speed);
}

#pragma mark 扫描

- (void)startScanWithVersion:(int)version
                        port:(int)port
                  maxWorkers:(int)maxWorkers
            latencyThreshold:(int)threshold
                  v4Sample:(int)v4Sample
                  v6Sample:(int)v6Sample {
    if (self.scanning || self.speedTesting) {
        [self logLine:@"已有任务正在执行，请先停止"];
        return;
    }
    self.scanning = YES;
    self.scanStopFlag = NO;

    [self logLine:[NSString stringWithFormat:
                   @"开始 IPv%d 扫描，端口: %d，并发: %d，延迟上限: %d ms，V4采样: %d，V6采样: %d",
                   version, port, maxWorkers, threshold, v4Sample, v6Sample]];

    int w = maxWorkers < 1 ? 1 : (maxWorkers > 300 ? 300 : maxWorkers);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self runScanVersion:version port:port workers:w threshold:threshold v4:v4Sample v6:v6Sample];
    });
}

- (void)runScanVersion:(int)version port:(int)port workers:(int)workers
             threshold:(int)threshold v4:(int)v4 v6:(int)v6 {
    [self logLine:[NSString stringWithFormat:@"正在从Cloudflare IPv%d IP段生成随机IP... (端口: %d)", version, port]];

    NSArray<NSString *> *ips = (version == 4) ? CSFGenerateIPv4(v4) : CSFGenerateIPv6(v6);
    if (ips.count == 0) {
        [self logLine:[NSString stringWithFormat:@"错误: 未能生成IPv%d IP列表", version]];
        self.scanning = NO;
        CSFScanCompleteBlock done = self.onScanComplete;
        if (done) done(@[]);
        return;
    }

    [self logLine:[NSString stringWithFormat:@"已生成 %d 个随机IPv%d IP", (int)ips.count, version]];
    [self logLine:[NSString stringWithFormat:@"开始延迟测试 %d 个IPv%d IP...", (int)ips.count, version]];

    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    NSLock *lock = [NSLock new];
    dispatch_semaphore_t sem = dispatch_semaphore_create(workers);
    dispatch_group_t group = dispatch_group_create();

    __block NSInteger completed = 0;
    __block NSInteger found = 0;
    double startMs = cfs_now_ms();
    NSInteger total = (NSInteger)ips.count;

    for (NSString *ip in ips) {
        if (self.scanStopFlag) break;

        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        if (self.scanStopFlag) {
            dispatch_semaphore_signal(sem);
            break;
        }
        dispatch_group_enter(group);
        NSString *ipCopy = [ip copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                double latency = cfs_tcp_ping(ipCopy.UTF8String, port, 1000.0);

                if (latency <= 0.0 || latency > (double)threshold) {
                    [lock lock];
                    completed++;
                    [self emitScanProgress:completed total:total found:found startMs:startMs];
                    [lock unlock];
                    dispatch_semaphore_signal(sem);
                    dispatch_group_leave(group);
                    return;
                }

                NSString *iata = cfs_colo_code(ipCopy.UTF8String, port);
                NSString *cn = [CSFEngine chineseNameForIata:iata];
                if (iata.length == 0) {
                    iata = @"UNKNOWN";
                    cn = @"未知地区";
                }

                NSDictionary *row = @{
                    @"ip": ipCopy,
                    @"port": @(port),
                    @"latencyMs": @(latency),
                    @"iataCode": iata,
                    @"chineseName": cn,
                    @"success": @YES
                };

                [lock lock];
                [results addObject:row];
                found++;
                completed++;
                [self emitScanProgress:completed total:total found:found startMs:startMs];
                CSFScanResultBlock rcb = self.onResult;
                if (rcb) rcb(row);
                [lock unlock];

                dispatch_semaphore_signal(sem);
                dispatch_group_leave(group);
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    [lock lock];
    NSArray *final = [results copy];
    [lock unlock];

    [_stateLock lock];
    _lastResults = [final mutableCopy];
    [_stateLock unlock];

    self.scanning = NO;
    self.scanStopFlag = NO;

    [self logLine:[NSString stringWithFormat:@"扫描结束，共发现 %d 个可用IP", (int)final.count]];
    CSFScanCompleteBlock done = self.onScanComplete;
    if (done) done(final);
}

- (void)stopScan {
    if (self.scanning) {
        self.scanStopFlag = YES;
        [self logLine:@"正在停止扫描..."];
    }
}

#pragma mark 测速

- (void)startFullSpeedTestWithMaxCount:(int)maxCount port:(int)port {
    if (self.speedTesting || self.scanning) {
        [self logLine:@"请先停止当前任务"];
        return;
    }
    NSArray *last = [self lastScanResults];
    if (last.count == 0) {
        [self logLine:@"没有可用的 IP，请先进行扫描"];
        return;
    }
    self.speedTesting = YES;
    self.speedStopFlag = NO;
    [self logLine:[NSString stringWithFormat:@"开始完全测速，测速数量: %d，端口: %d", maxCount, port]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self runSpeedTest:last region:nil maxCount:maxCount port:port];
    });
}

- (void)startRegionSpeedTestWithRegion:(NSString *)region maxCount:(int)maxCount port:(int)port {
    if (self.speedTesting || self.scanning) {
        [self logLine:@"请先停止当前任务"];
        return;
    }
    NSArray *last = [self lastScanResults];
    if (last.count == 0) {
        [self logLine:@"没有可用的 IP，请先进行扫描"];
        return;
    }
    NSString *code = [region uppercaseString];
    self.speedTesting = YES;
    self.speedStopFlag = NO;
    [self logLine:[NSString stringWithFormat:@"开始地区测速: %@ (%@)，测速数量: %d，端口: %d",
                   code, [CSFEngine chineseNameForIata:code], maxCount, port]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self runSpeedTest:last region:code maxCount:maxCount port:port];
    });
}

- (void)runSpeedTest:(NSArray<NSDictionary *> *)all region:(NSString *)region maxCount:(int)maxCount port:(int)port {
    NSArray<NSDictionary *> *targets = nil;

    if (region.length > 0) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *r in all) {
            NSString *code = r[@"iataCode"];
            if ([code caseInsensitiveCompare:region] == NSOrderedSame) [filtered addObject:r];
        }
        if (filtered.count == 0) {
            [self logLine:[NSString stringWithFormat:@"未找到地区 %@ 的 IP", region]];
            self.speedTesting = NO;
            CSFSpeedCompleteBlock done = self.onSpeedComplete;
            if (done) done(@[]);
            return;
        }
        [self logLine:[NSString stringWithFormat:@"地区 %@ (%@) 共找到 %d 个 IP",
                       region, [CSFEngine chineseNameForIata:region], (int)filtered.count]];
        targets = filtered;
    } else {
        targets = all;
        [self logLine:[NSString stringWithFormat:@"完全测速，共 %d 个 IP", (int)targets.count]];
    }

    targets = cfs_sort_by_latency(targets);
    if (maxCount > 0 && (NSInteger)targets.count > maxCount) {
        targets = [targets subarrayWithRange:NSMakeRange(0, (NSUInteger)maxCount)];
    }

    NSInteger total = (NSInteger)targets.count;
    [self logLine:[NSString stringWithFormat:@"将对 %d 个IP进行测速", (int)total]];

    NSMutableArray<NSDictionary *> *speedResults = [NSMutableArray array];

    for (NSInteger idx = 0; idx < total; idx++) {
        if (self.speedStopFlag) break;
        NSDictionary *target = targets[(NSUInteger)idx];
        NSString *ip = target[@"ip"];

        [self logLine:[NSString stringWithFormat:@"[%d/%d] 正在测速 %@ (端口: %d)", (int)(idx + 1), (int)total, ip, port]];

        double speed = cfs_download_speed(ip.UTF8String, port, 3.0);

        NSString *iata = target[@"iataCode"];
        if (iata.length == 0) iata = @"UNKNOWN";
        NSString *cn = [CSFEngine chineseNameForIata:iata];

        NSDictionary *row = @{
            @"ip": ip,
            @"port": @(port),
            @"latencyMs": target[@"latencyMs"] ?: @(0.0),
            @"downloadSpeed": @(speed),
            @"iataCode": iata,
            @"chineseName": cn,
            @"testType": (region.length > 0 ? @"地区测速" : @"完全测速")
        };
        [speedResults addObject:row];

        CSFSpeedProgressBlock pcb = self.onSpeedProgress;
        if (pcb) pcb(idx + 1, total);

        [self logLine:[NSString stringWithFormat:@"  测速结果: %.2f MB/s, 地区: %@", speed, cn]];

        usleep(300 * 1000);   /* 与 Go 相同：测完一个歇 300ms，避免服务端限流 */
    }

    NSArray *sorted = cfs_sort_by_speed_desc(speedResults);

    self.speedTesting = NO;
    self.speedStopFlag = NO;

    [self logLine:[NSString stringWithFormat:@"测速完成，成功测速 %d 个 IP", (int)sorted.count]];
    CSFSpeedCompleteBlock done = self.onSpeedComplete;
    if (done) done(sorted);
}

- (void)stopSpeedTest {
    if (self.speedTesting) {
        self.speedStopFlag = YES;
        [self logLine:@"正在停止测速..."];
    }
}

- (NSArray<NSDictionary *> *)lastScanResults {
    [_stateLock lock];
    NSArray *copy = [_lastResults copy];
    [_stateLock unlock];
    return copy;
}

#pragma mark - IATA 表（与 Go 版 utils.go 逐条一致）

+ (NSString *)chineseNameForIata:(NSString *)code {
    if (code.length == 0) return @"";
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"HKG": @"香港", @"TPE": @"台北", @"KHH": @"高雄", @"MFM": @"澳门",
            @"NRT": @"东京", @"HND": @"东京", @"KIX": @"大阪", @"NGO": @"名古屋",
            @"FUK": @"福冈", @"CTS": @"札幌", @"OKA": @"冲绳",
            @"ICN": @"首尔", @"GMP": @"首尔", @"PUS": @"釜山",
            @"SIN": @"新加坡", @"BKK": @"曼谷", @"DMK": @"曼谷",
            @"KUL": @"吉隆坡", @"HKT": @"普吉岛",
            @"MNL": @"马尼拉", @"CEB": @"宿务",
            @"HAN": @"河内", @"SGN": @"胡志明市",
            @"JKT": @"雅加达", @"DPS": @"巴厘岛",
            @"DEL": @"德里", @"BOM": @"孟买", @"MAA": @"金奈",
            @"DXB": @"迪拜", @"AUH": @"阿布扎比",
            @"SJC": @"圣何塞", @"LAX": @"洛杉矶", @"SFO": @"旧金山",
            @"SEA": @"西雅图", @"PDX": @"波特兰",
            @"LAS": @"拉斯维加斯", @"PHX": @"菲尼克斯",
            @"DEN": @"丹佛", @"DFW": @"达拉斯", @"IAH": @"休斯顿",
            @"ORD": @"芝加哥", @"MSP": @"明尼阿波利斯",
            @"ATL": @"亚特兰大", @"MIA": @"迈阿密", @"MCO": @"奥兰多",
            @"JFK": @"纽约", @"EWR": @"纽约", @"LGA": @"纽约",
            @"BOS": @"波士顿", @"PHL": @"费城", @"IAD": @"华盛顿",
            @"YYZ": @"多伦多", @"YVR": @"温哥华", @"YUL": @"蒙特利尔",
            @"LHR": @"伦敦", @"LGW": @"伦敦", @"STN": @"伦敦",
            @"CDG": @"巴黎", @"ORY": @"巴黎",
            @"FRA": @"法兰克福", @"MUC": @"慕尼黑", @"TXL": @"柏林",
            @"AMS": @"阿姆斯特丹", @"EIN": @"埃因霍温",
            @"MAD": @"马德里", @"BCN": @"巴塞罗那",
            @"FCO": @"罗马", @"MXP": @"米兰", @"LIN": @"米兰",
            @"ZRH": @"苏黎世", @"GVA": @"日内瓦",
            @"VIE": @"维也纳", @"PRG": @"布拉格",
            @"WAW": @"华沙", @"KRK": @"克拉科夫",
            @"HEL": @"赫尔辛基", @"OSL": @"奥斯陆", @"ARN": @"斯德哥尔摩",
            @"CPH": @"哥本哈根",
            @"SYD": @"悉尼", @"MEL": @"墨尔本", @"BNE": @"布里斯班",
            @"PER": @"珀斯", @"ADL": @"阿德莱德",
            @"AKL": @"奥克兰", @"WLG": @"惠灵顿",
            @"GRU": @"圣保罗", @"GIG": @"里约热内卢", @"EZE": @"布宜诺斯艾利斯",
            @"SCL": @"圣地亚哥", @"LIM": @"利马", @"BOG": @"波哥大",
            @"JNB": @"约翰内斯堡", @"CPT": @"开普敦", @"CAI": @"开罗",
        };
    });
    NSString *name = map[code];
    return name ?: code;
}

@end
