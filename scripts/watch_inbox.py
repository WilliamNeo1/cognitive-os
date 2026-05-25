#!/usr/bin/env python3
"""
watch_inbox.py — 监控文件夹，自动处理截图入库
用法: python3 scripts/watch_inbox.py
"""

import os, sys, time, subprocess
from pathlib import Path

INBOX = Path.home() / "Desktop" / "ccc_inbox"
DONE  = INBOX / "done"
INBOX.mkdir(exist_ok=True)
DONE.mkdir(exist_ok=True)

SUPPORTED = {".png", ".jpg", ".jpeg"}

print(f"👁  监控文件夹: {INBOX}")
print(f"   支持格式: {', '.join(SUPPORTED)}")
print(f"   按 Ctrl+C 停止\n")

seen = set()

while True:
    for f in INBOX.iterdir():
        if f.suffix.lower() not in SUPPORTED:
            continue
        if f.name in seen:
            continue
        seen.add(f.name)

        print(f"📸 发现新文件: {f.name}")
        result = subprocess.run(
            [sys.executable, "scripts/ingest_v3.py", "--image", str(f)],
            capture_output=False
        )
        if result.returncode == 0:
            f.rename(DONE / f.name)
            print(f"✅ 处理完成，已移至 done/\n")

            # 自动同步
            print("🔄 同步到 Supabase...")
            subprocess.run([sys.executable, "scripts/sync_to_supabase.py"])
        else:
            print(f"❌ 处理失败: {f.name}\n")

    time.sleep(3)
