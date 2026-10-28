#!/usr/bin/env python3
"""Проверка контента Deshielo: схема JSON и перекрёстные ссылки.

Запуск:  python3 tools/validate_content.py
Завершается с кодом 1, если найдены ошибки. Предупреждения не мешают сборке.
"""
import json
import re
import sys
from pathlib import Path

CONTENT = Path(__file__).resolve().parent.parent / "Shared" / "Content"

UNITS = {"g", "kg", "ml", "l", "pcs", "tbsp", "tsp", "pinch", "clove", "bunch",
         "sprig", "slice", "leaf", "stalk", "head", "toTaste"}
CATEGORIES = {"soup", "main", "side", "salad", "dessert", "baking", "breakfast", "drink", "snack"}
AISLES = {"vegetables", "fruits", "meat", "fish", "dairy", "bakery", "grocery", "spices",
          "drinks", "frozen", "other"}
DIETS = {"vegetarian", "vegan", "gluten-free"}
NOT_VEGETARIAN = {"beef-stock", "chicken-stock", "fish-sauce", "dashi", "gelatin", "worcestershire",
                  "kimchi", "green-curry-paste", "tom-yum-paste"}
NOT_VEGAN = {"egg", "honey", "mayonnaise"}
GLUTEN = {"flour", "bread", "baguette", "pasta", "savoiardi", "puff-pastry", "beer",
          "semolina", "bliny-ready", "doubanjiang", "rye-bread", "rye-sourdough", "kvass",
          "pearl-barley", "bulgur", "oats", "noodles", "breadcrumbs", "panko", "filo", "lavash",
          "dumpling-wrappers", "soy-sauce", "kecap-manis", "hoisin", "gochujang", "burger-buns",
          "cookies", "sponge-cake"}
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

errors: list = []
warnings: list = []


def err(where: str, message: str) -> None:
    errors.append(f"✗ {where}: {message}")


def warn(where: str, message: str) -> None:
    warnings.append(f"! {where}: {message}")


def load(name: str):
    path = CONTENT / name
    try:
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        err(name, "файл не найден")
    except json.JSONDecodeError as e:
        err(name, f"ошибка JSON: {e}")
    return None


def unique(items, key, where):
    seen = set()
    for item in items:
        value = item.get(key)
        if value in seen:
            err(where, f"повторяется {key} «{value}»")
        seen.add(value)
    return seen


def require(obj, fields, where):
    for field, kind in fields.items():
        if field not in obj:
            err(where, f"нет поля «{field}»")
        elif not isinstance(obj[field], kind):
            err(where, f"поле «{field}» должно быть {kind}")


COUNTRY = re.compile(r"^[A-Z]{2}$")


def check_palette(obj, where):
    palette = obj.get("palette")
    if not isinstance(palette, list) or len(palette) != 3 or not all(HEX.match(str(c)) for c in palette):
        err(where, "palette — три цвета #RRGGBB")


def check_place(obj, where):
    if not COUNTRY.match(str(obj.get("country", ""))):
        err(where, "country — двухбуквенный код ISO, например FR")
    lat, lon = obj.get("lat"), obj.get("lon")
    if not isinstance(lat, (int, float)) or not -90 <= lat <= 90:
        err(where, "lat — широта от −90 до 90")
    if not isinstance(lon, (int, float)) or not -180 <= lon <= 180:
        err(where, "lon — долгота от −180 до 180")


def check_pairing(pairing, where, pantry_keys, term_ids):
    if not isinstance(pairing, dict):
        err(where, "нет блока pairing")
        return
    if not isinstance(pairing.get("note"), str) or not pairing["note"].strip():
        err(where, "в pairing нет текста note")
    if not (pairing.get("keys") or pairing.get("categories") or pairing.get("countries")):
        err(where, "в pairing нужны keys, categories или countries")
    for field in ("keys", "avoid"):
        for key in pairing.get(field, []):
            if key not in pantry_keys:
                err(where, f"pairing.{field}: неизвестный продукт «{key}»")
    for category in pairing.get("categories", []):
        if category not in CATEGORIES:
            err(where, f"pairing.categories: неизвестная категория «{category}»")
    for code in pairing.get("countries", []):
        if not COUNTRY.match(str(code)):
            err(where, f"pairing.countries: «{code}» — не код страны")
    for term in pairing.get("techniques", []):
        if term not in term_ids:
            err(where, f"pairing.techniques: неизвестная техника «{term}»")
    if "sweets" in pairing and not isinstance(pairing["sweets"], bool):
        err(where, "pairing.sweets — true или false")


