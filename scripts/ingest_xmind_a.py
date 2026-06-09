#!/usr/bin/env python3
"""
ingest_xmind_a.py — ccc3-3A.md 专用入库脚本
自动切分大章节，逐段 NER 入库

用法:
  python3 scripts/ingest_xmind_a.py --dry-run
  python3 scripts/ingest_xmind_a.py --section 1
  python3 scripts/ingest_xmind_a.py --start 1
  python3 scripts/ingest_xmind_a.py --start 10 --end 20
"""

import json, os, sys, re, argparse, subprocess, tempfile
import requests
from json_repair import repair_json

GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "").strip()
CHUNK_SIZE   = 3500
FILE_PATH    = os.path.expanduser("~/Desktop/ccc3-3A.md")

def split_sections(text):
    sections = re.split(r'\n(?=## )', text)
    result = []
    for s in sections:
        s = s.strip()
        if not s or len(s) < 20:
            continue
        lines = [l for l in s.split('\n') if l.strip() and l.strip() not in ['','#','##']]
        if len(lines) < 2:
            continue
        result.append(s)
    return result

def chunk_text(text, size=CHUNK_SIZE):
    if len(text) <= size:
        return [text]
    chunks = []
    lines  = text.split('\n')
    cur    = []
    cur_len = 0
    for line in lines:
        if cur_len + len(line) > size and cur:
            chunks.append('\n'.join(cur))
            cur = [line]
            cur_len = len(line)
        else:
            cur.append(line)
            cur_len += len(line)
    if cur:
        chunks.append('\n'.join(cur))
    return chunks

def ner(text, title):
    if not GROQ_API_KEY:
        print("未设置 GROQ_API_KEY"); sys.exit(1)

    prompt = f"""你是情报分析系统。从以下内容提取实体、关系、事件，只返回JSON：
{{
  "title": "{title[:40]}",
  "category": "PERSON|ORG|EVENT|PLACE|CLAIM",
  "language": "zh|en|mixed",
  "source_type": "xmind",
  "source_url": null,
  "verified": false,
  "entities": [
    {{"name":"","type":"PERSON|ORG|GPE|EVENT","role":"","aliases":[],"notes":"","relations":[{{"to":"","type":"family_relation|political_alignment|financial_control|colleague|organizational_dependency","direction":"source_to_target"}}]}}
  ],
  "events": [{{"date":"","location":"","summary":"","persons":[]}}],
  "claims": [{{"text":"","confidence":0.7,"source":null}}],
  "raw_content": "摘要150字以内"
}}
只输出JSON，不要解释。

内容：
{text[:CHUNK_SIZE]}"""

    try:
        resp = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
            json={"model": "llama-3.3-70b-versatile", "temperature": 0.1, "max_tokens": 2000,
                  "messages": [{"role": "system", "content": "只输出JSON，不要任何解释或markdown。"},
                                {"role": "user", "content": prompt}]},
            timeout=30, verify=True
        )
        data = resp.json()
        if "choices" not in data:
            err = data.get("error", {})
            if "rate_limit" in str(err) or "429" in str(resp.status_code):
                print(f"  ⚠️  Rate limit: {err.get('message','')[:80]}")
                return None
            print(f"  ⚠️  API error: {err}")
            return None
        raw = data["choices"][0]["message"]["content"].strip()
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        result = json.loads(repair_json(raw.strip()))
        result["source_type"] = "xmind"
        return result
    except Exception as e:
        print(f"  NER失败: {e}")
        return None

def ingest(data):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json",
                                     encoding="utf-8", delete=False) as f:
        json.dump(data, f, ensure_ascii=False)
        tmp = f.name
    r = subprocess.run(["python3", "scripts/ingest_v3.py", "--json", tmp],
                       capture_output=True, text=True)
    os.unlink(tmp)
    if r.returncode == 0:
        for line in r.stdout.split('\n'):
            if '✅' in line or '实体:' in line or '事件:' in line:
                print(f"    {line.strip()}")
        return True
    else:
        print(f"    入库失败: {r.stderr[:150]}")
        return False

def process_section(section, idx, total):
    title = section.split('\n')[0][:50]
    chunks = chunk_text(section)
    print(f"[{idx:03d}/{total}] {title} ({len(section)}字符, {len(chunks)}段)")

    ok = 0
    for ci, chunk in enumerate(chunks, 1):
        if len(chunks) > 1:
            print(f"  段 {ci}/{len(chunks)}")
        data = ner(chunk, title)
        if data is None:
            return False  # rate limit
        entities = len(data.get("entities", []))
        events   = len(data.get("events", []))
        print(f"  实体:{entities} 事件:{events}")
        if ingest(data):
            ok += 1

    return ok > 0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run",  action="store_true")
    parser.add_argument("--section",  type=int)
    parser.add_argument("--start",    type=int, default=1)
    parser.add_argument("--end",      type=int)
    args = parser.parse_args()

    with open(FILE_PATH, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()

    sections = split_sections(text)
    total    = len(sections)
    print(f"文件: {FILE_PATH}")
    print(f"章节: {total}")

    if args.dry_run:
        for i, s in enumerate(sections, 1):
            title = s.split('\n')[0][:60]
            chunks = chunk_text(s)
            print(f"[{i:03d}] {title} ({len(s)}字符, {len(chunks)}段)")
        return

    if args.section:
        targets = [(args.section, sections[args.section-1])]
    else:
        end = args.end or total
        targets = [(i, sections[i-1]) for i in range(args.start, end+1)]

    ok, fail, stopped = 0, 0, False
    for idx, section in targets:
        result = process_section(section, idx, total)
        if result is False:
            print("\n⚠️  Rate limit 触发，停止。明天从这里继续：")
            print(f"  python3 scripts/ingest_xmind_a.py --start {idx}")
            stopped = True
            break
        elif result:
            ok += 1
        else:
            fail += 1

    print(f"\n完成: {ok}成功 / {fail}失败")
    if not stopped and ok > 0:
        print("同步到 Supabase...")
        subprocess.run(["python3", "scripts/sync_to_supabase.py"])

if __name__ == "__main__":
    main()
