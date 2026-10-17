"""Builds Resources/glossary.json from scripts/glossary_ru.txt and scripts/glossary_kk.txt."""
import json, os
here = os.path.dirname(os.path.abspath(__file__))
def load(name):
    out = {}
    for n, line in enumerate(open(os.path.join(here, name), encoding="utf-8"), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        src, sep, en = line.partition("|")
        assert sep, f"{name}:{n}: missing |"
        src, en = src.strip(), en.strip()
        assert src and en, f"{name}:{n}: empty field"
        out.setdefault(src, en)
    return out
ru, kk = load("glossary_ru.txt"), load("glossary_kk.txt")
data = {"version": 1, "note": "Unofficial community glossary for the Kaspi.kz app UI. Not affiliated with Kaspi.kz.", "ru": ru, "kk": kk}
path = os.path.join(here, "..", "Resources", "glossary.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
print(f"ru={len(ru)} kk={len(kk)} -> {os.path.normpath(path)}")
