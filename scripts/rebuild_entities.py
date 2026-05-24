from supabase import create_client
import spacy

SUPABASE_URL = "https://mgigbiblwqywcegkhjpu.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1naWdiaWJsd3F5d2NlZ2toanB1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTI0MTI3OCwiZXhwIjoyMDk0ODE3Mjc4fQ.Kdx9uKFCQVCqcVs4ZXXCUPGE4jsIa3zX07segnEdLjo"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

nlp = spacy.load("zh_core_web_sm")

def fetch_docs(limit=2554):
    res = supabase.schema("ccc").table("documents").select("id,content").limit(limit).execute()
    return res.data

def extract_entities(text):
    doc = nlp(text)
    return [(ent.text, ent.label_) for ent in doc.ents]

def run():
    docs = fetch_docs()

    for d in docs:
        ents = extract_entities(d["content"])

        for ent, label in ents:
            supabase.schema("ccc").table("staging_entities").insert({
                "canonical_name": ent,
                "entity_type": label,
                "source_document_id": d["id"],
                "raw_text": ent
            }).execute()

            supabase.schema("ccc").table("staging_document_entities").insert({
                "document_id": d["id"],
                "entity_name": ent,
                "entity_type": label,
                "frequency": 1
            }).execute()

    print("DONE")

if __name__ == "__main__":
    run()