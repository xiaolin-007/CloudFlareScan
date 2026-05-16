import sys
import random
import time
import ipaddress
import asyncio
import aiohttp
import socket
import ssl
from datetime import datetime
from typing import List, Optional, Dict
import csv

from PySide6.QtWidgets import (
    QApplication, QWidget, QLabel, QPushButton,
    QLineEdit, QProgressBar, QVBoxLayout, QHBoxLayout,
    QTextEdit, QComboBox, QFileDialog, QMessageBox,
    QScrollArea, QFrame, QStackedWidget, QDialog, QDialogButtonBox
)
from PySide6.QtCore import Qt, QThread, Signal, QTimer
from PySide6.QtGui import QFont, QIcon, QIntValidator
import os
import platform


def get_system_font():
    system = platform.system()
    if system == "Windows":
        return "Microsoft YaHei"
    elif system == "Darwin":
        return "PingFang SC"
    else:
        return "DejaVu Sans"

SYSTEM_FONT = get_system_font()

FONT_TITLE = QFont(SYSTEM_FONT, 28)
FONT_TITLE.setBold(True)
FONT_BTN = QFont(SYSTEM_FONT, 11)
FONT_STATUS = QFont(SYSTEM_FONT, 10)

BTN_W = 120
BTN_H = 32
SPACING = 8


LINE_EDIT_STYLE = f"""
    QLineEdit {{
        background: white;
        border: 1px solid #D1D5DB;
        border-radius: 6px;
        padding: 0px 5px;
        font-family: "{SYSTEM_FONT}";
        color: #111827;
    }}
    QLineEdit:focus {{
        border-color: #F97316;
    }}
"""

COMBO_BOX_STYLE = f"""
    QComboBox {{
        background: white;
        border: 1px solid #D1D5DB;
        border-radius: 6px;
        padding: 0px 5px;
        font-family: "{SYSTEM_FONT}";
        color: #111827;
    }}
    QComboBox:focus {{
        border-color: #F97316;
    }}
    QComboBox::drop-down {{
        subcontrol-origin: padding;
        subcontrol-position: top right;
        width: 20px;
        border: none;
        border-top-right-radius: 5px;
        border-bottom-right-radius: 5px;
    }}
"""


SCROLLBAR_STYLE = """
    QScrollBar:vertical {
        background: #0F4C75;
        width: 8px;
        border-radius: 3px;
    }
    QScrollBar::handle:vertical {
        background: #1E90FF;
        min-height: 20px;
        border-radius: 3px;
    }
    QScrollBar::handle:vertical:hover {
        background: #00BFFF;
    }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        height: 0px;
    }
    QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {
        background: none;
    }
"""


CF_IPV4_CIDRS = [
    "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "104.16.0.0/13",
	"104.24.0.0/14", "108.162.192.0/18", "131.0.72.0/22", "141.101.64.0/18",
	"162.158.0.0/15", "172.64.0.0/13", "173.245.48.0/20", "188.114.96.0/20",
	"190.93.240.0/20", "197.234.240.0/22", "198.41.128.0/17"
]

CF_IPV6_CIDRS = [
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
    "2a06:98c1:58::/48"
]


AIRPORT_CODES = {
    "HKG": "香港", "TPE": "台北", "KHH": "高雄", "MFM": "澳门",
    "NRT": "东京", "HND": "东京", "KIX": "大阪", "NGO": "名古屋",
    "FUK": "福冈", "CTS": "札幌", "OKA": "冲绳",
    "ICN": "首尔", "GMP": "首尔", "PUS": "釜山",
    "SIN": "新加坡", "BKK": "曼谷", "DMK": "曼谷",
    "KUL": "吉隆坡", "HKT": "普吉岛",
    "MNL": "马尼拉", "CEB": "宿务",
    "HAN": "河内", "SGN": "胡志明市",
    "JKT": "雅加达", "DPS": "巴厘岛",
    "DEL": "德里", "BOM": "孟买", "MAA": "金奈",
    "DXB": "迪拜", "AUH": "阿布扎比",
    "SJC": "圣何塞", "LAX": "洛杉矶", "SFO": "旧金山",
    "SEA": "西雅图", "PDX": "波特兰",
    "LAS": "拉斯维加斯", "PHX": "菲尼克斯",
    "DEN": "丹佛", "DFW": "达拉斯", "IAH": "休斯顿",
    "ORD": "芝加哥", "MSP": "明尼阿波利斯",
    "ATL": "亚特兰大", "MIA": "迈阿密", "MCO": "奥兰多",
    "JFK": "纽约", "EWR": "纽约", "LGA": "纽约",
    "BOS": "波士顿", "PHL": "费城", "IAD": "华盛顿",
    "YYZ": "多伦多", "YVR": "温哥华", "YUL": "蒙特利尔",
    "LHR": "伦敦", "LGW": "伦敦", "STN": "伦敦",
    "CDG": "巴黎", "ORY": "巴黎",
    "FRA": "法兰克福", "MUC": "慕尼黑", "TXL": "柏林",
    "AMS": "阿姆斯特丹", "EIN": "埃因霍温",
    "MAD": "马德里", "BCN": "巴塞罗那",
    "FCO": "罗马", "MXP": "米兰", "LIN": "米兰",
    "ZRH": "苏黎世", "GVA": "日内瓦",
    "VIE": "维也纳", "PRG": "布拉格",
    "WAW": "华沙", "KRK": "克拉科夫",
    "HEL": "赫尔辛基", "OSL": "奥斯陆", "ARN": "斯德哥尔摩",
    "CPH": "哥本哈根",
    "SYD": "悉尼", "MEL": "墨尔本", "BNE": "布里斯班",
    "PER": "珀斯", "ADL": "阿德莱德",
    "AKL": "奥克兰", "WLG": "惠灵顿",
    "GRU": "圣保罗", "GIG": "里约热内卢", "EZE": "布宜诺斯艾利斯",
    "SCL": "圣地亚哥", "LIM": "利马", "BOG": "波哥大",
    "JNB": "约翰内斯堡", "CPT": "开普敦", "CAI": "开罗",
}

