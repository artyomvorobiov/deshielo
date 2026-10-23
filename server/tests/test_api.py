#!/usr/bin/env python3
"""Интеграционные тесты сервера сообщества: права доступа, отзывы, рейтинги, жалобы, удаление аккаунта.

Нужен запущенный PocketBase с миграциями и хуками из папки server/ на чистой базе:

    ./pocketbase serve --dir /tmp/pb_test --migrationsDir server/pb_migrations --hooksDir server/pb_hooks
    python3 server/tests/test_api.py
"""
import json
import sys
import uuid

from pb_client import make_png, request, sign_in, sign_up, wait_until_healthy

failures = []
passed = 0


def check(condition, message, response=None):
    global passed
    if condition:
        passed += 1
    else:
        failures.append(f"✗ {message}" + (f": {response}" if response is not None else ""))


def message_of(response):
    body = response.body if isinstance(response.body, dict) else {}
    return json.dumps(body, ensure_ascii=False)


RUN = uuid.uuid4().hex[:6]
PASSWORD = "very-secret-42"


class User:
    def __init__(self, name):
        self.email = f"{name.lower()}-{RUN}@example.com"
        response = sign_up(self.email, PASSWORD, name)
        check(response.ok, f"регистрация {name}", response)
        auth = sign_in(self.email, PASSWORD)
        if not auth.ok:
            raise SystemExit(f"Не удалось войти как {name}: {auth}")
        self.token = auth.body["token"]
        self.id = auth.body["record"]["id"]
        self.name = name


def recipe_payload(user, **overrides):
    payload = {
        "author": user.id,
        "title": "Бабушкины сырники",
        "summary": "Нежные, с изюмом.",
        "category": "breakfast",
        "difficulty": 1,
        "prep_minutes": 10,
        "cook_minutes": 15,
        "servings": 2,
        "published": True,
        "ingredients": [
            {"name": "Творог", "amount": 400, "unit": "g"},
            {"name": "Изюм", "amount": 2, "unit": "tbsp", "note": "по желанию"},
        ],
        "steps": [
            {"title": "Тесто", "text": "Смешайте творог с яйцом и мукой."},
            {"title": "Обжарьте", "text": "Обжарьте до золотистой корочки.", "timer": 6},
        ],
    }
    payload.update(overrides)
    return payload


def create_recipe(user, photos=0, **overrides):
    files = [("photos", f"photo{i}.png", make_png(), "image/png") for i in range(photos)]
    return request("POST", "/api/collections/recipes/records", token=user.token,
                   json_body=recipe_payload(user, **overrides), files=files or None)


def create_review(user, rating, recipe=None, catalog_id=None, comment="", photo=False, **extra):
    body = {"author": user.id, "rating": rating, "comment": comment, **extra}
    if recipe:
        body["recipe"] = recipe
    if catalog_id:
        body["catalog_id"] = catalog_id
    files = [("photo", "result.png", make_png(colors=((90, 120, 60), (240, 220, 180))), "image/png")] if photo else None
    return request("POST", "/api/collections/reviews/records", token=user.token, json_body=body, files=files)


def get_recipe(recipe_id, token=None):
    return request("GET", f"/api/collections/recipes/records/{recipe_id}", token=token)


def catalog_rating(catalog_id):
    response = request("GET", "/api/collections/catalog_ratings/records",
                       query={"filter": f'catalog_id = "{catalog_id}"'})
    items = response.body.get("items", []) if response.ok else []
    return items[0] if items else None