def check_brewing(brewing, where):
    if not isinstance(brewing, dict):
        err(where, "нет блока brewing")
        return
    temperature, grams, water = brewing.get("temperature"), brewing.get("grams"), brewing.get("water")
    if not isinstance(temperature, int) or not 50 <= temperature <= 100:
        err(where, "brewing.temperature — целое от 50 до 100 °C")
    if not isinstance(grams, (int, float)) or not 0 < grams <= 50:
        err(where, "brewing.grams — от 0 до 50 г")
    if not isinstance(water, int) or not 30 <= water <= 1000:
        err(where, "brewing.water — целое от 30 до 1000 мл")
    steeps = brewing.get("steeps")
    if not isinstance(steeps, list) or not all(isinstance(t, int) and 5 <= t <= 900 for t in steeps):
        err(where, "brewing.steeps — секунды, целые от 5 до 900")
    elif not steeps and not brewing.get("note"):
        err(where, "без steeps нужен note — как заваривать")


def validate_drinks(pantry_keys, term_ids, recipe_ids):
    """Винная и чайная карта: wine.json и tea.json."""
    wine = load("wine.json") or {}
    tea = load("tea.json") or {}
    styles, grapes, regions = wine.get("styles", []), wine.get("grapes", []), wine.get("regions", [])
    types, teas = tea.get("types", []), tea.get("teas", [])

    style_ids = unique(styles, "id", "wine.json/styles")
    grape_ids = unique(grapes, "id", "wine.json/grapes")
    region_ids = unique(regions, "id", "wine.json/regions")
    for s in styles:
        where = f"wine/styles/{s.get('id')}"
        require(s, {"id": str, "name": str, "summary": str, "description": str, "serving": str, "glass": str}, where)
        check_palette(s, where)
        check_pairing(s.get("pairing"), where, pantry_keys, term_ids)
    used_styles = set()
    for g in grapes:
        where = f"wine/grapes/{g.get('id')}"
        require(g, {"id": str, "name": str, "original": str, "summary": str, "story": str, "vivino": str,
                    "aromas": list, "styles": list, "regions": list}, where)
        if g.get("color") not in {"red", "white"}:
            err(where, "color — red или white")
        for field in ("body", "acidity", "tannin"):
            if not isinstance(g.get(field), int) or not 1 <= g[field] <= 5:
                err(where, f"{field} — целое от 1 до 5")
        if not g.get("aromas"):
            err(where, "нужен хотя бы один аромат")
        if not g.get("styles"):
            err(where, "нужен хотя бы один стиль")
        for style in g.get("styles", []):
            used_styles.add(style)
            if style not in style_ids:
                err(where, f"неизвестный стиль «{style}»")
        for region in g.get("regions", []):
            if region not in region_ids:
                err(where, f"неизвестный регион «{region}»")
        check_palette(g, where)
    grapes_by_id = {g.get("id"): g for g in grapes}
    for r in regions:
        where = f"wine/regions/{r.get('id')}"
        require(r, {"id": str, "name": str, "original": str, "summary": str, "story": str, "vivino": str,
                    "grapes": list}, where)
        check_place(r, where)
        if not r.get("grapes"):
            err(where, "нужен хотя бы один сорт")
        for grape in r.get("grapes", []):
            if grape not in grape_ids:
                err(where, f"неизвестный сорт «{grape}»")
            elif r.get("id") not in grapes_by_id[grape].get("regions", []):
                err(where, f"сорт «{grape}» не ссылается на этот регион")
    for g in grapes:
        for region in g.get("regions", []):
            match = next((r for r in regions if r.get("id") == region), None)
            if match and g.get("id") not in match.get("grapes", []):
                err(f"wine/grapes/{g.get('id')}", f"регион «{region}» не ссылается на этот сорт")
    for style in style_ids - used_styles:
        warn("wine.json", f"у стиля «{style}» нет ни одного сорта")
    sweets = (wine.get("fallback") or {}).get("sweets")
    sweet_styles = {s.get("id") for s in styles if (s.get("pairing") or {}).get("sweets")}
    if sweets not in sweet_styles:
        err("wine.json", "fallback.sweets — стиль с pairing.sweets = true")

    type_ids = unique(types, "id", "tea.json/types")
    tea_ids = unique(teas, "id", "tea.json/teas")
    for t in types:
        where = f"tea/types/{t.get('id')}"
        require(t, {"id": str, "name": str, "oxidation": str, "summary": str, "description": str}, where)
        check_palette(t, where)
        check_brewing(t.get("brewing"), where)
    used_types = set()
    for t in teas:
        where = f"tea/teas/{t.get('id')}"
        require(t, {"id": str, "name": str, "original": str, "origin": str, "summary": str, "story": str,
                    "aromas": list}, where)
        used_types.add(t.get("type"))
        if t.get("type") not in type_ids:
            err(where, f"неизвестный тип чая «{t.get('type')}»")
        if not t.get("aromas"):
            err(where, "нужен хотя бы один аромат")
        check_place(t, where)
        check_palette(t, where)
        check_brewing(t.get("brewing"), where)
        check_pairing(t.get("pairing"), where, pantry_keys, term_ids)
        if t.get("recipe") and t["recipe"] not in recipe_ids:
            err(where, f"неизвестный рецепт «{t['recipe']}»")
    for kind in type_ids - used_types:
        warn("tea.json", f"у типа «{kind}» нет ни одного чая")
    for key, value in (tea.get("fallback") or {}).items():
        if key != "sweets" and key not in CATEGORIES:
            err("tea.json", f"fallback: неизвестная категория «{key}»")
        if value not in tea_ids:
            err("tea.json", f"fallback: неизвестный чай «{value}»")

    return (f"Вино: стилей {len(style_ids)}, сортов {len(grape_ids)}, регионов {len(region_ids)}; "
            f"чай: типов {len(type_ids)}, сортов {len(tea_ids)}")