PORT_OPTIONS = ["443", "2053", "2083", "2087", "2096", "8443"]


IPV4_IPS_PER_SUBNET = 1
IPV6_IPS_PER_CIDR = 100


def get_iata_translation(iata_code: str) -> str:
    return AIRPORT_CODES.get(iata_code, iata_code if iata_code else "未知地区")

def get_iata_code_from_ip(ip: str, timeout: int = 3) -> Optional[str]:
    test_host = "speed.cloudflare.com"
    urls = (f"http://[{ip}]/cdn-cgi/trace", f"https://[{ip}]/cdn-cgi/trace") if ':' in ip else (f"http://{ip}/cdn-cgi/trace", f"https://{ip}/cdn-cgi/trace")
    for url in urls:
        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            use_ssl = url.startswith('https://')
            if '[' in url and ']' in url:
                host = url[8:].split('/')[0].strip('[]') if use_ssl else url[7:].split('/')[0].strip('[]')
            else:
                host = url[8:].split('/')[0] if use_ssl else url[7:].split('/')[0]
            port = 443 if use_ssl else 80
            if ':' in host:
                addrinfo = socket.getaddrinfo(host, port, socket.AF_INET6, socket.SOCK_STREAM)
                s = socket.socket(addrinfo[0][0], addrinfo[0][1], addrinfo[0][2])
                s.settimeout(timeout)
                s.connect(addrinfo[0][4])
            else:
                s = socket.create_connection((host, port), timeout=timeout)
            if use_ssl:
                s = ctx.wrap_socket(s, server_hostname=test_host)
            req = f"GET /cdn-cgi/trace HTTP/1.1\r\nHost: {test_host}\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n".encode()
            s.sendall(req)
            data = b""
            while True:
                try:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                    if b"\r\n\r\n" in data:
                        break
                except socket.timeout:
                    break
            s.close()
            response = data.decode('utf-8', errors='ignore')
            for line in response.splitlines():
                if line.startswith('colo='):
                    colo = line.split('=', 1)[1].strip()
                    if colo and colo.upper() != 'UNKNOWN':
                        return colo.upper()
            if b'CF-RAY' in data:
                cf_ray = data.decode('utf-8', errors='ignore').split('CF-RAY:', 1)[1].split('\r\n', 1)[0].strip()
                if '-' in cf_ray:
                    parts = cf_ray.split('-')
                    for part in parts[-2:]:
                        if len(part) == 3 and part.isalpha():
                            return part.upper()
        except Exception:
            continue
    return None

async def get_iata_code_async(session: aiohttp.ClientSession, ip: str, timeout: int = 3) -> Optional[str]:
    test_host = "speed.cloudflare.com"
    urls = (f"http://[{ip}]/cdn-cgi/trace", f"https://[{ip}]/cdn-cgi/trace") if ':' in ip else (f"http://{ip}/cdn-cgi/trace", f"https://{ip}/cdn-cgi/trace")
    headers = {"User-Agent": "Mozilla/5.0", "Host": test_host}
    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE
    for url in urls:
        try:
            async with session.get(url, headers=headers, ssl=ssl_ctx if url.startswith('https://') else None,
                                   timeout=aiohttp.ClientTimeout(total=timeout), allow_redirects=False) as resp:
                if resp.status == 200:
                    text = await resp.text()
                    for line in text.strip().split('\n'):
                        if line.startswith('colo='):
                            colo = line.split('=', 1)[1].strip()
                            if colo and colo.upper() != 'UNKNOWN':
                                return colo.upper()
                    if 'CF-RAY' in resp.headers:
                        cf_ray = resp.headers['CF-RAY']
                        if '-' in cf_ray:
                            for part in cf_ray.split('-')[-2:]:
                                if len(part) == 3 and part.isalpha():
                                    return part.upper()
        except Exception:
            continue
    return None

async def async_tcp_ping(ip: str, port: int, timeout: float = 1.0) -> Optional[float]:
    start = time.monotonic()
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(ip, port), timeout=timeout)
        latency = (time.monotonic() - start) * 1000
        writer.close()
        await writer.wait_closed()
        return round(latency, 2)
    except Exception:
        return None

async def measure_tcp_latency(ip: str, port: int, ping_times: int = 2, timeout: float = 1.0) -> Optional[float]:
    latencies = []
    for i in range(ping_times):
        lat = await async_tcp_ping(ip, port, timeout)
        if lat is not None:
            latencies.append(lat)
        if i < ping_times - 1:
            await asyncio.sleep(0.05)
    return min(latencies) if latencies else None


