# Сервер сообщества Deshielo

Схема базы, права доступа и серверная логика для [PocketBase](https://pocketbase.io) 0.40.

- `pb_migrations/` — коллекции `recipes`, `reviews`, `catalog_ratings`, `reports` и настройки пользователей; применяются автоматически при запуске.
- `pb_hooks/` — проверка рецептов, фильтр грубых слов, пересчёт рейтингов, автоскрытие по жалобам.
- `tests/run.sh` — интеграционные тесты API на чистом сервере, `tests/seed.py` — демо-данные.

Быстрый старт:

```bash
./pocketbase serve --migrationsDir server/pb_migrations --hooksDir server/pb_hooks
python3 server/tests/seed.py
```

Подробно — запуск на своём Mac, сервер в интернете, модерация и требования App Store — в [docs/COMMUNITY.md](../docs/COMMUNITY.md).
