#!/usr/bin/env python3
"""
ingest_batch.py — 批量入库脚本
读取JSON数组文件，逐个对象调用 ingest_v3.py 入库

用法:
  python3 scripts/ingest_batch.py --file ccc3a_ner_combined.json
  python3 scripts/ingest_batch.py --file ccc3a_ner_combined.json --start 10
"""

import json, os, sys, argparse, subprocess, tempfile

def ingest_one(data):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json",
                                     encoding="utf-8", delete=False) as f:
        json.dump(data, f, ensure_ascii=False)
        tmp = f.name
    r = subprocess.run(["python3", "scripts/ingest_v3.py", "--json", tmp],
                       capture_output=True, text=True)
    os.unlink(tmp)
    if r.returncode == 0:
        for line in r.stdout.split('\n'):
            if '✅' in line or '实体:' in line or '事件:' in line or '关系:' in line:
                print(f"    {line.strip()}")
        return True
    else:
        print(f"    入库失败: {r.stderr[:200]}")
        return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file",  required=True)
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--end",   type=int)
    args = parser.parse_args()

    with open(args.file, "r", encoding="utf-8") as f:
        docs = json.load(f)

    total = len(docs)
    print(f"文件: {args.file}")
    print(f"文档总数: {total}")

    end = args.end or total
    ok, fail = 0, 0

    for i in range(args.start-1, end):
        doc = docs[i]
        title = doc.get("title", "")[:50]
        print(f"\n[{i+1:03d}/{total}] {title}")
        print(f"  实体:{len(doc.get('entities',[]))} 事件:{len(doc.get('events',[]))}")
        if ingest_one(doc):
            ok += 1
        else:
            fail += 1

    print(f"\n完成: {ok}成功 / {fail}失败")
    if ok > 0:
        print("同步到 Supabase...")
        subprocess.run(["python3", "scripts/sync_to_supabase.py"])

if __name__ == "__main__":
    main()
