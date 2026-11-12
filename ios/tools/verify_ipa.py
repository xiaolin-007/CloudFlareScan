#!/usr/bin/env python3
"""校验 CloudFlareScan iOS IPA：包结构 + Mach-O + ad-hoc 签名 page hash。"""
import hashlib
import os
import plistlib
import struct
import sys
import tempfile
import zipfile

LC_CODE_SIGNATURE = 0x1D
LC_BUILD_VERSION = 0x32
LC_SEGMENT_64 = 0x19


def parse_macho(data):
    magic = struct.unpack("<I", data[:4])[0]
    if magic not in (0xFEEDFACF,):
        raise ValueError("not a 64-bit Mach-O (magic 0x%x)" % magic)
    cputype, cpusub = struct.unpack("<II", data[4:12])
    ncmds = struct.unpack("<I", data[16:20])[0]
    off = 32
    info = {"cputype": cputype, "cpusub": cpusub, "sig": None, "build": None}
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", data[off:off + 8])
        if size < 8:
            raise ValueError("bad load command at 0x%x" % off)
        if cmd == LC_CODE_SIGNATURE:
            info["sig"] = struct.unpack("<II", data[off + 8:off + 16])
        elif cmd == LC_BUILD_VERSION:
            plat, minos, sdk = struct.unpack("<III", data[off + 8:off + 20])
            info["build"] = (plat, minos, sdk)
        off += size
    return info


def verify_signature(data, sig_off_size):
    dataoff, datasize = sig_off_size
    blob = data[dataoff:dataoff + datasize]
    magic, length, count = struct.unpack(">III", blob[:12])
    if magic != 0xFADE0CC0:
        return (False, "superblob magic 0x%x" % magic)
    results = []
    for i in range(count):
        slot, off = struct.unpack(">II", blob[12 + i * 8:20 + i * 8])
        if slot != 0:
            continue
        cd = blob[off:]
        if len(cd) < 44:
            return (False, "CodeDirectory truncated")
        (cd_magic, cd_len, ver, flags, hash_off, ident_off, n_special,
         n_code, code_limit, hash_size, hash_type, platform, page_size,
         spare2) = struct.unpack(">9I4BI", cd[:44])
        if cd_magic != 0xFADE0C02:
            return (False, "CodeDirectory magic 0x%x" % cd_magic)
        try:
            ident = cd[ident_off:cd.index(b"\0", ident_off)].decode()
        except Exception:
            ident = "?"
        pages_ok = pages_bad = 0
        psize = 1 << page_size
        for p in range(n_code):
            start = p * psize
            end = min(start + psize, code_limit)
            h = hashlib.sha256(data[start:end]).digest()
            got = cd[hash_off + p * hash_size:hash_off + (p + 1) * hash_size]
            if h == got:
                pages_ok += 1
            else:
                pages_bad += 1
        results.append({
            "ident": ident, "version": hex(ver), "flags": hex(flags),
            "hash_type": hash_type, "page_size": psize,
            "n_code": n_code, "code_limit": code_limit,
            "ok": pages_ok, "bad": pages_bad,
        })
    if not results:
        return (False, "no CodeDirectory slot")
    r = results[0]
    return (r["bad"] == 0, r)


def main():
    if len(sys.argv) < 2:
        print("usage: verify_ipa.py <ipa>")
        return 2
    ipa = sys.argv[1]
    if not os.path.isfile(ipa):
        print("missing: %s" % ipa)
        return 2

    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(ipa) as z:
            names = z.namelist()
            z.extractall(tmp)

        apps = [n for n in names if n.startswith("Payload/") and n.count("/") == 2
                and n.endswith(".app/")]
        if not apps:
            print("FAIL: 没有 Payload/*.app")
            return 1
        app_rel = apps[0]
        app_dir = os.path.join(tmp, app_rel.rstrip("/"))
        app_name = os.path.basename(app_dir)

        info_path = os.path.join(app_dir, "Info.plist")
        if not os.path.isfile(info_path):
            problems.append("缺 Info.plist")
            info = {}
        else:
            with open(info_path, "rb") as f:
                info = plistlib.load(f)

        exe = info.get("CFBundleExecutable", "")
        bundle_id = info.get("CFBundleIdentifier", "")
        min_os = info.get("MinimumOSVersion", "")
        exe_path = os.path.join(app_dir, exe)

        if not exe:
            problems.append("Info.plist 缺 CFBundleExecutable")
        if not bundle_id:
            problems.append("Info.plist 缺 CFBundleIdentifier")
        if not os.path.isfile(exe_path):
            problems.append("可执行文件不存在: %s" % exe)
            exe_data = b""
            macho = {}
        else:
            with open(exe_path, "rb") as f:
                exe_data = f.read()
            try:
                macho = parse_macho(exe_data)
            except Exception as e:
                problems.append("Mach-O 解析失败: %s" % e)
                macho = {}

        if macho:
            if macho["cputype"] != 0x0100000C:
                problems.append("CPU 类型不是 arm64 (0x%x)" % macho["cputype"])
            if not macho["sig"]:
                problems.append("没有 LC_CODE_SIGNATURE（未签名）")
            if macho["build"]:
                plat, minos, sdk = macho["build"]
                if plat != 2:
                    problems.append("LC_BUILD_VERSION platform=%d，不是 iOS(2)" % plat)

        sig_report = None
        if macho.get("sig"):
            ok, rep = verify_signature(exe_data, macho["sig"])
            sig_report = rep
            if not ok:
                problems.append("签名校验失败: %r" % (rep,))

        for need in ("www/index.html", "www/assets/index-b48b5b2e.js",
                     "www/assets/index-8c2ced60.css", "shim.js"):
            if not os.path.isfile(os.path.join(app_dir, need)):
                problems.append("缺资源: %s" % need)

        print("=" * 62)
        print("IPA            : %s" % os.path.basename(ipa))
        print("大小           : %.2f MB" % (os.path.getsize(ipa) / 1048576.0))
        print("App            : %s" % app_name)
        print("Bundle ID      : %s" % bundle_id)
        print("可执行         : %s" % exe)
        print("最低系统       : %s" % min_os)
        if macho:
            print("架构           : arm64 (cpusub 0x%x)" % macho["cpusub"])
            if macho["build"]:
                plat, minos, sdk = macho["build"]
                print("BuildVersion   : platform=%d minos=%.2f sdk=%.2f"
                      % (plat, minos / 65536.0, sdk / 65536.0))
        if sig_report:
            print("签名           : %s  version=%s flags=%s hash=%d page=%d"
                  % (sig_report["ident"], sig_report["version"], sig_report["flags"],
                     sig_report["hash_type"], sig_report["page_size"]))
            print("页哈希         : %d/%d 通过"
                  % (sig_report["ok"], sig_report["ok"] + sig_report["bad"]))
        print("条目数         : %d" % len(names))
        print("=" * 62)

    if problems:
        print("FAIL:")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("OK: 包结构与签名全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
