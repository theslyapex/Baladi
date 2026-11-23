extends SceneTree

const LEVELS_PATH := "res://data/levels/levels.json"
const DICTIONARY_PATH := "res://data/dictionary/bonus_words.json"

func _initialize() -> void:
	var levels_data = JSON.parse_string(FileAccess.get_file_as_string(LEVELS_PATH))
	var dictionary_data = JSON.parse_string(FileAccess.get_file_as_string(DICTIONARY_PATH))
	if not (levels_data is Dictionary) or not (dictionary_data is Dictionary):
		push_error("Level or dictionary JSON could not be parsed.")
		quit(1)
		return
	var dictionary := {}
	for value in dictionary_data.get("words", []):
		dictionary[_normalize(str(value))] = true
	var errors: Array[String] = []
	var checked_answers := 0
	for level_value in levels_data.get("levels", []):
		var level: Dictionary = level_value
		var level_id := int(level.get("id", 0))
		var letters: Array = level.get("letters", [])
		var seen := {}
		for answer_value in level.get("answers", []):
			var answer := _normalize(str(answer_value))
			checked_answers += 1
			if seen.has(answer):
				errors.append("Stage %d repeats answer: %s" % [level_id, answer])
			seen[answer] = true
			if not dictionary.has(answer):
				errors.append("Stage %d answer is missing from the Persian dictionary: %s" % [level_id, answer])
			if not _can_form(answer, letters):
				errors.append("Stage %d answer cannot be formed from its letters: %s" % [level_id, answer])
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(1)
		return
	print("Baladi vocabulary validation passed: %d stages, %d answers, %d dictionary entries." % [
		levels_data.get("levels", []).size(), checked_answers, dictionary.size()
	])
	quit(0)

func _normalize(value: String) -> String:
	return value.strip_edges().replace("ي", "ی").replace("ك", "ک").replace("‌", "").replace("ـ", "")

func _can_form(word: String, letters: Array) -> bool:
	var available := {}
	for value in letters:
		var letter := _normalize(str(value))
		available[letter] = int(available.get(letter, 0)) + 1
	for index in range(word.length()):
		var character := word.substr(index, 1)
		if int(available.get(character, 0)) <= 0:
			return false
		available[character] = int(available[character]) - 1
	return true