def main():
    wait_until_healthy()

    # Регистрация: правила сообщества обязательны, грубые имена не проходят.
    no_terms = sign_up(f"noterms-{RUN}@example.com", PASSWORD, "Без правил", accepted_terms=False)
    check(no_terms.status == 400, "регистрация без согласия с правилами отклонена", no_terms)
    rude = sign_up(f"rude-{RUN}@example.com", PASSWORD, "Сука")
    check(rude.status == 400 and "правила" in message_of(rude), "грубое имя отклонено", rude)
    wrong = sign_in(f"nobody-{RUN}@example.com", PASSWORD)
    check(wrong.status == 400, "вход с неверными данными отклонён", wrong)

    anna, boris, vera, gleb = User("Анна"), User("Борис"), User("Вера"), User("Глеб")

    # Почта автора не видна другим, имя — видно.
    profile = request("GET", f"/api/collections/users/records/{anna.id}")
    check(profile.ok and profile.body.get("name") == "Анна" and not profile.body.get("email"),
          "чужой профиль: имя видно, почта скрыта", profile)
    users_list = request("GET", "/api/collections/users/records", token=boris.token)
    check(users_list.ok and all(u["id"] == boris.id for u in users_list.body["items"]),
          "список пользователей не раскрывает чужие аккаунты", users_list)

    # Рецепты.
    created = create_recipe(anna, photos=2)
    check(created.ok, "Анна публикует рецепт с двумя фото", created)
    recipe = created.body
    check(len(recipe.get("photos", [])) == 2, "у рецепта два фото", created)
    check(recipe.get("rating_count") == 0 and recipe.get("score") == 3.5, "новый рецепт: без отзывов, оценка 3,5", created)
    photo = request("GET", f"/api/files/recipes/{recipe['id']}/{recipe['photos'][0]}", query={"thumb": "600x0"})
    check(photo.status == 200, "фото рецепта отдаётся с миниатюрой", photo.status)

    draft = create_recipe(anna, title="Черновик пирога", published=False)
    check(draft.ok, "Анна сохраняет черновик", draft)

    public = request("GET", "/api/collections/recipes/records", query={"filter": f'author = "{anna.id}"'})
    public_ids = {r["id"] for r in public.body.get("items", [])}
    check(recipe["id"] in public_ids and draft.body["id"] not in public_ids,
          "гость видит опубликованный рецепт, но не черновик", public)
    own = request("GET", "/api/collections/recipes/records", token=anna.token,
                  query={"filter": f'author = "{anna.id}"'})
    check(len(own.body.get("items", [])) == 2, "автор видит свой черновик", own)
    check(get_recipe(draft.body["id"], token=boris.token).status == 404, "чужой черновик не открывается")

    check(not create_recipe(anna, hidden=True).ok, "нельзя создать рецепт с флагом модерации")
    check(not create_recipe(anna, rating_avg=5).ok, "нельзя задать себе рейтинг")
    check(not create_recipe(boris, author=anna.id).ok, "нельзя опубликовать рецепт от чужого имени")
    check(not request("POST", "/api/collections/recipes/records", json_body=recipe_payload(anna)).ok,
          "гость не может публиковать рецепты")
    empty = create_recipe(anna, ingredients=[])
    check(empty.status == 400 and "ингредиент" in message_of(empty), "рецепт без ингредиентов отклонён", empty)
    bad_timer = create_recipe(anna, steps=[{"text": "Варите долго-долго.", "timer": 9000}])
    check(bad_timer.status == 400 and "таймер" in message_of(bad_timer), "таймер вне диапазона отклонён", bad_timer)
    swear = create_recipe(anna, title="Охуенные сырники")
    check(swear.status == 400 and "правила" in message_of(swear), "грубое слово в названии отклонено", swear)
    disguised = create_recipe(anna, steps=[{"text": "Ну и xуйня получилась, но вкусно."}])
    check(disguised.status == 400, "грубое слово латиницей в шаге отклонено", disguised)
    clean = create_recipe(anna, title="Уха по-царски", summary="Себе и гостям: гребешки, хлеб, употреблять горячей.",
                          published=False)
    check(clean.ok, "обычные слова («себе», «уха», «употреблять») не считаются грубыми", clean)

    update_path = f"/api/collections/recipes/records/{recipe['id']}"
    check(request("PATCH", update_path, token=boris.token, json_body={"title": "Взлом"}).status == 404,
          "чужой рецепт нельзя изменить")
    renamed = request("PATCH", update_path, token=anna.token, json_body={"title": "Сырники с изюмом"})
    check(renamed.ok and renamed.body["title"] == "Сырники с изюмом", "автор меняет название", renamed)
    check(not request("PATCH", update_path, token=anna.token, json_body={"hidden": False}).ok,
          "автор не может снять скрытие модератора")
    check(not request("PATCH", update_path, token=anna.token, json_body={"score": 5}).ok,
          "автор не может изменить оценку")
    more_photos = request("PATCH", update_path, token=anna.token,
                          files=[("photos+", "extra.png", make_png(), "image/png")], json_body={})
    check(more_photos.ok and len(more_photos.body.get("photos", [])) == 3, "к рецепту добавляется фото", more_photos)
    removed = request("PATCH", update_path, token=anna.token, json_body={"photos-": [recipe["photos"][0]]})
    check(removed.ok and len(removed.body.get("photos", [])) == 2, "лишнее фото удаляется", removed)

    # Поиск идёт по полю search в нижнем регистре: «сырники» находят «Сырники», «творог» — «Творог».
    def search(*words):
        conditions = " && ".join(f'search ~ "{w}"' for w in words)
        return request("GET", "/api/collections/recipes/records", query={"filter": conditions})

    found = search("сырники", "изюм")
    check(found.ok and any(r["id"] == recipe["id"] for r in found.body["items"]), "поиск по названию без учёта регистра", found)
    by_ingredient = search("творог")
    check(by_ingredient.ok and any(r["id"] == recipe["id"] for r in by_ingredient.body["items"]),
          "поиск по ингредиентам", by_ingredient)
    yo = create_recipe(anna, title="Ёжики в томате", published=False)
    found_yo = request("GET", "/api/collections/recipes/records", token=anna.token,
                       query={"filter": 'search ~ "ежики"'})
    check(yo.ok and any(r["id"] == yo.body["id"] for r in found_yo.body.get("items", [])), "«ё» ищется как «е»", found_yo)
    forged = request("PATCH", f"/api/collections/recipes/records/{yo.body['id']}", token=anna.token,
                     json_body={"search": "подделка"})
    check(forged.ok and "подделка" not in forged.body.get("search", ""), "поле поиска нельзя подменить", forged)
    tricky = search('\\"\\\\ сыр')
    check(tricky.ok, "запрос с кавычками и обратной косой чертой не ломает фильтр", tricky)

    # Отзывы и рейтинг.
    review_b = create_review(boris, 4, recipe=recipe["id"], comment="Получилось!", photo=True)
    check(review_b.ok and review_b.body.get("photo"), "Борис оставляет отзыв с фото", review_b)
    rated = get_recipe(recipe["id"]).body
    check(rated["rating_avg"] == 4 and rated["rating_count"] == 1 and abs(rated["score"] - 3.667) < 0.001,
          "рейтинг пересчитан после первого отзыва", rated)
    check(create_review(boris, 5, recipe=recipe["id"]).status == 400, "второй отзыв на тот же рецепт отклонён")
    own_review = create_review(anna, 5, recipe=recipe["id"])
    check(own_review.status == 400 and "собственный" in message_of(own_review), "нельзя оценить свой рецепт", own_review)
    check(create_review(vera, 5, recipe=recipe["id"]).ok, "Вера ставит пять звёзд")
    check(get_recipe(recipe["id"]).body["rating_avg"] == 4.5, "среднее из двух отзывов — 4,5")
    review_path = f"/api/collections/reviews/records/{review_b.body['id']}"
    check(request("PATCH", review_path, token=boris.token, json_body={"rating": 2}).ok, "Борис меняет оценку")
    check(get_recipe(recipe["id"]).body["rating_avg"] == 3.5, "среднее пересчитано после правки — 3,5")
    check(not request("PATCH", review_path, token=boris.token, json_body={"recipe": draft.body["id"]}).ok,
          "отзыв нельзя перенести на другой рецепт")
    check(request("PATCH", review_path, token=vera.token, json_body={"rating": 1}).status == 404,
          "чужой отзыв нельзя изменить")
    check(create_review(boris, 5, recipe=draft.body["id"]).status == 400, "черновик нельзя оценить")
    check(create_review(boris, 5).status == 400, "отзыв без рецепта отклонён")
    check(create_review(boris, 5, recipe=recipe["id"], catalog_id="plov").status == 400,
          "отзыв сразу на два рецепта отклонён")
    check(create_review(boris, 6, catalog_id="plov").status == 400, "оценка больше пяти отклонена")
    check(not request("POST", "/api/collections/reviews/records",
                      json_body={"rating": 5, "catalog_id": "plov"}).ok, "гость не может оставлять отзывы")
    rude_review = create_review(gleb, 1, catalog_id="carbonara", comment="Полная хуйня")
    check(rude_review.status == 400, "грубый отзыв отклонён", rude_review)

    listed = request("GET", "/api/collections/reviews/records",
                     query={"filter": f'recipe = "{recipe["id"]}"', "expand": "author", "sort": "-created"})
    authors = [item.get("expand", {}).get("author", {}) for item in listed.body.get("items", [])]
    check(len(authors) == 2 and {a.get("name") for a in authors} == {"Борис", "Вера"}
          and not any(a.get("email") for a in authors), "в отзывах видно имя автора, но не почту", listed)

    # Отзывы на рецепты из каталога приложения.
    check(create_review(boris, 5, catalog_id="plov", comment="Как в Ташкенте").ok, "отзыв на плов из каталога")
    check(create_review(vera, 3, catalog_id="plov").ok, "второй отзыв на плов")
    plov = catalog_rating("plov")
    check(plov and plov["rating_avg"] == 4 and plov["rating_count"] == 2, "рейтинг плова из каталога — 4", plov)
    check(create_review(boris, 5, catalog_id="Плов!").status == 400, "неверный id рецепта каталога отклонён")
    check(not request("POST", "/api/collections/catalog_ratings/records", token=boris.token,
                      json_body={"catalog_id": "plov", "rating_avg": 5}).ok, "рейтинг каталога нельзя записать вручную")

    # Жалобы: три человека — и рецепт скрыт до решения модератора.
    report = lambda user, **target: request("POST", "/api/collections/reports/records", token=user.token,
                                            json_body={"author": user.id, "reason": "offensive", **target})
    target = create_recipe(anna, title="Спорный рецепт")
    check(report(boris, recipe=target.body["id"]).ok, "Борис жалуется")
    check(not report(boris, recipe=target.body["id"]).ok, "повторная жалоба того же человека не принимается")
    check(report(vera, recipe=target.body["id"]).ok, "Вера жалуется")
    check(get_recipe(target.body["id"]).ok, "после двух жалоб рецепт ещё виден")
    check(report(gleb, recipe=target.body["id"]).ok, "Глеб жалуется")
    check(get_recipe(target.body["id"]).status == 404, "после трёх жалоб рецепт скрыт от всех")
    hidden_own = get_recipe(target.body["id"], token=anna.token)
    check(hidden_own.ok and hidden_own.body["hidden"], "автор видит, что рецепт скрыт", hidden_own)
    check(not report(boris).ok, "жалоба без цели отклонена")
    check(request("GET", "/api/collections/reports/records", token=boris.token).status in (403, 404),
          "жалобы не видны пользователям")

    # Скрытый жалобами отзыв не учитывается в рейтинге.
    vera_review = request("GET", "/api/collections/reviews/records",
                          query={"filter": f'recipe = "{recipe["id"]}" && author = "{vera.id}"'}).body["items"][0]
    dasha = User("Даша")
    for user in (anna, gleb, dasha):
        check(report(user, review=vera_review["id"]).ok, f"жалоба на отзыв от {user.name}")
    after = get_recipe(recipe["id"]).body
    check(after["rating_count"] == 1 and after["rating_avg"] == 2, "скрытый отзыв исключён из рейтинга", after)

    # Удаление аккаунта уносит рецепты и отзывы, рейтинги пересчитываются.
    egor = User("Егор")
    egor_recipe = create_recipe(egor, title="Пирог Егора")
    check(create_review(egor, 1, catalog_id="plov").ok, "Егор оценивает плов")
    check(catalog_rating("plov")["rating_count"] == 3, "у плова три отзыва")
    deleted = request("DELETE", f"/api/collections/users/records/{egor.id}", token=egor.token)
    check(deleted.status == 204, "Егор удаляет аккаунт", deleted)
    check(get_recipe(egor_recipe.body["id"]).status == 404, "рецепт удалённого автора исчез")
    plov = catalog_rating("plov")
    check(plov["rating_count"] == 2 and plov["rating_avg"] == 4, "рейтинг плова пересчитан после удаления", plov)
    check(sign_in(egor.email, PASSWORD).status == 400, "удалённый аккаунт не может войти")
    check(request("DELETE", f"/api/collections/users/records/{anna.id}", token=boris.token).status == 404,
          "чужой аккаунт удалить нельзя")

    renamed_user = request("PATCH", f"/api/collections/users/records/{boris.id}", token=boris.token,
                           json_body={"name": "Мудак"})
    check(renamed_user.status == 400, "грубое имя при изменении профиля отклонено", renamed_user)

    print(f"Проверок пройдено: {passed}, ошибок: {len(failures)}")
    for line in failures:
        print(line)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
