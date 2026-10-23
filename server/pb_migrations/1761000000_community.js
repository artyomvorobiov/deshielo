/// <reference path="../pb_data/types.d.ts" />

// Схема сообщества Deshielo: авторы, рецепты, отзывы с фото, рейтинги рецептов из каталога и жалобы.
// Права доступа описаны правилами коллекций, остальная логика — в pb_hooks/community.pb.js.

const CATEGORIES = ["soup", "main", "side", "salad", "dessert", "baking", "breakfast", "drink", "snack"];
const IMAGE_TYPES = ["image/jpeg", "image/png", "image/heic", "image/webp"];
const MAX_IMAGE_SIZE = 10 * 1024 * 1024;
const THUMBS = ["600x0", "200x200"];

function timestamps() {
  return [
    { name: "created", type: "autodate", onCreate: true },
    { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
  ];
}

migrate((app) => {
  // Пользователи: имя видно всем (для подписи под рецептом), почта — только владельцу.
  const users = app.findCollectionByNameOrId("users");
  users.viewRule = "";
  const name = users.fields.getByName("name");
  name.required = true;
  name.min = 2;
  name.max = 40;
  users.fields.add(new BoolField({ name: "accepted_terms", required: true }));
  users.authToken.duration = 30 * 24 * 60 * 60;
  app.save(users);

  const recipes = new Collection({
    type: "base",
    name: "recipes",
    // Опубликованные и не скрытые модератором рецепты видны всем, черновики — только автору.
    listRule: "(published = true && hidden = false) || author = @request.auth.id",
    viewRule: "(published = true && hidden = false) || author = @request.auth.id",
    createRule: [
      '@request.auth.id != ""',
      "@request.body.author = @request.auth.id",
      "@request.body.hidden:isset = false",
      "@request.body.rating_avg:isset = false",
      "@request.body.rating_count:isset = false",
      "@request.body.score:isset = false",
    ].join(" && "),
    updateRule: [
      "author = @request.auth.id",
      "@request.body.author:isset = false",
      "@request.body.hidden:isset = false",
      "@request.body.rating_avg:isset = false",
      "@request.body.rating_count:isset = false",
      "@request.body.score:isset = false",
    ].join(" && "),
    deleteRule: "author = @request.auth.id",
    fields: [
      { name: "author", type: "relation", required: true, collectionId: users.id, cascadeDelete: true, maxSelect: 1 },
      { name: "title", type: "text", required: true, min: 3, max: 120, presentable: true },
      { name: "summary", type: "text", max: 500 },
      { name: "story", type: "text", max: 3000 },
      { name: "category", type: "select", required: true, maxSelect: 1, values: CATEGORIES },
      { name: "country", type: "text", max: 2, pattern: "^[A-Z]{2}$" },
      { name: "difficulty", type: "number", required: true, onlyInt: true, min: 1, max: 3 },
      { name: "prep_minutes", type: "number", onlyInt: true, min: 0, max: 1440 },
      { name: "cook_minutes", type: "number", onlyInt: true, min: 0, max: 2880 },
      { name: "servings", type: "number", required: true, onlyInt: true, min: 1, max: 50 },
      { name: "ingredients", type: "json", required: true, maxSize: 20000 },
      { name: "steps", type: "json", required: true, maxSize: 60000 },
      { name: "photos", type: "file", maxSelect: 6, maxSize: MAX_IMAGE_SIZE, mimeTypes: IMAGE_TYPES, thumbs: THUMBS },
      { name: "published", type: "bool" },
      { name: "hidden", type: "bool" },
      // Текст для поиска в нижнем регистре: LIKE в SQLite не различает регистр только у латиницы.
      // Заполняется хуком при каждом сохранении.
      { name: "search", type: "text", max: 10000 },
      { name: "rating_avg", type: "number" },
      { name: "rating_count", type: "number", onlyInt: true },
      // Байесовская оценка для сортировки «Лучшие»: один отзыв на пять звёзд не обгоняет сотню четвёрок с плюсом.
      { name: "score", type: "number" },
      ...timestamps(),
    ],
    indexes: [
      "CREATE INDEX idx_recipes_author ON recipes (author)",
      "CREATE INDEX idx_recipes_created ON recipes (created)",
      "CREATE INDEX idx_recipes_score ON recipes (score)",
    ],
  });
  app.save(recipes);

  const reviews = new Collection({
    type: "base",
    name: "reviews",
    listRule: "hidden = false || author = @request.auth.id",
    viewRule: "hidden = false || author = @request.auth.id",
    createRule: [
      '@request.auth.id != ""',
      "@request.body.author = @request.auth.id",
      "@request.body.hidden:isset = false",
    ].join(" && "),
    // Отзыв можно исправить, но не перенести на другой рецепт.
    updateRule: [
      "author = @request.auth.id",
      "@request.body.author:isset = false",
      "@request.body.hidden:isset = false",
      "@request.body.recipe:isset = false",
      "@request.body.catalog_id:isset = false",
    ].join(" && "),
    deleteRule: "author = @request.auth.id",
    fields: [
      { name: "author", type: "relation", required: true, collectionId: users.id, cascadeDelete: true, maxSelect: 1 },
      // Отзыв относится либо к рецепту сообщества, либо к рецепту из каталога приложения.
      { name: "recipe", type: "relation", collectionId: recipes.id, cascadeDelete: true, maxSelect: 1 },
      { name: "catalog_id", type: "text", max: 80, pattern: "^[a-z0-9]+(-[a-z0-9]+)*$" },
      { name: "rating", type: "number", required: true, onlyInt: true, min: 1, max: 5 },
      { name: "comment", type: "text", max: 2000 },
      { name: "photo", type: "file", maxSelect: 1, maxSize: MAX_IMAGE_SIZE, mimeTypes: IMAGE_TYPES, thumbs: THUMBS },
      { name: "hidden", type: "bool" },
      ...timestamps(),
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_reviews_once ON reviews (author, recipe, catalog_id)",
      "CREATE INDEX idx_reviews_recipe ON reviews (recipe)",
      "CREATE INDEX idx_reviews_catalog ON reviews (catalog_id)",
    ],
  });
  app.save(reviews);

  // Рейтинги рецептов из каталога приложения. Пишет их только сервер (хуки), читать может кто угодно.
  const catalogRatings = new Collection({
    type: "base",
    name: "catalog_ratings",
    listRule: "",
    viewRule: "",
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "catalog_id", type: "text", required: true, max: 80 },
      { name: "rating_avg", type: "number" },
      { name: "rating_count", type: "number", onlyInt: true },
      ...timestamps(),
    ],
    indexes: ["CREATE UNIQUE INDEX idx_catalog_ratings_id ON catalog_ratings (catalog_id)"],
  });
  app.save(catalogRatings);

  // Жалобы видит только администратор в панели PocketBase.
  const reports = new Collection({
    type: "base",
    name: "reports",
    listRule: null,
    viewRule: null,
    createRule: '@request.auth.id != "" && @request.body.author = @request.auth.id',
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "author", type: "relation", required: true, collectionId: users.id, cascadeDelete: true, maxSelect: 1 },
      { name: "recipe", type: "relation", collectionId: recipes.id, cascadeDelete: true, maxSelect: 1 },
      { name: "review", type: "relation", collectionId: reviews.id, cascadeDelete: true, maxSelect: 1 },
      { name: "reason", type: "select", required: true, maxSelect: 1, values: ["spam", "offensive", "wrong", "other"] },
      { name: "comment", type: "text", max: 1000 },
      ...timestamps(),
    ],
    indexes: ["CREATE UNIQUE INDEX idx_reports_once ON reports (author, recipe, review)"],
  });
  app.save(reports);

  const settings = app.settings();
  settings.meta.appName = "Deshielo";
  settings.rateLimits.enabled = true;
  settings.rateLimits.rules = [
    { label: "*:auth", maxRequests: 5, duration: 10 },
    { label: "users:create", maxRequests: 10, duration: 600 },
    { label: "reports:create", maxRequests: 20, duration: 3600 },
    { label: "*:create", maxRequests: 20, duration: 5 },
    { label: "/api/batch", maxRequests: 3, duration: 1 },
    { label: "/api/", maxRequests: 300, duration: 10 },
  ];
  app.save(settings);
}, (app) => {
  for (const name of ["reports", "catalog_ratings", "reviews", "recipes"]) {
    app.delete(app.findCollectionByNameOrId(name));
  }
  const users = app.findCollectionByNameOrId("users");
  users.viewRule = "id = @request.auth.id";
  users.fields.removeByName("accepted_terms");
  const name = users.fields.getByName("name");
  name.required = false;
  name.min = 0;
  name.max = 255;
  app.save(users);
});
