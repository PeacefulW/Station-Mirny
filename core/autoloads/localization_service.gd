class_name LocalizationServiceSingleton
extends Node

## Сервис локализации. Тонкая обёртка над tr().
## Добавляет именованные аргументы {name} и fallback-предупреждения.
##
## Использование:
##   Localization.t("CRAFT_SUCCESS", {"item": "Слиток", "amount": 5})
##   → "Скрафчено: Слиток x5"

## Проверить, существует ли ключ локализации.
func has(key: String) -> bool:
	return tr(key) != key

## Перевести ключ с опциональными именованными аргументами.
func t(key: String, args: Dictionary = {}) -> String:
	var text: String = tr(key)
	if text == key:
		push_warning(key)
	for arg_key: String in args:
		text = text.replace("{%s}" % arg_key, str(args[arg_key]))
	return text

## Перевести ключ из data-ресурса (ItemData, BuildingData и т.д.).
## Если ключ пустой или не найден — возвращает fallback.
func td(key: String, fallback: String = "") -> String:
	if key.is_empty():
		return fallback
	var text: String = tr(key)
	if text == key and not fallback.is_empty():
		return fallback
	return text
