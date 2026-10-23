// Общая логика хуков сообщества. Подключается внутри каждого обработчика через require():
// обработчики PocketBase выполняются изолированно и не видят переменных файла хуков.

// Рецепт с 3 жалобами от разных людей скрывается до решения модератора.
const HIDE_AFTER_REPORTS = 3;

// Байесовская оценка: среднее «подтягивается» к 3,5, пока отзывов мало.
const PRIOR_MEAN = 3.5;
const PRIOR_WEIGHT = 2;

const UNITS = ["g", "kg", "ml", "l", "pcs", "tbsp", "tsp", "pinch", "clove", "bunch",
  "sprig", "slice", "leaf", "stalk", "head", "toTaste"];

// Корни нецензурных слов. Границы слов проверяются вручную: \b в JavaScript не понимает кириллицу.
const RUSSIAN_PATTERNS = [
  /(^|[^а-я])(на|по|за|от|вы|у|о|раз|до|об|про|при|ни|не)?ху[йеяию]/,
  /пизд/,
  // Приставка «с» только с твёрдым знаком: иначе под шаблон попадает «себе».
  /(^|[^а-я])(вы|за|на|от|до|по|про|раз|у|из|об|под|съ|объ|подъ|разъ|отъ|изъ|въ)?еб[аеиулнтшы]/,
  /(^|[^а-я])бля($|[^а-ях])/,
  /(^|[^а-я])бля[дт]/,
  /(^|[^а-я])су(ка|ки|ке|ку|кой|чк[аеиу])($|[^а-я])/,
  /(^|[^а-я])муда[кч]/,
  /(^|[^а-я])мудил/,
  /(^|[^а-я])пид[оа]р/,
  /(^|[^а-я])гандон/,
  /(^|[^а-я])шлюх/,
  /(^|[^а-я])залуп/,
  /долбо[её]б/,
];
const LATIN_PATTERNS = [
  /(^|[^a-z])(fuck|cunt|bitch|nigg|faggot)/,
  /(^|[^a-z])shit($|[^a-z])/,
];
// Латинские буквы, похожие на русские: «xуй» с латинской x тоже должен ловиться.
const LOOKALIKES = { a: "а", e: "е", o: "о", p: "р", c: "с", x: "х", y: "у", k: "к", m: "м", t: "т", b: "в", h: "н" };

function containsBannedWord(text) {
  if (!text) {
    return false;
  }
  const lower = String(text).toLowerCase().replace(/ё/g, "е");
  if (LATIN_PATTERNS.some((pattern) => pattern.test(lower))) {
    return true;
  }
  const cyrillic = lower.replace(/[aeopcxykmtbh]/g, (ch) => LOOKALIKES[ch]);
  return RUSSIAN_PATTERNS.some((pattern) => pattern.test(lower) || pattern.test(cyrillic));
}

function parseJSONField(record, name) {
  const raw = record.getString(name);
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch (_) {
    throw new BadRequestError("Не удалось прочитать поле «" + name + "».");
  }
}

function isText(value, min, max) {
  return typeof value === "string" && value.trim().length >= min && value.length <= max;
}

function isOptionalText(value, max) {
  return value === undefined || value === null || (typeof value === "string" && value.length <= max);
}

// Проверяет состав и шаги рецепта: приложение показывает их без дополнительных проверок.
function validateRecipeContent(record) {
  const ingredients = parseJSONField(record, "ingredients");
  if (!Array.isArray(ingredients) || ingredients.length < 1 || ingredients.length > 60) {
    throw new BadRequestError("В рецепте должно быть от 1 до 60 ингредиентов.");
  }
  ingredients.forEach((item, index) => {
    const where = "Ингредиент " + (index + 1);
    if (!item || typeof item !== "object" || !isText(item.name, 1, 120)) {
      throw new BadRequestError(where + ": нужно название до 120 символов.");
    }
    if (item.amount !== undefined && item.amount !== null &&
        (typeof item.amount !== "number" || !(item.amount > 0) || item.amount > 100000)) {
      throw new BadRequestError(where + ": количество должно быть положительным числом.");
    }
    if (item.unit !== undefined && item.unit !== null && UNITS.indexOf(item.unit) < 0) {
      throw new BadRequestError(where + ": неизвестная единица измерения.");
    }
    if (!isOptionalText(item.note, 120) || !isOptionalText(item.group, 60)) {
      throw new BadRequestError(where + ": слишком длинная заметка или группа.");
    }
  });

  const steps = parseJSONField(record, "steps");
  if (!Array.isArray(steps) || steps.length < 1 || steps.length > 40) {
    throw new BadRequestError("В рецепте должно быть от 1 до 40 шагов.");
  }
  steps.forEach((step, index) => {
    const where = "Шаг " + (index + 1);
    if (!step || typeof step !== "object" || !isText(step.text, 3, 1500)) {
      throw new BadRequestError(where + ": нужен текст от 3 до 1500 символов.");
    }
    if (!isOptionalText(step.title, 80)) {
      throw new BadRequestError(where + ": заголовок длиннее 80 символов.");
    }
    if (step.timer !== undefined && step.timer !== null &&
        (typeof step.timer !== "number" || step.timer % 1 !== 0 || step.timer < 1 || step.timer > 600)) {
      throw new BadRequestError(where + ": таймер — целое число минут от 1 до 600.");
    }
  });
  return { ingredients, steps };
}

