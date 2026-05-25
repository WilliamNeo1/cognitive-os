# CCC 认知情报系统 — 工作流手册

## 日常数据入库流程

### 方案A：手动（主力）
1. 在 XMind 里截图
2. 上传截图给 Claude
3. Claude 返回结构化 JSON
4. 复制 JSON 到文件，比如 /tmp/data.json
5. 运行入库：
   python3 scripts/ingest_v3.py --json /tmp/data.json
6. 同步到 Supabase：
   python3 scripts/sync_to_supabase.py
7. 生成 embedding：
   python3 scripts/generate_embeddings.py

### 方案B：自动（备用）
1. 设置 OpenAI key（只需设置一次）：
   echo 'export OPENAI_API_KEY="sk-你的key"' >> ~/.zshrc
   source ~/.zshrc
2. 把截图放入监控文件夹：
   ~/Desktop/ccc_inbox/
3. 运行监控脚本（后台运行）：
   python3 scripts/watch_inbox.py &
4. 脚本自动处理并入库

## 完整 Pipeline

XMind截图
    ↓
ingest_v3.py（入库）
    ↓
本地数据库
├── raw_documents（原文）
├── documents（结构化JSON）
├── clean_entities（干净实体）
├── clean_document_entities（实体-文档关联）
├── clean_graph_edges（语义边）
├── events（事件）
└── claims（声明）
    ↓
sync_to_supabase.py（同步）
    ↓
generate_embeddings.py（向量）
    ↓
Supabase（线上搜索）

## 表结构说明

| 表名 | 用途 | 是否同步到云端 |
|------|------|----------------|
| raw_documents | 原始文本，永久保留 | ✅ |
| documents | 结构化JSON | ✅ |
| clean_entities | 干净实体主表 | ✅ |
| clean_document_entities | 实体-文档关联 | ✅ |
| clean_graph_edges | 语义共现图谱 | ✅ |
| events | 时间事件 | ✅ |
| claims | 声明/判断 | ✅ |
| person_aliases | 别名库（手工维护） | ✅ |
| person_noise_library | 噪音库（手工维护） | ✅ |
| cognitive_nodes | 认知节点（v4） | ✅ |
| cognitive_edges | 认知边（v4） | ✅ |
| contradictions | 反证层（v4） | ✅ |
| signals | 风险信号（v4） | ✅ |

## 命令速查

# 入库（方案A）
python3 scripts/ingest_v3.py --json /tmp/data.json

# 入库（方案B单张图）
python3 scripts/ingest_v3.py --image ~/Desktop/screenshot.png

# 同步到云端
python3 scripts/sync_to_supabase.py

# 生成 embedding（新文档入库后运行）
python3 scripts/generate_embeddings.py

# 搜索测试
curl "https://ccc-lab.vercel.app/api/search?q=习近平"