class CloudflareScanner:
    def __init__(self, cidrs: List[str], ip_version: int, log_callback=None, progress_callback=None,
                 port=443, max_workers=100, latency_threshold=150):
        self.cidrs = cidrs
        self.ip_version = ip_version
        self.max_workers = max_workers
        self.timeout = 1.0
        self.ping_times = 2
        self.running = True
        self.log_callback = log_callback
        self.progress_callback = progress_callback
        self.port = port
        self.latency_threshold = latency_threshold

    def generate_ips(self) -> List[str]:
        ip_list = []
        for cidr in self.cidrs:
            try:
                network = ipaddress.ip_network(cidr, strict=False)
                if self.ip_version == 4:
                    for subnet in network.subnets(new_prefix=24):
                        if subnet.num_addresses > 12:
                            hosts = list(subnet.hosts())
                            if hosts:
                                n = min(IPV4_IPS_PER_SUBNET, len(hosts))
                                sampled_ips = random.sample(hosts, n)
                                for ip in sampled_ips:
                                    ip_list.append(str(ip))
                else:
                    if network.num_addresses > 2:
                        sample = min(IPV6_IPS_PER_CIDR, network.num_addresses - 2)
                        for _ in range(sample):
                            rand_int = random.randint(int(network.network_address)+1, int(network.broadcast_address)-1)
                            ip_list.append(str(ipaddress.IPv6Address(rand_int)))
            except ValueError as e:
                if self.log_callback:
                    self.log_callback(f"处理CIDR {cidr} 时出错: {e}")
                continue
        return ip_list

    async def test_single_ip(self, session: aiohttp.ClientSession, ip: str):
        if not self.running:
            return None
        latency = await measure_tcp_latency(ip, self.port, self.ping_times, self.timeout)
        if latency is not None and latency < self.latency_threshold:
            iata = None
            if self.running:
                try:
                    iata = await get_iata_code_async(session, ip, self.timeout)
                except Exception as e:
                    if self.log_callback:
                        self.log_callback(f"获取地区码失败 {ip}: {str(e)}")
            return {
                'ip': ip, 'latency': latency, 'iata_code': iata,
                'chinese_name': get_iata_translation(iata) if iata else "未知地区",
                'success': True, 'ip_version': self.ip_version,
                'scan_time': datetime.now().strftime("%H:%M:%S"),
                'port': self.port, 'ping_times': self.ping_times
            }
        return None

    async def batch_test_ips(self, ip_list: List[str]):
        semaphore = asyncio.Semaphore(self.max_workers)
        family = socket.AF_INET6 if self.ip_version == 6 else socket.AF_INET
        connector = aiohttp.TCPConnector(limit=self.max_workers, force_close=True,
                                         enable_cleanup_closed=True, limit_per_host=0, family=family)
        successful = []
        start_time = time.time()
        async with aiohttp.ClientSession(connector=connector) as session:
            async def _test(ip):
                async with semaphore:
                    return await self.test_single_ip(session, ip)
            tasks = [asyncio.create_task(_test(ip)) for ip in ip_list if self.running]
            total = len(tasks)
            completed = 0
            last_update = 0.0
            for fut in asyncio.as_completed(tasks):
                if not self.running:
                    # 取消所有尚未完成的任务
                    for task in tasks:
                        if not task.done():
                            task.cancel()
                    break
                result = await fut
                completed += 1
                if result:
                    successful.append(result)
                now = time.time()
                if now - last_update >= 0.5 or completed == total:
                    elapsed = now - start_time
                    speed = completed / elapsed if elapsed > 0 else 0
                    if self.progress_callback:
                        self.progress_callback(completed, total, len(successful), speed)
                    last_update = now
        return successful

    async def run_scan_async(self):
        try:
            if self.log_callback:
                self.log_callback(f"正在从Cloudflare IPv{self.ip_version} IP段生成随机IP... (端口: {self.port})")
            ip_list = self.generate_ips()
            if not ip_list:
                if self.log_callback:
                    self.log_callback(f"错误: 未能生成IPv{self.ip_version} IP列表")
                return None
            if self.log_callback:
                self.log_callback(f"已生成 {len(ip_list)} 个随机IPv{self.ip_version} IP")
                self.log_callback(f"开始延迟测试 {len(ip_list)} 个IPv{self.ip_version} IP...")
            results = await self.batch_test_ips(ip_list)
            if not self.running:
                if self.log_callback:
                    self.log_callback(f"IPv{self.ip_version}扫描被用户中止")
                return None
            return results
        except Exception as e:
            if self.log_callback:
                self.log_callback(f"IPv{self.ip_version}扫描过程中出现错误: {str(e)}")
            return None

    def stop(self):
        self.running = False


class ScanWorker(QThread):
    progress_update = Signal(int, int, int, float)
    status_message = Signal(str)
    scan_completed = Signal(list)

    def __init__(self, ip_version: int, port=443, max_workers=150, latency_threshold=220):
        super().__init__()
        self.ip_version = ip_version
        self.port = port
        self.max_workers = max_workers
        self.latency_threshold = latency_threshold
        self.scanner = None

    def run(self):
        if sys.platform == 'win32':
            asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
        cidrs = CF_IPV4_CIDRS if self.ip_version == 4 else CF_IPV6_CIDRS
        self.scanner = CloudflareScanner(
            cidrs=cidrs, ip_version=self.ip_version,
            log_callback=lambda msg: self.status_message.emit(msg),
            progress_callback=lambda c, t, s, sp: self.progress_update.emit(c, t, s, sp),
            port=self.port, max_workers=self.max_workers, latency_threshold=self.latency_threshold
        )
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            results = loop.run_until_complete(self.scanner.run_scan_async())
            if results is not None:
                self.scan_completed.emit(results)
        finally:
            loop.close()

    def stop(self):
        if self.scanner:
            self.scanner.stop()