def main() -> int:
    pantry = load("pantry.json") or []
    collections = load("collections.json") or []
    chefs = load("chefs.json") or []
    countries = load("countries.json") or []
    eras = load("eras.json") or []
    glossary = load("glossary.json") or []
    facts = load("facts.json") or []
    seasonal = load("seasonal.json") or []
    delivery = load("delivery.json") or []
    measures = load("measures.json") or {}

    pantry_keys = unique(pantry, "key", "pantry.json")
    pantry_by_key = {p["key"]: p for p in pantry if "key" in p}
    for p in pantry:
        require(p, {"key": str, "name": str, "category": str, "emoji": str}, f"pantry/{p.get('key')}")
        if p.get("category") not in AISLES:
            err(f"pantry/{p.get('key')}", f"неизвестная категория «{p.get('category')}»")

    collection_ids = unique(collections, "id", "collections.json")
    for c in collections:
        require(c, {"id": str, "title": str, "subtitle": str, "description": str, "symbol": str, "palette": list},
                f"collections/{c.get('id')}")

    chef_ids = unique(chefs, "id", "chefs.json")
    country_codes = unique(countries, "code", "countries.json")
    for c in countries:
        require(c, {"code": str, "name": str, "cuisine": str, "lat": (int, float), "lon": (int, float)},
                f"countries/{c.get('code')}")
    for c in chefs:
        require(c, {"id": str, "name": str, "years": str, "role": str, "bio": str}, f"chefs/{c.get('id')}")
        if c.get("country") and c["country"] not in country_codes:
            warn(f"chefs/{c.get('id')}", f"страны «{c['country']}» нет в countries.json")

    unique(eras, "id", "eras.json")
    sorted_eras = sorted(eras, key=lambda e: e.get("fromYear", 0))
    for previous, current in zip(sorted_eras, sorted_eras[1:]):
        if previous["toYear"] + 1 != current["fromYear"]:
            err("eras.json", f"разрыв между «{previous['id']}» и «{current['id']}»")

    term_ids = unique(glossary, "id", "glossary.json")
    for t in glossary:
        require(t, {"id": str, "term": str, "definition": str}, f"glossary/{t.get('id')}")

    # Рецепты из всех файлов recipes-*.json
    recipes = []
    recipe_files = sorted(CONTENT.glob("recipes-*.json"))
    if not recipe_files:
        err("Content", "нет файлов recipes-*.json")
    for path in recipe_files:
        data = load(path.name)
        if not isinstance(data, list):
            err(path.name, "ожидается массив рецептов")
            continue
        recipes.extend((path.name, r) for r in data)

    recipe_ids = set()
    used_keys, used_terms, used_chefs, used_countries = set(), set(), set(), set()
    for file_name, r in recipes:
        rid = r.get("id", "?")
        where = f"{file_name}/{rid}"
        if rid in recipe_ids:
            err(where, "повторяющийся id")
        recipe_ids.add(rid)
        if not ID.match(rid):
            err(where, "id должен быть в kebab-case латиницей")
        require(r, {"id": str, "title": str, "summary": str, "story": str, "category": str,
                    "difficulty": int, "prepMinutes": int, "cookMinutes": int, "servings": int,
                    "palette": list, "ingredients": list, "steps": list}, where)
        for c in r.get("collections", []):
            if c not in collection_ids:
                err(where, f"неизвестная коллекция «{c}»")
        if r.get("chef"):
            used_chefs.add(r["chef"])
            if r["chef"] not in chef_ids:
                err(where, f"неизвестный шеф «{r['chef']}»")
            if "chefs" not in r.get("collections", []):
                warn(where, "есть шеф, но рецепт не в коллекции «chefs»")
        if r.get("country"):
            used_countries.add(r["country"])
            if r["country"] not in country_codes:
                err(where, f"неизвестная страна «{r['country']}»")
        if r.get("category") not in CATEGORIES:
            err(where, f"неизвестная категория «{r.get('category')}»")
        if not 1 <= r.get("difficulty", 0) <= 3:
            err(where, "difficulty должна быть от 1 до 3")
        for field in ("prepMinutes", "cookMinutes", "restMinutes"):
            if field in r and (not isinstance(r[field], int) or r[field] < 0):
                err(where, f"{field} должно быть целым неотрицательным")
        if r.get("servings", 0) < 1:
            err(where, "servings должно быть ≥ 1")
        palette = r.get("palette", [])
        if len(palette) != 3 or not all(isinstance(c, str) and HEX.match(c) for c in palette):
            err(where, "palette — ровно три цвета #RRGGBB")
        for d in r.get("diets", []):
            if d not in DIETS:
                err(where, f"неизвестная диета «{d}»")
        if "year" in r and not isinstance(r["year"], int):
            err(where, "year должен быть целым числом (до н. э. — отрицательным)")
        if "year" in r and isinstance(r["year"], int):
            if not any(e["fromYear"] <= r["year"] <= e["toYear"] for e in eras):
                err(where, f"год {r['year']} не попадает ни в одну эпоху")
            if "yearLabel" not in r:
                warn(where, "есть year, но нет yearLabel")

        if not r.get("ingredients"):
            err(where, "нет ингредиентов")
        required_keys = set()
        for i, ing in enumerate(r.get("ingredients", [])):
            iw = f"{where}/ingredient[{i}]"
            if not isinstance(ing.get("name"), str) or not ing["name"].strip():
                err(iw, "нет названия")
            unit = ing.get("unit")
            if unit is not None and unit not in UNITS:
                err(iw, f"неизвестная единица «{unit}»")
            amount = ing.get("amount")
            if amount is not None and (not isinstance(amount, (int, float)) or amount <= 0):
                err(iw, "amount должно быть положительным числом")
            if unit == "toTaste" and amount is not None:
                err(iw, "у «по вкусу» не должно быть количества")
            if amount is not None and unit is None:
                err(iw, "есть количество, но нет единицы")
            key = ing.get("key")
            if key is None:
                warn(iw, f"«{ing.get('name')}» без key — не попадёт в поиск «Из холодильника»")
            elif key not in pantry_keys:
                err(iw, f"неизвестный ключ продукта «{key}» (добавьте его в pantry.json)")
            else:
                used_keys.add(key)
                if not ing.get("optional"):
                    required_keys.add(key)

        diets = set(r.get("diets", []))
        meat_keys = {k for k in required_keys
                     if pantry_by_key.get(k, {}).get("category") in ("meat", "fish") or k in NOT_VEGETARIAN}
        if ("vegetarian" in diets or "vegan" in diets) and meat_keys:
            err(where, f"помечен вегетарианским, но содержит {sorted(meat_keys)}")
        animal = {k for k in required_keys
                  if pantry_by_key.get(k, {}).get("category") == "dairy" or k in NOT_VEGAN}
        if "vegan" in diets and animal:
            err(where, f"помечен веганским, но содержит {sorted(animal)}")
        if "gluten-free" in diets and required_keys & GLUTEN:
            err(where, f"помечен «без глютена», но содержит {sorted(required_keys & GLUTEN)}")
        if "vegan" in diets and "vegetarian" not in diets:
            warn(where, "веганский рецепт стоит пометить и как вегетарианский")

        if not r.get("steps"):
            err(where, "нет шагов")
        for i, step in enumerate(r.get("steps", [])):
            sw = f"{where}/step[{i + 1}]"
            if not isinstance(step.get("text"), str) or len(step["text"].strip()) < 10:
                err(sw, "слишком короткий текст шага")
            timer = step.get("timer")
            if timer is not None and (not isinstance(timer, (int, float)) or not 0 < timer <= 600):
                err(sw, "timer — минуты, от 0 до 600")
            temperature = step.get("temperature")
            if temperature is not None and (not isinstance(temperature, int) or not 20 <= temperature <= 300):
                err(sw, "temperature — градусы Цельсия, целое от 20 до 300")
            for t in step.get("techniques", []):
                used_terms.add(t)
                if t not in term_ids:
                    err(sw, f"неизвестная техника «{t}» (добавьте в glossary.json)")

        source = r.get("source")
        if source is not None:
            if not isinstance(source, dict) or "title" not in source:
                err(where, "у source должно быть поле title")
            elif source.get("quote") and not source.get("translation") and source.get("quoteLanguage") != "русский":
                warn(where, "есть цитата на иностранном языке без перевода")

    for f in facts:
        if f.get("recipe") and f["recipe"] not in recipe_ids:
            err(f"facts/{f.get('id')}", f"неизвестный рецепт «{f['recipe']}»")
    unique(facts, "id", "facts.json")

    months = [s.get("month") for s in seasonal]
    if sorted(months) != list(range(1, 13)):
        err("seasonal.json", "нужно ровно 12 месяцев, 1–12")
    for s in seasonal:
        for key in s.get("keys", []):
            if key not in pantry_keys:
                err(f"seasonal/{s.get('month')}", f"неизвестный продукт «{key}»")

    unique(delivery, "id", "delivery.json")
    for d in delivery:
        where = f"delivery/{d.get('id')}"
        require(d, {"id": str, "name": str, "kind": str, "homeURL": str}, where)
        if not str(d.get("homeURL", "")).startswith("https://"):
            err(where, "homeURL должен начинаться с https://")
        if d.get("searchURL") and "{query}" not in d["searchURL"]:
            err(where, "в searchURL нет {query}")
        if d.get("kind") not in {"groceries", "restaurants", "places"}:
            err(where, "kind: groceries, restaurants или places")

    for section in ("volumes", "products", "historic", "ovenMarks"):
        if not measures.get(section):
            err("measures.json", f"нет раздела «{section}»")

    drinks = validate_drinks(pantry_keys, term_ids, recipe_ids)

    for code in country_codes - used_countries:
        warn("countries.json", f"у страны «{code}» нет ни одного рецепта")
    for chef in chef_ids - used_chefs:
        warn("chefs.json", f"у шефа «{chef}» нет ни одного рецепта")

    print(f"Рецептов: {len(recipe_ids)}, продуктов: {len(pantry_keys)}, техник: {len(term_ids)}, "
          f"стран: {len(country_codes)}, шефов: {len(chef_ids)}, фактов: {len(facts)}")
    print(drinks)
    for line in warnings:
        print(line)
    for line in errors:
        print(line)
    if errors:
        print(f"\nНайдено ошибок: {len(errors)}")
        return 1
    print("Контент в порядке ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
