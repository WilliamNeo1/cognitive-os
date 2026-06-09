#!/usr/bin/env python3
"""
parse_xmind_md.py — XMind 导出 Markdown 分段入库
按 ## 章节切分，每段独立 NER，逐段入库

用法:
  python3 scripts/parse_xmind_md.py --file export.md --dry-run
  python3 scripts/parse_xmind_md.py --file export.md
  python3 scripts/parse_xmind_md.py --file export.md --section 3
"""

import json, os, sys, argparse, re, subprocess, tempfile
import requests

GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "").strip()
CHUNK_SIZE   = 3000

def split_sections(text):
    sections = re.split(r'\n(?=## )', text)
    result = []
    for s in sections:
        s = s.strip()
        if not s or len(s) < 20:
            continue
        lines = [l for l in s.split('\n') if l.strip() and l.strip() not in ['', '#', '##']]
        if len(lines) < 2:
            continue
        result.append(s)
    return result

def ner_section(text, section_title):
    if not GROQ_API_KEY:
        print("未设置 GROQ_API_KEY")
        sys.exit(1)

    truncated = text[:CHUNK_SIZE]
    prompt = f"""你是一个情报分析系统。从以下XMind笔记内容中提取实体、关系、事件，只返回JSON不要解释：
{{
  "title": "章节主题（一句话）",
  "category": "PERSON|ORG|EVENT|PLACE|CLAIM",
  "language": "zh|en|mixed",
  "source_type": "xmind",
  "source_url": null,
  "verified": false,
  "entities": [
    {{"name":"实体名","type":"PERSON|ORG|GPE|EVENT","role":"角色描述","aliases":[],"notes":"关键信息","relations":[{{"to":"关联实体名","type":"family_relation|political_alignment|financial_control|colleague|organizational_dependency","direction":"source_to_target"}}]}}
  ],
  "events": [
    {{"date":"YYYY或YYYY-MM-DD","location":"","summary":"事件摘要","persons":[]}}
  ],
  "claims": [
    {{"text":"声明内容","confidence":0.7,"source":null}}
  ],
  "raw_content": "核心内容摘要（150字以内）"
}}

注意：
1. 提取所有人名、组织、地点
2. 重点提取人物之间的关系（家庭、政治、财务）
3. 金额、日期、身份证号等作为 notes 保留
4. 只输出JSON，不要任何解释

内容：
{truncated}"""

    try:
        resp = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
            json={
                "model": "llama-3.3-70b-versatile",
                "temperature": 0.1,
                "max_tokens": 2000,
                "messages": [
                    {"role": "system", "content": "你是专业情报分析系统，只输出JSON，不要任何解释或markdown符号。"},
                    {"role": "user", "content": prompt}
                ]
            },
            timeout=30,
            verify=True,
        )
        raw = resp.json()["choices"][0]["message"]["content"].strip()
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        raw = raw.strip()
        from json_repair import repair_json
        result = json.loads(repair_json(raw))
        result["source_type"] = "xmind"
        return result
    except Exception as e:
        print(f"  NER 失败: {e}")
        return {
            "title": section_title[:50],
            "source_type": "xmind",
            "raw_content": text[:500],
            "entities": [], "events": [], "claims": []
        }

def ingest_section(data):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json",
                                     encoding="utf-8", delete=False) as f:
        json.dump(data, f, ensure_ascii=False)
        tmp = f.name
    result = subprocess.run(
        ["python3", "scripts/ingest_v3.py", "--json", tmp],
        capture_output=True, text=True
    )
    os.unlink(tmp)
    if result.returncode == 0:
        for line in result.stdout.split('\n'):
            if line.strip():
                print(f"    {line}")
    else:
        print(f"    入库失败: {result.stderr[:200]}")
    return result.returncode == 0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file",    required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--section", type=int, help="只处理第N段（从1开始）")
    parser.add_argument("--start",   type=int, default=1, help="从第N段开始")
    args = parser.parse_args()

    with open(args.file, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()

    sections = split_sections(text)
    print(f"文件: {args.file}")
    print(f"章节总数: {len(sections)}")
    print()

    if args.dry_run:
        for i, s in enumerate(sections, 1):
            title = s.split('\n')[0][:60]
            print(f"[{i:03d}] {title} ({len(s)}字符)")
        return

    targets = [sections[args.section-1]] if args.section else sections[args.start-1:]

    ok, fail = 0, 0
    for i, section in enumerate(targets, args.start if not args.section else args.section):
        title = section.split('\n')[0][:50]
        print(f"[{i:03d}/{len(sections)}] {title}")
        data = ner_section(section, title)
        entities = len(data.get("entities", []))
        events   = len(data.get("events", []))
        print(f"  实体:{entities} 事件:{events}")
        if ingest_section(data):
            ok += 1
        else:
            fail += 1

    print(f"\n完成: {ok} 成功 / {fail} 失败")
    if ok > 0:
        print("同步到 Supabase...")
        subprocess.run(["python3", "scripts/sync_to_supabase.py"])

if __name__ == "__main__":
    main()