class SpeedTestWorker(QThread):
    progress_update = Signal(int, int, float)
    status_message = Signal(str)
    speed_test_completed = Signal(list)

    def __init__(self, results: List[Dict], region_code: str = None, max_test_count=10, current_port=443):
        super().__init__()
        self.results = results
        self.region_code = region_code.upper() if region_code else None
        self.max_test_count = max_test_count
        self.download_time_limit = 3
        self.test_host = "speed.cloudflare.com"
        self.running = True
        self.current_port = current_port

    def download_speed(self, ip: str, port: int) -> float:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = (f"GET /__down?bytes=50000000 HTTP/1.1\r\nHost: {self.test_host}\r\nUser-Agent: Mozilla/5.0\r\nAccept: */*\r\nConnection: close\r\n\r\n").encode()
        try:
            if ':' in ip:
                addrinfo = socket.getaddrinfo(ip, port, socket.AF_INET6, socket.SOCK_STREAM)
                sock = socket.socket(addrinfo[0][0], addrinfo[0][1], addrinfo[0][2])
                sock.settimeout(3)
                sock.connect(addrinfo[0][4])
            else:
                sock = socket.create_connection((ip, port), timeout=3)
            ss = ctx.wrap_socket(sock, server_hostname=self.test_host)
            ss.sendall(req)
            start = time.time()
            data = b""
            header_done = False
            body = 0
            while time.time() - start < self.download_time_limit:
                buf = ss.recv(8192)
                if not buf:
                    break
                if not header_done:
                    data += buf
                    if b"\r\n\r\n" in data:
                        header_done = True
                        body += len(data.split(b"\r\n\r\n", 1)[1])
                else:
                    body += len(buf)
            ss.close()
            dur = time.time() - start
            return round((body / 1024 / 1024) / max(dur, 0.1), 2)
        except Exception as e:
            self.status_message.emit(f"测速失败 {ip}: {str(e)}")
            return 0.0

    def run(self):
        try:
            if not self.results:
                self.status_message.emit("错误：没有可用的IP进行测速")
                self.speed_test_completed.emit([])
                return
            if self.region_code:
                filtered = [r for r in self.results if r.get('iata_code') and r['iata_code'].upper() == self.region_code]
                self.status_message.emit(f"开始地区测速：{self.region_code} ({AIRPORT_CODES.get(self.region_code, '未知地区')}) (端口: {self.current_port})")
                self.status_message.emit(f"找到 {len(filtered)} 个 {self.region_code} 地区的IP")
            else:
                filtered = self.results
                self.status_message.emit(f"开始完全测速 (端口: {self.current_port})")
            if not filtered:
                self.status_message.emit("没有找到可用的IP进行测速")
                self.speed_test_completed.emit([])
                return
            filtered.sort(key=lambda x: x.get('latency', float('inf')))
            targets = filtered[:min(self.max_test_count, len(filtered))]
            self.status_message.emit(f"{'地区测速' if self.region_code else '完全测速'}：将对 {len(targets)} 个IP进行测速")
            speed_results = []
            for i, info in enumerate(targets):
                if not self.running:
                    break
                ip = info['ip']
                latency = info.get('latency', 0)
                self.status_message.emit(f"[{i+1}/{len(targets)}] 正在测速 {ip} (端口: {self.current_port})")
                self.progress_update.emit(i+1, len(targets), 0)
                dl_speed = self.download_speed(ip, self.current_port)
                colo = get_iata_code_from_ip(ip, timeout=3)
                if not colo or colo == "Unknown":
                    colo = info.get('iata_code', 'UNKNOWN')
                speed_results.append({
                    'ip': ip, 'latency': latency, 'download_speed': dl_speed,
                    'iata_code': colo.upper() if colo else 'UNKNOWN',
                    'chinese_name': AIRPORT_CODES.get(colo.upper(), '未知地区') if colo else '未知地区',
                    'test_type': '地区测速' if self.region_code else '完全测速',
                    'port': self.current_port
                })
                self.status_message.emit(f"  测速结果: {dl_speed} MB/s, 地区: {speed_results[-1]['chinese_name']}")
                if i < len(targets)-1 and self.running:
                    time.sleep(0.3)
            speed_results.sort(key=lambda x: x['download_speed'], reverse=True)
            self.status_message.emit(f"测速完成！成功测速 {len(speed_results)}/{len(targets)} 个IP")
            self.speed_test_completed.emit(speed_results)
        except Exception as e:
            self.status_message.emit(f"测速过程中出现错误: {str(e)}")
            self.speed_test_completed.emit([])

    def stop(self):
        self.running = False


class CustomDialog(QDialog):
    def __init__(self, message: str,
                 buttons: int = QDialogButtonBox.Ok,
                 parent=None):
        super().__init__(parent)

        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Dialog)
        self.setModal(True)

        self.setAttribute(Qt.WA_TranslucentBackground, True)

        outer_layout = QVBoxLayout(self)
        outer_layout.setContentsMargins(12, 12, 12, 12)
        outer_layout.setSpacing(0)

        panel = QFrame()
        panel.setObjectName("dialogPanel")
        panel.setStyleSheet(f"""
            QFrame#dialogPanel {{
                background-color: white;
                border: 1px solid #D1D5DB;
                border-radius: 12px;
            }}

            QLabel {{
                background: transparent;
                border: none;
                font-family: "{SYSTEM_FONT}";
                font-size: 15px;
                color: #111827;
            }}

            QDialogButtonBox {{
                background: transparent;
                border: none;
            }}

            QPushButton {{
                background: #F97316;
                color: white;
                border: none;
                border-radius: 6px;
                padding: 6px 18px;
                min-width: 62px;
                min-height: 20px;
                font-family: "{SYSTEM_FONT}";
                font-size: 15px;
            }}

            QPushButton:hover {{
                background: #EA580C;
            }}

            QPushButton:pressed {{
                background: #C2410C;
            }}
        """)

        outer_layout.addWidget(panel)

        layout = QVBoxLayout(panel)
        layout.setContentsMargins(24, 24, 24, 20)
        layout.setSpacing(18)

        msg_label = QLabel(message)
        msg_label.setWordWrap(True)
        msg_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(msg_label)

        button_box = QDialogButtonBox(buttons)
        button_box.setCenterButtons(True)

        button_box.setStyleSheet("""
            QDialogButtonBox {
                background: transparent;
                border: none;
            }
        """)

        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)

        yes_btn = button_box.button(QDialogButtonBox.Yes)
        no_btn = button_box.button(QDialogButtonBox.No)

        if yes_btn:
            yes_btn.clicked.connect(self.accept)

        if no_btn:
            no_btn.clicked.connect(self.reject)

        layout.addWidget(button_box)

        self.setFixedSize(320, 160)

    @staticmethod
    def warning(parent, message):
        dialog = CustomDialog(
            message,
            QDialogButtonBox.Ok,
            parent
        )
        return dialog.exec()

    @staticmethod
    def question(parent, message):
        dialog = CustomDialog(
            message,
            QDialogButtonBox.Yes | QDialogButtonBox.No,
            parent
        )
        return dialog.exec() == QDialog.Accepted


