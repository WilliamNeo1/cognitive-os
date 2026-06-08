#!/usr/bin/env python3
"""
parse_file.py — 多格式文件解析器
把 txt / docx / xlsx / csv 转成 ingest_v3.py 接受的 JSON 结构
然后通过 Groq 做 NER 提取实体和事件

用法:
  python3 scripts/parse_file.py --file report.txt
  python3 scripts/parse_file.py --file data.xlsx
  python3 scripts/parse_file.py --file notes.docx
  python3 scripts/parse_file.py --file table.csv
  python3 scripts/parse_file.py --file doc.txt --dry-run
"""

import json, os, sys, argparse
from pathlib import Path

GROQ_API_KEY = os.environ.get("GROQ_API_KEY")

def read_txt(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read().strip()

def read_docx(path):
    from docx import Document
    doc = Document(path)
    paragraphs = [p.text.strip() for p in doc.paragraphs if p.text.strip()]
    return "\n".join(paragraphs)

def read_xlsx(path):
    import pandas as pd
    xl = pd.ExcelFile(path)
    parts = []
    for sheet in xl.sheet_names:
        df = pd.read_excel(path, sheet_name=sheet, dtype=str).fillna("")
        parts.append(f"[Sheet: {sheet}]\n{df.to_string(index=False)}")
    return "\n\n".join(parts)

def read_csv(path):
    import pandas as pd
    df = pd.read_csv(path, dtype=str).fillna("")
    return df.to_string(index=False)

def extract_text(path):
    ext = Path(path).suffix.lower()
    if ext == ".txt":
        return read_txt(path), "txt"
    elif ext == ".docx":
        return read_docx(path), "docx"
    elif ext in (".xlsx", ".xls"):
        return read_xlsx(path), "xlsx"
    elif ext == ".csv":
        return read_csv(path), "csv"
    else:
        print(f"不支持的格式: {ext}")
        sys.exit(1)

def ner_with_groq(text, source_type, filename):
    if not GROQ_API_KEY:
        print("未设置 GROQ_API_KEY，跳过 NER，返回最小结构")
        return {
            "title": filename,
            "source_type": source_type,
            "raw_content": text[:2000],
            "entities": [],
            "events": [],
            "claims": [],
        }

    import requests
    truncated = text[:4000]

    prompt = f"""你是一个情报分析系统。从以下文本中提取实体、事件和声明，只返回JSON不要解释：
{{
  "title": "文档主题（一句话）",
  "category": "PERSON|ORG|EVENT|PLACE|CLAIM",
  "language": "zh|en|mixed",
  "source_type": "{source_type}",
  "source_url": null,
  "verified": false,
  "entities": [
    {{"name":"实体名","type":"PERSON|ORG|GPE|EVENT","role":"角色描述","aliases":[],"notes":"备注"}}
  ],
  "events": [
    {{"date":"YYYY或YYYY-MM-DD","location":"","summary":"事件摘要","persons":[]}}
  ],
  "claims": [
    {{"text":"声明内容","confidence":0.8,"source":null}}
  ],
  "raw_content": "文档核心内容摘要（200字以内）"
}}

文本内容：
{truncated}"""

    payload = json.dumps({
        "model": "llama-3.3-70b-versatile",
        "temperature": 0.1,
        "max_tokens": 2000,
        "messages": [
            {"role": "system", "content": "你是一个专业情报分析系统，只输出JSON，不要任何解释或markdown。"},
            {"role": "user", "content": prompt}
        ]
    }).encode()

    try:
        resp = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
            json=json.loads(payload),
            timeout=30,
            verify=True,
        )
        data = resp.json()
        raw = data["choices"][0]["message"]["content"].strip()
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        result = json.loads(raw.strip())
        result["source_type"] = source_type
        return result
    except Exception as e:
        print(f"Groq NER 失败: {e}，返回最小结构")
        return {
            "title": filename,
            "source_type": source_type,
            "raw_content": text[:2000],
            "entities": [],
            "events": [],
            "claims": [],
        }

def main():
    parser = argparse.ArgumentParser(description="多格式文件解析器")
    parser.add_argument("--file",    required=True, help="文件路径")
    parser.add_argument("--dry-run", action="store_true", help="只输出JSON不入库")
    args = parser.parse_args()

    path = args.file
    if not os.path.exists(path):
        print(f"文件不存在: {path}")
        sys.exit(1)

    filename = Path(path).name
    print(f"解析文件: {filename}")

    text, source_type = extract_text(path)
    print(f"提取文本: {len(text)} 字符")

    print("NER 提取中...")
    data = ner_with_groq(text, source_type, filename)

    print(f"实体: {len(data.get('entities', []))} 个")
    print(f"事件: {len(data.get('events', []))} 个")

    if args.dry_run:
        print("\n[DRY RUN] JSON 输出:")
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return

    import subprocess, tempfile
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json",
                                     encoding="utf-8", delete=False) as f:
        json.dump(data, f, ensure_ascii=False)
        tmp_path = f.name

    print(f"写入临时文件: {tmp_path}")
    result = subprocess.run(
        ["python3", "scripts/ingest_v3.py", "--json", tmp_path],
        capture_output=False
    )
    os.unlink(tmp_path)

    if result.returncode == 0:
        print(f"入库完成: {filename}")
    else:
        print(f"入库失败: returncode={result.returncode}")

if __name__ == "__main__":
    main()
