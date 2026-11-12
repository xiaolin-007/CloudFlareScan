#import "CSFIPGen.h"

#include <arpa/inet.h>
#include <string.h>

/* 与 Go 版 ipgen.go 完全一致的 CIDR 表 */
static const char *kCFIPv4CIDRs[] = {
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
    "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
    "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/12",
    "172.64.0.0/17", "172.64.128.0/18", "172.64.192.0/19", "172.64.224.0/22",
    "172.64.229.0/24", "172.64.230.0/23", "172.64.232.0/21", "172.64.240.0/21",
    "172.64.248.0/21", "172.65.0.0/16", "172.66.0.0/16", "172.67.0.0/16",
    "131.0.72.0/22", "8.35.211.0/24", "188.164.248.0/24",
};
static const int kCFIPv4CIDRCount = (int)(sizeof(kCFIPv4CIDRs) / sizeof(kCFIPv4CIDRs[0]));

static const char *kCFIPv6CIDRs[] = {
    "2400:cb00:2049::/48", "2400:cb00:f00e::/48", "2606:4700::/32",
    "2606:4700:10::/48", "2606:4700:130::/48", "2606:4700:3000::/48",
    "2606:4700:3001::/48", "2606:4700:3002::/48", "2606:4700:3003::/48",
    "2606:4700:3004::/48", "2606:4700:3005::/48", "2606:4700:3006::/48",
    "2606:4700:3007::/48", "2606:4700:3008::/48", "2606:4700:3009::/48",
    "2606:4700:3010::/48", "2606:4700:3011::/48", "2606:4700:3012::/48",
    "2606:4700:3013::/48", "2606:4700:3014::/48", "2606:4700:3015::/48",
    "2606:4700:3016::/48", "2606:4700:3017::/48", "2606:4700:3018::/48",
    "2606:4700:3019::/48", "2606:4700:3020::/48", "2606:4700:3021::/48",
    "2606:4700:3022::/48", "2606:4700:3023::/48", "2606:4700:3024::/48",
    "2606:4700:3025::/48", "2606:4700:3026::/48", "2606:4700:3027::/48",
    "2606:4700:3028::/48", "2606:4700:3029::/48", "2606:4700:3030::/48",
    "2606:4700:3031::/48", "2606:4700:3032::/48", "2606:4700:3033::/48",
    "2606:4700:3034::/48", "2606:4700:3035::/48", "2606:4700:3036::/48",
    "2606:4700:5a::/48", "2606:4700:52::/48", "2606:4700:57::/48",
    "2606:4700:a0::/48", "2606:4700:a1::/48", "2606:4700:a8::/48",
    "2606:4700:a9::/48", "2606:4700:a::/48", "2606:4700:b::/48",
    "2606:4700:c::/48", "2606:4700:d0::/48", "2606:4700:d1::/48",
    "2606:4700:d::/48", "2606:4700:e0::/48", "2606:4700:e1::/48",
    "2606:4700:e2::/48", "2606:4700:e3::/48", "2606:4700:e4::/48",
    "2606:4700:e5::/48", "2606:4700:e6::/48", "2606:4700:e7::/48",
    "2606:4700:e::/48", "2606:4700:f1::/48", "2606:4700:f2::/48",
    "2606:4700:f3::/48", "2606:4700:f4::/48", "2606:4700:f5::/48",
    "2606:4700:f::/48", "2803:f800:50::/48", "2803:f800:51::/48",
    "2a06:98c1:3100::/48", "2a06:98c1:3101::/48", "2a06:98c1:3102::/48",
    "2a06:98c1:3103::/48", "2a06:98c1:3104::/48", "2a06:98c1:3105::/48",
    "2a06:98c1:3106::/48", "2a06:98c1:3107::/48", "2a06:98c1:3108::/48",
    "2a06:98c1:3109::/48", "2a06:98c1:310a::/48", "2a06:98c1:310b::/48",
    "2a06:98c1:310c::/48", "2a06:98c1:310d::/48", "2a06:98c1:310e::/48",
    "2a06:98c1:310f::/48", "2a06:98c1:3120::/48", "2a06:98c1:3121::/48",
    "2a06:98c1:3122::/48", "2a06:98c1:3123::/48", "2a06:98c1:3200::/48",
    "2a06:98c1:50::/48", "2a06:98c1:51::/48", "2a06:98c1:54::/48",
    "2a06:98c1:58::/48",
};
static const int kCFIPv6CIDRCount = (int)(sizeof(kCFIPv6CIDRs) / sizeof(kCFIPv6CIDRs[0]));