class CloudflareScanUI(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("CloudFlare Scan - 小琳解说 V4.0")
        self.resize(430, 750)
        self.setMinimumSize(420, 600)
        self.setStyleSheet(f"""
            QWidget {{
                font-family: '{SYSTEM_FONT}';
                background: #F9FAFB;
            }}
            QLabel {{
                color: #111827;
            }}
        """)
        self.ipv4_scan_worker = None
        self.ipv6_scan_worker = None
        self.speed_test_worker = None
        self.scanning = False
        self.speed_testing = False
        self.scan_results = []
        self.speed_results = []
        self.current_scan_port = 443
        self.init_ui()

    def make_btn(self, text, color, text_color="white", enabled=True):
        btn = QPushButton(text)
        btn.setFixedSize(BTN_W, BTN_H)
        btn.setFont(FONT_BTN)
        btn.setEnabled(enabled)
        btn.setCursor(Qt.PointingHandCursor)
        btn.setStyleSheet(f"""
            QPushButton{{background:{color};color:{text_color};border-radius:6px;font-family:'{SYSTEM_FONT}';}}
            QPushButton:disabled{{background:#E5E7EB;color:#6B7280;}}
        """)
        return btn

    def make_stop_btn(self, text, enabled=True):
        btn = QPushButton(text)
        btn.setFixedSize(BTN_W, BTN_H)
        btn.setFont(FONT_BTN)
        btn.setEnabled(enabled)
        btn.setCursor(Qt.PointingHandCursor)
        btn.setStyleSheet(f"QPushButton{{background:#EF4444;color:white;border-radius:6px;font-family:'{SYSTEM_FONT}';}}"
                          f"QPushButton:disabled{{background:#E5E7EB;color:#6B7280;}}")
        return btn

    def init_ui(self):
        main = QVBoxLayout(self)
        main.setContentsMargins(14, 14, 14, 14)
        main.setSpacing(14)

        title = QLabel('<span style="color:#ff7a18;">CloudFlare</span> <span style="color:#111827;">Scan</span>')
        title.setFont(FONT_TITLE)
        title.setAlignment(Qt.AlignCenter)
        main.addWidget(title)

        link_layout = QHBoxLayout()
        link_layout.setAlignment(Qt.AlignCenter)
        link_layout.setSpacing(20)
        for name, url in [("小琳解说 ⭐ GitHub", "https://github.com/xiaolin-007/CloudFlareScan")]:
            lbl = QLabel(f'<a href="{url}" style="color:#2563EB;text-decoration:underline;font-size:15px;">{name}</a>')
            lbl.setTextFormat(Qt.RichText)
            lbl.setOpenExternalLinks(True)
            lbl.setCursor(Qt.PointingHandCursor)
            link_layout.addWidget(lbl)
        main.addLayout(link_layout)

        row1 = QHBoxLayout()
        row1.addStretch()
        self.btn_ipv4 = self.make_btn("IPv4 扫描", "#3B82F6")
        self.btn_ipv4.clicked.connect(lambda: self.start_scan(4))
        row1.addWidget(self.btn_ipv4)
        row1.addSpacing(SPACING)
        self.btn_ipv6 = self.make_btn("IPv6 扫描", "#22C55E")
        self.btn_ipv6.clicked.connect(lambda: self.start_scan(6))
        row1.addWidget(self.btn_ipv6)
        row1.addSpacing(SPACING)
        self.btn_stop = self.make_stop_btn("停止任务", enabled=False)
        self.btn_stop.clicked.connect(self.confirm_stop)
        row1.addWidget(self.btn_stop)
        row1.addStretch()

        row2 = QHBoxLayout()
        row2.addStretch()
        self.btn_area = self.make_btn("地区测速", "#EC4899", enabled=False)
        self.btn_area.clicked.connect(self.start_region_speed)
        row2.addWidget(self.btn_area)
        row2.addSpacing(SPACING)
        self.btn_full = self.make_btn("完全测速", "#F97316", enabled=False)
        self.btn_full.clicked.connect(self.start_full_speed)
        row2.addWidget(self.btn_full)
        row2.addSpacing(SPACING)
        self.btn_export = self.make_btn("导出结果", "#8B5CF6", enabled=False)
        self.btn_export.clicked.connect(self.export_results)
        row2.addWidget(self.btn_export)
        row2.addStretch()

        row3 = QHBoxLayout()
        row3.addStretch()
        self.input_region = QLineEdit()
        self.input_region.setFixedSize(BTN_W, BTN_H)
        self.input_region.setFont(FONT_BTN)
        self.input_region.setPlaceholderText("输入地区码")
        self.input_region.setStyleSheet(LINE_EDIT_STYLE)
        self.input_region.textChanged.connect(self.auto_uppercase)
        row3.addWidget(self.input_region)
        row3.addSpacing(SPACING)

        speed_cnt_widget = QWidget()
        speed_cnt_widget.setFixedSize(BTN_W, BTN_H)
        speed_cnt_layout = QHBoxLayout(speed_cnt_widget)
        speed_cnt_layout.setContentsMargins(0,0,0,0)
        speed_cnt_layout.setSpacing(5)
        label_speed_cnt = QLabel("测速数量")
        label_speed_cnt.setFont(FONT_BTN)
        speed_cnt_layout.addWidget(label_speed_cnt)
        self.input_speed_count = QLineEdit()
        self.input_speed_count.setFixedHeight(BTN_H)
        self.input_speed_count.setFont(FONT_BTN)
        self.input_speed_count.setText("10")
        self.input_speed_count.setStyleSheet(LINE_EDIT_STYLE)
        self.input_speed_count.setValidator(QIntValidator(1,50))
        speed_cnt_layout.addWidget(self.input_speed_count, 1)
        row3.addWidget(speed_cnt_widget)
        row3.addSpacing(SPACING)

        port_widget = QWidget()
        port_widget.setFixedSize(BTN_W, BTN_H)
        port_layout = QHBoxLayout(port_widget)
        port_layout.setContentsMargins(0,0,0,0)
        port_layout.setSpacing(5)
        label_port = QLabel("端口")
        label_port.setFont(FONT_BTN)
        port_layout.addWidget(label_port)
        self.combo_port = QComboBox()
        self.combo_port.setFixedHeight(BTN_H)
        self.combo_port.setFont(FONT_BTN)
        self.combo_port.addItems(PORT_OPTIONS)
        self.combo_port.setCurrentText("443")
        self.combo_port.setStyleSheet(COMBO_BOX_STYLE)
        port_layout.addWidget(self.combo_port, 1)
        row3.addWidget(port_widget)
        row3.addStretch()

        row4 = QHBoxLayout()
        row4.addStretch()
        workers_widget = QWidget()
        workers_widget.setFixedSize(BTN_W, BTN_H)
        workers_layout = QHBoxLayout(workers_widget)
        workers_layout.setContentsMargins(0,0,0,0)
        workers_layout.setSpacing(5)
        label_workers = QLabel("并发线程")
        label_workers.setFont(FONT_BTN)
        workers_layout.addWidget(label_workers)
        self.input_workers = QLineEdit()
        self.input_workers.setFixedHeight(BTN_H)
        self.input_workers.setFont(FONT_BTN)
        self.input_workers.setText("150")
        self.input_workers.setStyleSheet(LINE_EDIT_STYLE)
        self.input_workers.setValidator(QIntValidator(1, 300))
        workers_layout.addWidget(self.input_workers, 1)
        row4.addWidget(workers_widget)
        row4.addSpacing(SPACING)

        latency_widget = QWidget()
        latency_widget.setFixedSize(BTN_W, BTN_H)
        latency_layout = QHBoxLayout(latency_widget)
        latency_layout.setContentsMargins(0,0,0,0)
        latency_layout.setSpacing(5)
        label_latency = QLabel("延迟上限")
        label_latency.setFont(FONT_BTN)
        latency_layout.addWidget(label_latency)
        self.input_latency = QLineEdit()
        self.input_latency.setFixedHeight(BTN_H)
        self.input_latency.setFont(FONT_BTN)
        self.input_latency.setText("220")
        self.input_latency.setStyleSheet(LINE_EDIT_STYLE)
        self.input_latency.setValidator(QIntValidator(50,999))
        latency_layout.addWidget(self.input_latency, 1)
        row4.addWidget(latency_widget)
        row4.addStretch()

        control_layout = QVBoxLayout()
        control_layout.setSpacing(SPACING)
        control_layout.addLayout(row1)
        control_layout.addLayout(row2)
        control_layout.addLayout(row3)
        control_layout.addLayout(row4)
        main.addLayout(control_layout)

        self.progress_bar = QProgressBar()
        self.progress_bar.setFixedHeight(10)
        self.progress_bar.setTextVisible(False)
        self.progress_bar.setStyleSheet("QProgressBar{background:#E5E7EB;border-radius:5px;}QProgressBar::chunk{background:#22C55E;border-radius:5px;}")
        main.addWidget(self.progress_bar)

        status_frame = QHBoxLayout()
        self.status_label = QLabel("就绪")
        self.status_label.setStyleSheet(f"color:#6B7280;font-size:12px;padding:5px;font-family:'{SYSTEM_FONT}';")
        self.speed_label = QLabel("速度: 0 IP/秒")
        self.speed_label.setStyleSheet(f"color:#6B7280;font-size:12px;padding:5px;font-family:'{SYSTEM_FONT}';")
        status_frame.addWidget(self.status_label)
        status_frame.addStretch()
        status_frame.addWidget(self.speed_label)
        main.addLayout(status_frame)

        tab_btn_layout = QHBoxLayout()
        tab_btn_layout.addStretch()
        self.tab_btn_log = QPushButton("扫描日志")
        self.tab_btn_log.setFixedSize(180,32)
        self.tab_btn_log.setFont(FONT_BTN)
        self.tab_btn_log.setCheckable(True)
        self.tab_btn_log.clicked.connect(lambda: self.switch_tab(0))
        self.tab_btn_speed = QPushButton("测速结果")
        self.tab_btn_speed.setFixedSize(180,32)
        self.tab_btn_speed.setFont(FONT_BTN)
        self.tab_btn_speed.setCheckable(True)
        self.tab_btn_speed.clicked.connect(lambda: self.switch_tab(1))
        tab_btn_layout.addWidget(self.tab_btn_log)
        tab_btn_layout.addWidget(self.tab_btn_speed)
        tab_btn_layout.addStretch()
        main.addLayout(tab_btn_layout)

        self.stacked = QStackedWidget()
        self.log_tab = QWidget()
        log_layout = QVBoxLayout(self.log_tab)
        log_layout.setContentsMargins(0,0,0,0)
        self.status_display = QTextEdit()
        self.status_display.setFont(FONT_STATUS)
        self.status_display.setReadOnly(True)
        self.status_display.setStyleSheet(f"""
            QTextEdit{{
                background:#0B3C5D;
                border:1px solid #0F4C75;
                border-radius:6px;
                padding:10px;
                color:#ECF0F1;
                font-family:'{SYSTEM_FONT}';
            }}
            {SCROLLBAR_STYLE}
        """)
        log_layout.addWidget(self.status_display)
        self.stacked.addWidget(self.log_tab)

        self.speed_tab = QWidget()
        speed_tab_layout = QVBoxLayout(self.speed_tab)
        speed_tab_layout.setContentsMargins(0,0,0,0)
        self.speed_scroll = QScrollArea()
        self.speed_scroll.setWidgetResizable(True)
        self.speed_scroll.setStyleSheet(f"""
            QScrollArea{{
                background:#0B3C5D;
                border:none;
                border-radius:6px;
            }}
            {SCROLLBAR_STYLE}
        """)
        self.speed_container = QWidget()
        self.speed_container.setStyleSheet("background:transparent;")
        self.speed_layout = QVBoxLayout(self.speed_container)
        self.speed_layout.setContentsMargins(0,0,0,0)
        self.speed_layout.setSpacing(2)
        self.speed_layout.addStretch()
        self.speed_scroll.setWidget(self.speed_container)
        speed_tab_layout.addWidget(self.speed_scroll)
        self.stacked.addWidget(self.speed_tab)
        main.addWidget(self.stacked, 1)

        self.switch_tab(0)

    def switch_tab(self, idx):
        self.stacked.setCurrentIndex(idx)
        self.tab_btn_log.setChecked(idx == 0)
        self.tab_btn_speed.setChecked(idx == 1)
        active = "background:#0B4F7A;color:white;border:none;border-radius:15px;"
        inactive = "background:#E5E7EB;color:#6B7280;border:none;border-radius:15px;"
        self.tab_btn_log.setStyleSheet(active if idx == 0 else inactive)
        self.tab_btn_speed.setStyleSheet(active if idx == 1 else inactive)

    def auto_uppercase(self, text):
        if text != text.upper():
            self.input_region.setText(text.upper())

    def confirm_stop(self):
        if not self.scanning and not self.speed_testing:
            return
        if CustomDialog.question(self, "确定要停止当前任务吗？"):
            self.stop_all()

    def start_scan(self, version):
        if self.scanning or self.speed_testing:
            return

        workers_text = self.input_workers.text().strip()
        if not workers_text:
            workers = 150
        else:
            try:
                workers = int(workers_text)
            except ValueError:
                workers = 150
        if workers < 1 or workers > 300:
            CustomDialog.warning(self, "并发线程数范围1-300")
            return

        self.scanning = True
        self.update_ui_state(True)
        self.scan_results = []
        self.clear_speed_cards()
        self.status_display.clear()
        self.status_display.append(f"正在开始IPv{version}扫描...")
        self.status_display.append("="*25)
        self.progress_bar.setValue(0)
        self.status_label.setText(f"IPv{version}扫描中...")
        self.speed_label.setText("速度: 0 IP/秒")
        port = int(self.combo_port.currentText())
        self.current_scan_port = port
        try:
            latency = max(50, int(self.input_latency.text() or "220"))
        except:
            latency = 220
        worker = ScanWorker(version, port=port, max_workers=workers, latency_threshold=latency)
        worker.progress_update.connect(self.update_progress)
        worker.status_message.connect(self.update_status)
        worker.scan_completed.connect(self.scan_finished)
        worker.finished.connect(lambda: self.worker_finished("scan"))
        if version == 4:
            self.ipv4_scan_worker = worker
        else:
            self.ipv6_scan_worker = worker
        worker.start()

    def start_full_speed(self):
        if self.speed_testing or self.scanning or not self.scan_results:
            self.status_display.append("错误：请先运行扫描获取IP列表！")
            return
        try:
            cnt = int(self.input_speed_count.text().strip())
            if not 1 <= cnt <= 50:
                raise ValueError
        except:
            self.status_display.append("错误：测速数量必须在1-50之间！")
            return

        self.speed_testing = True
        self.update_ui_state(True)
        self.clear_speed_cards()
        self.status_display.append("")
        self.progress_bar.setValue(0)
        self.status_label.setText("完全测速中...")
        self.speed_label.setText("测速进度: 0/5")
        self.speed_test_worker = SpeedTestWorker(self.scan_results, max_test_count=cnt, current_port=self.current_scan_port)
        self.speed_test_worker.progress_update.connect(self.update_speed_progress)
        self.speed_test_worker.status_message.connect(self.update_status)
        self.speed_test_worker.speed_test_completed.connect(self.speed_test_finished)
        self.speed_test_worker.finished.connect(lambda: self.worker_finished("speed"))
        self.speed_test_worker.start()

    def start_region_speed(self):
        if self.speed_testing or self.scanning or not self.scan_results:
            self.status_display.append("错误：请先运行扫描获取IP列表！")
            return
        region = self.input_region.text().strip().upper()
        if not region:
            self.status_display.append("错误：请输入地区码（如SJC、SIN等）")
            return
        try:
            cnt = int(self.input_speed_count.text().strip())
            if not 1 <= cnt <= 50:
                raise ValueError
        except:
            self.status_display.append("错误：测速数量必须在1-50之间！")
            return
        self.speed_testing = True
        self.update_ui_state(True)
        self.clear_speed_cards()
        self.status_display.append("")
        self.progress_bar.setValue(0)
        self.status_label.setText(f"{region}地区测速中...")
        self.speed_label.setText("测速进度: 0/5")
        self.speed_test_worker = SpeedTestWorker(self.scan_results, region_code=region, max_test_count=cnt, current_port=self.current_scan_port)
        self.speed_test_worker.progress_update.connect(self.update_speed_progress)
        self.speed_test_worker.status_message.connect(self.update_status)
        self.speed_test_worker.speed_test_completed.connect(self.speed_test_finished)
        self.speed_test_worker.finished.connect(lambda: self.worker_finished("speed"))
        self.speed_test_worker.start()

    def export_results(self):
        if not self.speed_results:
            self.status_display.append("错误：没有测速结果可以导出！")
            return
        fname, _ = QFileDialog.getSaveFileName(self, "保存测速结果", f"cfs_results_{datetime.now().strftime('%Y%m%d')}.csv", "CSV文件 (*.csv)")
        if not fname:
            return
        if not fname.endswith('.csv'):
            fname += '.csv'
        try:
            with open(fname, 'w', newline='', encoding='utf-8-sig') as f:
                writer = csv.DictWriter(f, fieldnames=['排名','IP地址','地区码','地区','延迟(ms)','下载速度(MB/s)','端口','测速类型'])
                writer.writeheader()
                for i, r in enumerate(self.speed_results, 1):
                    writer.writerow({
                        '排名': i, 'IP地址': r['ip'], '地区码': r['iata_code'], '地区': r['chinese_name'],
                        '延迟(ms)': f"{r['latency']:.2f}", '下载速度(MB/s)': f"{r['download_speed']:.2f}",
                        '端口': r.get('port',443), '测速类型': r.get('test_type','未知')
                    })
            self.status_display.append(f"测速结果已成功导出到: {fname}")
            self.status_label.setText(f"结果已导出到: {os.path.basename(fname)}")
            QTimer.singleShot(3000, lambda: self.status_label.setText("就绪"))
        except Exception as e:
            self.status_display.append(f"导出失败: {str(e)}")

    def stop_all(self):
        if self.ipv4_scan_worker and self.scanning:
            self.ipv4_scan_worker.stop()
        if self.ipv6_scan_worker and self.scanning:
            self.ipv6_scan_worker.stop()
        if self.speed_test_worker and self.speed_testing:
            self.speed_test_worker.stop()
        self.btn_stop.setEnabled(False)

    def scan_finished(self, results):
        if results:
            known_results = [r for r in results if r.get('iata_code') and r.get('iata_code') != 'UNKNOWN']
        else:
            known_results = []
        self.scan_results = known_results
        self.show_scan_summary(self.scan_results)

    def speed_test_finished(self, results):
        self.speed_results = results
        self.display_speed_results(results)
        if results:
            self.btn_export.setEnabled(True)

    def worker_finished(self, typ):
        if typ == "scan":
            self.scanning = False
            self.status_label.setText("扫描完成")
            if self.scan_results:
                self.btn_full.setEnabled(True)
                self.btn_area.setEnabled(True)
        else:
            self.speed_testing = False
            self.status_label.setText("测速完成")
        if not self.scanning and not self.speed_testing:
            self.update_ui_state(False)

    def update_ui_state(self, busy):
        self.btn_stop.setEnabled(busy)
        self.btn_ipv4.setEnabled(not busy)
        self.btn_ipv6.setEnabled(not busy)
        self.btn_full.setEnabled(not busy and bool(self.scan_results))
        self.btn_area.setEnabled(not busy and bool(self.scan_results))
        self.btn_export.setEnabled(not busy and bool(self.speed_results))
        self.input_region.setEnabled(not busy)
        self.input_speed_count.setEnabled(not busy)
        self.input_workers.setEnabled(not busy)
        self.input_latency.setEnabled(not busy)
        if not busy:
            self.progress_bar.setValue(0)

    def update_progress(self, cur, total, ok, speed):
        if total:
            self.progress_bar.setValue(int(cur/total*100))
        self.status_label.setText(f"扫描中: {cur}/{total} ({ok}个可用)")
        self.speed_label.setText(f"速度: {speed:.1f} IP/秒")

    def update_speed_progress(self, cur, total, _):
        if total:
            self.progress_bar.setValue(int(cur/total*100))
        self.status_label.setText(f"测速中: {cur}/{total}")
        self.speed_label.setText(f"测速进度: {cur}/{total}")

    def update_status(self, msg):
        self.status_display.append(msg)
        self.status_display.verticalScrollBar().setValue(self.status_display.verticalScrollBar().maximum())

    def show_scan_summary(self, results):
        if not results:
            self.status_display.append("\n扫描完成！未找到任何已知地区的可用IP地址。")
            return
        ipv4 = sum(1 for r in results if ':' not in r['ip'])
        ipv6 = len(results) - ipv4
        iata_stats = {}
        for r in results:
            code = r.get('iata_code')
            if code:
                key = f"{code} ({r['chinese_name']})"
                iata_stats[key] = iata_stats.get(key, 0) + 1
        self.status_display.append("\n" + "="*25)
        self.status_display.append("扫描完成！统计信息：")
        if ipv4:
            self.status_display.append(f"可用IPv4地址: {ipv4} 个 (端口: {self.current_scan_port})")
        if ipv6:
            self.status_display.append(f"可用IPv6地址: {ipv6} 个 (端口: {self.current_scan_port})")
        if iata_stats:
            self.status_display.append(f"地区统计（共 {len(iata_stats)} 个不同地区）：")
            for iata, cnt in sorted(iata_stats.items(), key=lambda x: x[1], reverse=True):
                self.status_display.append(f"  {iata}: {cnt}个IP")
        else:
            self.status_display.append("提示：本次扫描未获取到具体的地区码信息。")
        self.status_display.append(f"\n扫描端口: {self.current_scan_port}\n现在可以使用完全测速或地区测速功能。")

    def display_speed_results(self, results):
        if not results:
            self.status_display.append("测速完成：没有有效的测速结果")
            return
        self.switch_tab(1)
        for i, r in enumerate(results, 1):
            card = QFrame()
            card.setStyleSheet("QFrame{background:transparent;border:none;margin:0;padding:0;}")
            layout = QHBoxLayout(card)
            layout.setContentsMargins(12,8,12,8)
            layout.setSpacing(10)
            num = QLabel(str(i))
            num.setFixedWidth(20)
            num.setStyleSheet("color:white;font-size:13px;")
            layout.addWidget(num)
            info = QVBoxLayout()
            info.setSpacing(2)
            ip_label = QLabel(r['ip'])
            ip_label.setStyleSheet("color:white;font-size:13px;")
            detail_label = QLabel(f"{r['chinese_name']} 延迟: {r['latency']:.2f}ms 速度: {r['download_speed']:.2f} MB/s")
            detail_label.setStyleSheet("color:#D1D5DB;font-size:13px;")
            info.addWidget(ip_label)
            info.addWidget(detail_label)
            layout.addLayout(info, 1)
            copy_btn = QPushButton("复制")
            copy_btn.setFixedSize(60,30)
            copy_btn.setCursor(Qt.PointingHandCursor)
            copy_btn.setStyleSheet("QPushButton{background:#8B5CF6;color:white;border-radius:4px;font-size:11px;}"
                                   "QPushButton:hover{background:#7C3AED;}")
            copy_btn.clicked.connect(lambda _, ip=r['ip']: self.copy_ip(ip))
            layout.addWidget(copy_btn)
            self.speed_layout.insertWidget(self.speed_layout.count()-1, card)
        self.status_display.append(f"\n测速完成！！\n成功测速 {len(results)} 个IP (端口: {self.current_scan_port})")

    def clear_speed_cards(self):
        while self.speed_layout.count() > 0:
            item = self.speed_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        self.speed_layout.addStretch()

    def copy_ip(self, ip):
        QApplication.clipboard().setText(ip)
        self.status_label.setText(f"已复制: {ip[:27]+'...' if len(ip)>30 else ip}")
        QTimer.singleShot(2000, lambda: self.status_label.setText("就绪"))

def find_icon_file():
    basedir = os.path.dirname(os.path.abspath(__file__))
    for name in ["cfs.ico", "cfs.icns"]:
        path = os.path.join(basedir, name)
        if os.path.exists(path):
            return path
    if hasattr(sys, '_MEIPASS'):
        for name in ["cfs.ico", "cfs.icns"]:
            path = os.path.join(sys._MEIPASS, name)
            if os.path.exists(path):
                return path
    return None

if __name__ == "__main__":
    if platform.system() == "Darwin":
        os.environ['QT_MAC_WANTS_LAYER'] = '1'
    app = QApplication(sys.argv)
    icon = find_icon_file()
    if icon:
        app.setWindowIcon(QIcon(icon))
    win = CloudflareScanUI()
    if icon:
        win.setWindowIcon(QIcon(icon))
    win.show()
    sys.exit(app.exec())
