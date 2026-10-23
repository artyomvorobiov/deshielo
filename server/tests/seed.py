#!/usr/bin/env python3
"""Демо-данные для локального сервера сообщества: три автора, рецепты с фото и отзывы.

    python3 server/tests/seed.py            # сервер на http://127.0.0.1:8090
    PB_URL=http://127.0.0.1:8091 python3 server/tests/seed.py

Пароль всех демо-аккаунтов — deshielo-demo (почты: anna@example.com, boris@example.com, vera@example.com).
Повторный запуск ничего не дублирует: существующие аккаунты просто используются.
"""
import sys

from pb_client import make_png, request, sign_in, sign_up, wait_until_healthy

PASSWORD = "deshielo-demo"

AUTHORS = [("anna@example.com", "Анна"), ("boris@example.com", "Борис"), ("vera@example.com", "Вера")]

RECIPES = [
    ("anna@example.com", {
        "title": "Тыквенный суп с имбирём",
        "summary": "Бархатный и яркий, готовится за 40 минут.",
        "category": "soup", "difficulty": 1, "prep_minutes": 15, "cook_minutes": 30, "servings": 4,
        "ingredients": [{"name": "Тыква", "amount": 800, "unit": "g"}, {"name": "Лук репчатый", "amount": 1, "unit": "pcs"},
                        {"name": "Имбирь", "amount": 20, "unit": "g"}, {"name": "Кокосовое молоко", "amount": 400, "unit": "ml"},
                        {"name": "Соль", "unit": "toTaste"}],
        "steps": [{"title": "Обжарьте", "text": "Обжарьте лук и имбирь на масле до мягкости.", "timer": 5},
                  {"title": "Варите", "text": "Добавьте тыкву и воду, варите до мягкости.", "timer": 20},
                  {"title": "Пюрируйте", "text": "Влейте кокосовое молоко и пробейте блендером."}],
    }, ((233, 140, 40), (250, 220, 160))),
    ("boris@example.com", {
        "title": "Мегрельский хачапури",
        "summary": "Сулугуни внутри и сверху, тесто на мацони.",
        "category": "baking", "country": "GE", "difficulty": 2, "prep_minutes": 30, "cook_minutes": 15, "servings": 4,
        "ingredients": [{"name": "Мука", "amount": 500, "unit": "g"}, {"name": "Мацони", "amount": 300, "unit": "ml"},
                        {"name": "Сулугуни", "amount": 600, "unit": "g"}, {"name": "Яйцо", "amount": 1, "unit": "pcs"}],
        "steps": [{"title": "Тесто", "text": "Замесите мягкое тесто и дайте ему отдохнуть.", "timer": 30},
                  {"title": "Выпекайте", "text": "Сформируйте лепёшку с сыром и выпекайте при 230 °C.", "timer": 12}],
    }, ((201, 162, 75), (255, 244, 214))),
    ("vera@example.com", {
        "title": "Шарлотка с антоновкой",
        "summary": "Три яйца, стакан сахара, стакан муки и много кислых яблок.",
        "category": "baking", "country": "RU", "difficulty": 1, "prep_minutes": 15, "cook_minutes": 40, "servings": 6,
        "ingredients": [{"name": "Яблоки", "amount": 4, "unit": "pcs"}, {"name": "Яйцо", "amount": 3, "unit": "pcs"},
                        {"name": "Сахар", "amount": 180, "unit": "g"}, {"name": "Мука", "amount": 160, "unit": "g"}],
        "steps": [{"title": "Взбейте", "text": "Взбейте яйца с сахаром в пышную массу.", "timer": 7},
                  {"title": "Выпекайте", "text": "Вмешайте муку, вылейте на яблоки и выпекайте при 180 °C.", "timer": 40}],
    }, ((180, 83, 42), (243, 227, 181))),
]

REVIEWS = [
    ("boris@example.com", ("recipe", "Тыквенный суп с имбирём"), 5, "Добавил тыквенные семечки — шикарно!"),
    ("vera@example.com", ("recipe", "Мегрельский хачапури"), 5, "Тесто на мацони — открытие."),
    ("anna@example.com", ("recipe", "Шарлотка с антоновкой"), 4, "Яблок положила побольше."),
    ("anna@example.com", ("catalog_id", "plov"), 5, "Как в Ташкенте."),
    ("boris@example.com", ("catalog_id", "carbonara"), 5, "Наконец-то без сливок."),
    ("vera@example.com", ("catalog_id", "syrniki"), 4, "Добавила ваниль и цедру."),
]


def session(email, name):
    auth = sign_in(email, PASSWORD)
    if not auth.ok:
        created = sign_up(email, PASSWORD, name)
        if not created.ok:
            raise SystemExit(f"Не удалось создать {email}: {created}")
        auth = sign_in(email, PASSWORD)
    return auth.body["token"], auth.body["record"]["id"]


def main():
    wait_until_healthy()
    users = {email: session(email, name) for email, name in AUTHORS}
    recipe_ids = {}
    for email, recipe, colors in RECIPES:
        token, user_id = users[email]
        existing = request("GET", "/api/collections/recipes/records", token=token,
                           query={"filter": f'author = "{user_id}" && title = "{recipe["title"]}"'})
        if existing.ok and existing.body["items"]:
            recipe_ids[recipe["title"]] = existing.body["items"][0]["id"]
            continue
        created = request("POST", "/api/collections/recipes/records", token=token,
                          json_body={**recipe, "author": user_id, "published": True},
                          files=[("photos", "photo.png", make_png(480, 360, colors), "image/png")])
        if not created.ok:
            raise SystemExit(f"Рецепт «{recipe['title']}» не создан: {created}")
        recipe_ids[recipe["title"]] = created.body["id"]
    for email, (field, value), rating, comment in REVIEWS:
        token, user_id = users[email]
        target = recipe_ids[value] if field == "recipe" else value
        body = {"author": user_id, field: target, "rating": rating, "comment": comment}
        response = request("POST", "/api/collections/reviews/records", token=token, json_body=body,
                           files=[("photo", "result.png", make_png(480, 360), "image/png")])
        if not response.ok and "unique" not in str(response.body):
            print(f"! отзыв не добавлен: {response}")
    print(f"Готово: {len(users)} автора, {len(recipe_ids)} рецепта, {len(REVIEWS)} отзывов. Пароль: {PASSWORD}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
