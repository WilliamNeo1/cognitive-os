# scripts/backfill_slugs.py
import psycopg2, re, os

def make_slug(name):
    """Convert entity name to canonical slug."""
    # Manual overrides for key entities
    overrides = {
        '习近平': 'xi-jinping',
        '中共': 'ccp',
        '普京': 'putin-vladimir',
        '特朗普': 'trump-donald',
        '美联储': 'federal-reserve',
        'WEF': 'wef',
        '世界经济论坛': 'world-economic-forum',
        '中国': 'china',
        '美国': 'united-states',
        '俄罗斯': 'russia',
        '江泽民': 'jiang-zemin',
        '胡锦涛': 'hu-jintao',
        '邓小平': 'deng-xiaoping',
        '毛泽东': 'mao-zedong',
        '李强': 'li-qiang',
        '王岐山': 'wang-qishan',
        '赵乐际': 'zhao-leji',
        '蔡奇': 'cai-qi',
        '李希': 'li-xi',
        '丁薛祥': 'ding-xuexiang',
        '李克强': 'li-keqiang',
        '温家宝': 'wen-jiabao',
        '朱镕基': 'zhu-rongji',
        '彭丽媛': 'peng-liyuan',
        '马云': 'ma-yun',
        '任正非': 'ren-zhengfei',
        '台湾': 'taiwan',
        '香港': 'hong-kong',
        '联合国': 'united-nations',
        '北约': 'nato',
        '欧盟': 'european-union',
        '中国人民解放军': 'pla',
        '华为': 'huawei',
        '阿里巴巴': 'alibaba',
        '腾讯': 'tencent',
        '字节跳动': 'bytedance',
        '百度': 'baidu',
        '比尔·盖茨': 'gates-bill',
        '埃隆·马斯克': 'musk-elon',
        '乔治·索罗斯': 'soros-george',
        '亨利·基辛格': 'kissinger-henry',
        '唐纳德·特朗普': 'trump-donald',
        '拜登': 'biden-joe',
        '奥巴马': 'obama-barack',
    }
    if name in overrides:
        return overrides[name]
    
    # Auto-generate for English names
    slug = name.lower()
    slug = re.sub(r'[^a-z0-9\s-]', '', slug)
    slug = re.sub(r'\s+', '-', slug.strip())
    slug = re.sub(r'-+', '-', slug)
    
    # If result is empty (Chinese name with no override), return None
    if not slug or slug == '-':
        return None
    return slug[:100]

conn = psycopg2.connect(
    host='localhost', port=5432, dbname='postgres',
    user='postgres',
    password=os.environ.get('LOCAL_PG_PASSWORD','')
)
cur = conn.cursor()

cur.execute("SELECT id, canonical_name FROM ccc.clean_entities WHERE canonical_slug IS NULL")
rows = cur.fetchall()

updated = 0
skipped = 0
for entity_id, name in rows:
    slug = make_slug(name)
    if slug:
        try:
            cur.execute(
                "UPDATE ccc.clean_entities SET canonical_slug = %s WHERE id = %s",
                (slug, entity_id)
            )
            updated += 1
        except psycopg2.errors.UniqueViolation:
            conn.rollback()
            # Add numeric suffix to resolve collision
            for suffix in range(2, 20):
                try:
                    cur.execute(
                        "UPDATE ccc.clean_entities SET canonical_slug = %s WHERE id = %s",
                        (f"{slug}-{suffix}", entity_id)
                    )
                    updated += 1
                    break
                except psycopg2.errors.UniqueViolation:
                    conn.rollback()
    else:
        skipped += 1

conn.commit()
print(f"Updated: {updated}, Skipped (Chinese no override): {skipped}")
cur.close()
conn.close()
# Phase 2: backfill Chinese entities with pinyin
from pypinyin import lazy_pinyin

conn = psycopg2.connect(
    host='localhost', port=5432, dbname='postgres',
    user='postgres',
    password=os.environ.get('LOCAL_PG_PASSWORD','')
)
cur = conn.cursor()

cur.execute("SELECT id, canonical_name FROM ccc.clean_entities WHERE canonical_slug IS NULL")
rows = cur.fetchall()

updated = 0
for entity_id, name in rows:
    try:
        pinyin = lazy_pinyin(name)
        slug = '-'.join(pinyin)
        slug = re.sub(r'[^a-z0-9-]', '', slug)
        slug = re.sub(r'-+', '-', slug).strip('-')[:100]
        if not slug:
            continue
        try:
            cur.execute(
                "UPDATE ccc.clean_entities SET canonical_slug = %s WHERE id = %s",
                (slug, entity_id)
            )
            updated += 1
        except psycopg2.errors.UniqueViolation:
            conn.rollback()
            for suffix in range(2, 50):
                try:
                    cur.execute(
                        "UPDATE ccc.clean_entities SET canonical_slug = %s WHERE id = %s",
                        (f"{slug}-{suffix}", entity_id)
                    )
                    updated += 1
                    break
                except psycopg2.errors.UniqueViolation:
                    conn.rollback()
    except Exception as e:
        print(f"Error on {name}: {e}")

conn.commit()
print(f"Pinyin updated: {updated}")
cur.close()
conn.close()