// Публичные тексты записи, которые проходят через фильтр слов.
function publicTexts(record) {
  switch (record.collection().name) {
    case "users":
      return [record.getString("name")];
    case "reviews":
      return [record.getString("comment")];
    case "recipes": {
      const texts = [record.getString("title"), record.getString("summary"), record.getString("story")];
      for (const name of ["ingredients", "steps"]) {
        const items = parseJSONField(record, name);
        if (Array.isArray(items)) {
          items.forEach((item) => {
            if (item && typeof item === "object") {
              texts.push(item.name, item.note, item.group, item.title, item.text);
            }
          });
        }
      }
      return texts;
    }
    default:
      return [];
  }
}

// Название, описание и продукты одной строкой в нижнем регистре, «ё» заменена на «е».
function searchText(record) {
  const parts = [record.getString("title"), record.getString("summary")];
  let ingredients = null;
  try {
    ingredients = JSON.parse(record.getString("ingredients") || "null");
  } catch (_) {
    ingredients = null;
  }
  if (Array.isArray(ingredients)) {
    ingredients.forEach((item) => {
      if (item && typeof item.name === "string") {
        parts.push(item.name);
      }
    });
  }
  return parts.join(" ").toLowerCase().replace(/ё/g, "е").slice(0, 10000);
}

function checkPublicTexts(record) {
  if (publicTexts(record).some(containsBannedWord)) {
    throw new BadRequestError("Текст нарушает правила сообщества. Уберите грубые слова и попробуйте снова.");
  }
}

// Отзыв относится ровно к одному рецепту: из сообщества или из каталога приложения.
function validateReviewTarget(app, review, auth) {
  const recipeId = review.getString("recipe");
  const catalogId = review.getString("catalog_id");
  if (!recipeId === !catalogId) {
    throw new BadRequestError("Отзыв должен относиться к одному рецепту.");
  }
  if (!recipeId) {
    return;
  }
  let recipe;
  try {
    recipe = app.findRecordById("recipes", recipeId);
  } catch (_) {
    throw new BadRequestError("Рецепт не найден.");
  }
  if (!recipe.getBool("published") || recipe.getBool("hidden")) {
    throw new BadRequestError("Рецепт недоступен для отзывов.");
  }
  if (auth && recipe.getString("author") === auth.id) {
    throw new BadRequestError("Нельзя оценивать собственный рецепт.");
  }
}

function validateReportTarget(report) {
  if (!report.getString("recipe") === !report.getString("review")) {
    throw new BadRequestError("Жалоба должна относиться к одному рецепту или отзыву.");
  }
}

function ratingStats(app, field, id) {
  const stats = new DynamicModel({ avg: -0, cnt: 0 });
  app.db()
    .newQuery("SELECT COALESCE(AVG(rating), 0) AS avg, COUNT(*) AS cnt FROM reviews WHERE " + field +
      " = {:id} AND hidden = FALSE")
    .bind({ id: id })
    .one(stats);
  return { avg: Math.round(stats.avg * 10) / 10, count: stats.cnt, rawAvg: stats.avg };
}

function bayesianScore(avg, count) {
  return Math.round(((PRIOR_MEAN * PRIOR_WEIGHT + avg * count) / (PRIOR_WEIGHT + count)) * 1000) / 1000;
}

// Пересчитывает средний рейтинг рецепта, к которому относится отзыв.
function refreshRating(app, review) {
  const recipeId = review.getString("recipe");
  const catalogId = review.getString("catalog_id");
  if (recipeId) {
    let recipe;
    try {
      recipe = app.findRecordById("recipes", recipeId);
    } catch (_) {
      return; // рецепт удалён вместе с отзывами
    }
    const stats = ratingStats(app, "recipe", recipeId);
    recipe.set("rating_avg", stats.avg);
    recipe.set("rating_count", stats.count);
    recipe.set("score", bayesianScore(stats.rawAvg, stats.count));
    app.save(recipe);
  } else if (catalogId) {
    const stats = ratingStats(app, "catalog_id", catalogId);
    let rating;
    try {
      rating = app.findFirstRecordByData("catalog_ratings", "catalog_id", catalogId);
    } catch (_) {
      if (stats.count === 0) {
        return;
      }
      rating = new Record(app.findCollectionByNameOrId("catalog_ratings"));
      rating.set("catalog_id", catalogId);
    }
    rating.set("rating_avg", stats.avg);
    rating.set("rating_count", stats.count);
    app.save(rating);
  }
}

// Скрывает рецепт или отзыв, на который пожаловались несколько разных людей.
function applyReports(app, report) {
  const recipeId = report.getString("recipe");
  const field = recipeId ? "recipe" : "review";
  const id = recipeId || report.getString("review");
  const stats = new DynamicModel({ cnt: 0 });
  app.db()
    .newQuery("SELECT COUNT(DISTINCT author) AS cnt FROM reports WHERE " + field + " = {:id}")
    .bind({ id: id })
    .one(stats);
  if (stats.cnt < HIDE_AFTER_REPORTS) {
    return;
  }
  const target = app.findRecordById(recipeId ? "recipes" : "reviews", id);
  if (!target.getBool("hidden")) {
    target.set("hidden", true);
    app.save(target);
  }
}

module.exports = {
  PRIOR_MEAN,
  containsBannedWord,
  validateRecipeContent,
  searchText,
  checkPublicTexts,
  validateReviewTarget,
  validateReportTarget,
  refreshRating,
  applyReports,
};