#pragma mark - IPv4

/* 在 net/prefix 子网里随机取一个主机地址（主机位全 0 时 +1，等价 Go 的 randomIP） */
static NSString *CSFRandomV4(uint32_t net, int prefix) {
    uint32_t mask = (prefix <= 0) ? 0u : (0xFFFFFFFFu << (32 - prefix));
    if (prefix >= 32) mask = 0xFFFFFFFFu;
    uint32_t hostMask = ~mask;
    uint32_t val = (net & mask) | (arc4random() & hostMask);
    if ((val & hostMask) == 0) val += 1u;

    struct in_addr a;
    a.s_addr = htonl(val);
    char buf[INET_ADDRSTRLEN];
    if (!inet_ntop(AF_INET, &a, buf, sizeof(buf))) return @"";
    return [NSString stringWithUTF8String:buf];
}

NSArray<NSString *> *CSFGenerateIPv4(int sample) {
    if (sample <= 0) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];

    for (int ci = 0; ci < kCFIPv4CIDRCount; ci++) {
        const char *cidr = kCFIPv4CIDRs[ci];
        const char *slash = strchr(cidr, '/');
        if (!slash) continue;
        char ipbuf[64];
        size_t n = (size_t)(slash - cidr);
        if (n >= sizeof(ipbuf)) continue;
        memcpy(ipbuf, cidr, n);
        ipbuf[n] = '\0';
        int prefix = atoi(slash + 1);
        if (prefix < 0 || prefix > 32) continue;

        struct in_addr base;
        if (inet_pton(AF_INET, ipbuf, &base) != 1) continue;
        uint32_t net = ntohl(base.s_addr);

        if (prefix >= 24) {
            for (int i = 0; i < sample; i++) {
                NSString *s = CSFRandomV4(net, prefix);
                if (s.length) [out addObject:s];
            }
        } else {
            uint32_t subnets = 1u << (24 - prefix);
            for (uint32_t j = 0; j < subnets; j++) {
                uint32_t sub = net + (j << 8);
                for (int i = 0; i < sample; i++) {
                    NSString *s = CSFRandomV4(sub, 24);
                    if (s.length) [out addObject:s];
                }
            }
        }
    }
    return out;
}

#pragma mark - IPv6

static NSString *CSFRandomV6(const struct in6_addr *net, int prefix) {
    uint8_t outb[16];
    uint8_t netb[16];
    memcpy(netb, net->s6_addr, 16);

    for (int i = 0; i < 16; i++) {
        int bits = prefix - i * 8;
        uint8_t m;
        if (bits >= 8) m = 0xFF;
        else if (bits <= 0) m = 0x00;
        else m = (uint8_t)(0xFF << (8 - bits));
        outb[i] = (uint8_t)((netb[i] & m) | ((uint8_t)arc4random_uniform(256) & (uint8_t)~m));
    }

    BOOL isNetwork = YES;
    for (int i = 0; i < 16; i++) {
        int bits = prefix - i * 8;
        uint8_t m;
        if (bits >= 8) m = 0xFF;
        else if (bits <= 0) m = 0x00;
        else m = (uint8_t)(0xFF << (8 - bits));
        if (outb[i] != (netb[i] & m)) { isNetwork = NO; break; }
    }
    if (isNetwork) {
        for (int i = 15; i >= 0; i--) {
            outb[i] += 1;
            if (outb[i] != 0) break;
        }
    }

    char buf[INET6_ADDRSTRLEN];
    if (!inet_ntop(AF_INET6, outb, buf, sizeof(buf))) return @"";
    return [NSString stringWithUTF8String:buf];
}

NSArray<NSString *> *CSFGenerateIPv6(int sample) {
    if (sample <= 0) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];

    for (int ci = 0; ci < kCFIPv6CIDRCount; ci++) {
        const char *cidr = kCFIPv6CIDRs[ci];
        const char *slash = strchr(cidr, '/');
        if (!slash) continue;
        char ipbuf[128];
        size_t n = (size_t)(slash - cidr);
        if (n >= sizeof(ipbuf)) continue;
        memcpy(ipbuf, cidr, n);
        ipbuf[n] = '\0';
        int prefix = atoi(slash + 1);
        if (prefix < 0 || prefix > 128) continue;

        struct in6_addr base;
        if (inet_pton(AF_INET6, ipbuf, &base) != 1) continue;

        for (int i = 0; i < sample; i++) {
            NSString *s = CSFRandomV6(&base, prefix);
            if (s.length) [out addObject:s];
        }
    }
    return out;
}
