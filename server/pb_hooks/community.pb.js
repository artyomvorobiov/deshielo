/// <reference path="../pb_data/types.d.ts" />

// Хуки сообщества Deshielo. Логика вынесена в lib/community.js.

// Состав и шаги рецепта, фильтр грубых слов.
onRecordCreateRequest((e) => {
  const community = require(`${__hooks}/lib/community.js`);
  community.validateRecipeContent(e.record);
  community.checkPublicTexts(e.record);
  e.next();
}, "recipes");

onRecordUpdateRequest((e) => {
  const community = require(`${__hooks}/lib/community.js`);
  community.validateRecipeContent(e.record);
  community.checkPublicTexts(e.record);
  e.next();
}, "recipes");

// Поисковый текст обновляется при любом сохранении. Новый рецепт без отзывов
// получает нейтральную оценку для сортировки «Лучшие».
onRecordCreate((e) => {
  const community = require(`${__hooks}/lib/community.js`);
  e.record.set("search", community.searchText(e.record));
  if (!e.record.getFloat("score")) {
    e.record.set("score", community.PRIOR_MEAN);
  }
  e.next();
}, "recipes");

onRecordUpdate((e) => {
  e.record.set("search", require(`${__hooks}/lib/community.js`).searchText(e.record));
  e.next();
}, "recipes");

onRecordCreateRequest((e) => {
  const community = require(`${__hooks}/lib/community.js`);
  community.validateReviewTarget(e.app, e.record, e.auth);
  community.checkPublicTexts(e.record);
  e.next();
}, "reviews");

onRecordUpdateRequest((e) => {
  const community = require(`${__hooks}/lib/community.js`);
  community.checkPublicTexts(e.record);
  e.next();
}, "reviews");

onRecordCreateRequest((e) => {
  require(`${__hooks}/lib/community.js`).checkPublicTexts(e.record);
  e.next();
}, "users");

onRecordUpdateRequest((e) => {
  require(`${__hooks}/lib/community.js`).checkPublicTexts(e.record);
  e.next();
}, "users");

// Средний рейтинг пересчитывается после любого изменения отзыва — в том числе из панели администратора.
onRecordAfterCreateSuccess((e) => {
  require(`${__hooks}/lib/community.js`).refreshRating(e.app, e.record);
  e.next();
}, "reviews");

onRecordAfterUpdateSuccess((e) => {
  require(`${__hooks}/lib/community.js`).refreshRating(e.app, e.record);
  e.next();
}, "reviews");

onRecordAfterDeleteSuccess((e) => {
  require(`${__hooks}/lib/community.js`).refreshRating(e.app, e.record);
  e.next();
}, "reviews");

onRecordCreateRequest((e) => {
  require(`${__hooks}/lib/community.js`).validateReportTarget(e.record);
  e.next();
}, "reports");

onRecordAfterCreateSuccess((e) => {
  require(`${__hooks}/lib/community.js`).applyReports(e.app, e.record);
  e.next();
}, "reports");
