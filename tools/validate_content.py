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
NOT_VEGETARIAN = {"beef-stock", "chicken-stock", "fish-sauce", "dashi", "gelatin", "worcestershire"}
NOT_VEGAN = {"egg", "honey"}
GLUTEN = {"flour", "bread", "baguette", "pasta", "savoiardi", "puff-pastry", "beer",
          "semolina", "bliny-ready", "doubanjiang"}
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

    for code in country_codes - used_countries:
        warn("countries.json", f"у страны «{code}» нет ни одного рецепта")
    for chef in chef_ids - used_chefs:
        warn("chefs.json", f"у шефа «{chef}» нет ни одного рецепта")

    print(f"Рецептов: {len(recipe_ids)}, продуктов: {len(pantry_keys)}, техник: {len(term_ids)}, "
          f"стран: {len(country_codes)}, шефов: {len(chef_ids)}, фактов: {len(facts)}")
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
