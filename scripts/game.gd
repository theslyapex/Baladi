extends Control

const LEVELS_PATH := "res://data/levels/levels.json"
const SAVE_PATH := "user://baladi_save.cfg"
const BG := Color("#102f2a")
const PANEL := Color("#19443b")
const PANEL_LIGHT := Color("#23574b")
const GOLD := Color("#e8bd68")
const CREAM := Color("#fff3d7")
const MUTED := Color("#b8c9bb")
const RED := Color("#e58b79")
const GREEN := Color("#9bd3a5")

var levels: Array = []
var level_index := 0
var coins := 100
var solved: Array[String] = []
var selected_indices: Array[int] = []
var selected_word := ""
var completed := false
var level_reward_claimed := false

var root_box: VBoxContainer
var header_label: Label
var coin_label: Label
var level_label: Label
var subtitle_label: Label
var board_box: VBoxContainer
var selection_label: Label
var letters_grid: GridContainer
var status_label: Label
var hint_button: Button
var submit_button: Button
var next_button: Button
var letter_buttons: Array[Button] = []

func _ready() -> void:
	_load_levels()
	_load_save()
	_build_interface()
	_render_level()

func _load_levels() -> void:
	if not FileAccess.file_exists(LEVELS_PATH):
		push_error("Level data not found: " + LEVELS_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEVELS_PATH))
	if parsed is Dictionary and parsed.get("levels") is Array:
		levels = parsed["levels"]

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		coins = int(cfg.get_value("player", "coins", 100))
		level_index = clampi(int(cfg.get_value("player", "level_index", 0)), 0, max(0, levels.size() - 1))
		var saved = cfg.get_value("player", "solved", [])
		if saved is Array:
			for word in saved:
				solved.append(str(word))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "level_index", level_index)
	cfg.set_value("player", "solved", solved)
	cfg.save(SAVE_PATH)

func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	root_box = VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 12)
	root_box.add_theme_constant_override("margin_left", 20)
	root_box.add_theme_constant_override("margin_right", 20)
	root_box.add_theme_constant_override("margin_top", 22)
	root_box.add_theme_constant_override("margin_bottom", 18)
	add_child(root_box)

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	root_box.add_child(top)
	var brand := Label.new()
	brand.text = "بلدی؟"
	brand.add_theme_font_size_override("font_size", 30)
	brand.add_theme_color_override("font_color", GOLD)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	coin_label = Label.new()
	coin_label.add_theme_font_size_override("font_size", 19)
	coin_label.add_theme_color_override("font_color", CREAM)
	top.add_child(coin_label)

	var separator := HSeparator.new()
	separator.modulate = GOLD
	root_box.add_child(separator)

	level_label = Label.new()
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 23)
	level_label.add_theme_color_override("font_color", CREAM)
	root_box.add_child(level_label)

	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 14)
	subtitle_label.add_theme_color_override("font_color", MUTED)
	root_box.add_child(subtitle_label)

	var board_panel := _panel()
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_panel.custom_minimum_size.y = 240
	root_box.add_child(board_panel)
	board_box = VBoxContainer.new()
	board_box.add_theme_constant_override("separation", 8)
	board_panel.add_child(board_box)

	var selection_panel := _panel()
	selection_panel.custom_minimum_size.y = 62
	root_box.add_child(selection_panel)
	selection_label = Label.new()
	selection_label.text = "حروف انتخاب‌شده"
	selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selection_label.add_theme_font_size_override("font_size", 25)
	selection_label.add_theme_color_override("font_color", GOLD)
	selection_panel.add_child(selection_label)

	letters_grid = GridContainer.new()
	letters_grid.columns = 5
	letters_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	letters_grid.add_theme_constant_override("h_separation", 9)
	letters_grid.add_theme_constant_override("v_separation", 9)
	root_box.add_child(letters_grid)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", MUTED)
	status_label.text = "حروف را انتخاب کن و واژه بساز."
	root_box.add_child(status_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	root_box.add_child(actions)
	var clear_button := _make_button("پاک‌کردن", PANEL_LIGHT, CREAM)
	clear_button.pressed.connect(_clear_selection)
	actions.add_child(clear_button)
	hint_button = _make_button("راهنما · ۲۰", Color("#80602e"), CREAM)
	hint_button.pressed.connect(_use_hint)
	actions.add_child(hint_button)
	submit_button = _make_button("ثبت واژه", GOLD, BG)
	submit_button.pressed.connect(_submit_word)
	actions.add_child(submit_button)

	next_button = _make_button("مرحله بعد", GREEN, BG)
	next_button.pressed.connect(_next_level)
	root_box.add_child(next_button)

	var footer := Label.new()
	footer.text = "ALISHAMS GAME STUDIO"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", MUTED)
	root_box.add_child(footer)

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color("#547c66")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_button(text_value: String, color: Color, text_color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.12)
	button.add_theme_stylebox_override("pressed", pressed)
	return button

func _render_level() -> void:
	if levels.is_empty():
		status_label.text = "داده مراحل بارگذاری نشد."
		return
	level_index = clampi(level_index, 0, levels.size() - 1)
	var data: Dictionary = levels[level_index]
	level_label.text = "مرحله %d" % int(data["id"])
	subtitle_label.text = str(data.get("title", ""))
	coin_label.text = "◆ %d" % coins
	completed = _is_level_complete()
	level_reward_claimed = completed
	_render_board()
	_render_letters()
	_update_controls()
	if completed:
		status_label.text = "آفرین! این مرحله را کامل کردی."
	else:
		status_label.text = "حروف را انتخاب کن و واژه بساز."
	_save()

func _render_board() -> void:
	for child in board_box.get_children():
		child.queue_free()
	var answers: Array = levels[level_index]["answers"]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	board_box.add_child(row)
	for i in range(answers.size()):
		var word := str(answers[i])
		var tile := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#315e4d") if solved.has(word) else Color("#12372f")
		style.border_color = GOLD if solved.has(word) else Color("#537766")
		style.set_border_width_all(1)
		style.set_corner_radius_all(10)
		style.content_margin_left = 9
		style.content_margin_right = 9
		style.content_margin_top = 9
		style.content_margin_bottom = 9
		tile.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = word if solved.has(word) else "·".repeat(word.length())
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", CREAM if solved.has(word) else MUTED)
		tile.add_child(label)
		row.add_child(tile)

func _render_letters() -> void:
	for child in letters_grid.get_children():
		child.queue_free()
	letter_buttons.clear()
	selected_indices.clear()
	selected_word = ""
	_update_selection_label()
	var letters: Array = levels[level_index]["letters"]
	letters_grid.columns = mini(5, letters.size())
	for i in range(letters.size()):
		var button := _make_button(str(letters[i]), PANEL_LIGHT, CREAM)
		button.custom_minimum_size = Vector2(0, 62)
		button.add_theme_font_size_override("font_size", 27)
		button.pressed.connect(_on_letter_pressed.bind(i))
		letters_grid.add_child(button)
		letter_buttons.append(button)

func _on_letter_pressed(index: int) -> void:
	if completed or selected_indices.has(index):
		return
	var letters: Array = levels[level_index]["letters"]
	selected_indices.append(index)
	selected_word += str(letters[index])
	letter_buttons[index].disabled = true
	letter_buttons[index].modulate = Color("#82958a")
	_update_selection_label()
	_update_controls()

func _update_selection_label() -> void:
	selection_label.text = selected_word if not selected_word.is_empty() else "حروف انتخاب‌شده"

func _clear_selection() -> void:
	for index in selected_indices:
		if index < letter_buttons.size():
			letter_buttons[index].disabled = false
			letter_buttons[index].modulate = Color.WHITE
	selected_indices.clear()
	selected_word = ""
	_update_selection_label()
	_update_controls()

func _normalize_word(value: String) -> String:
	var result := value.strip_edges().replace("ي", "ی").replace("ك", "ک")
	result = result.replace("‌", "").replace("ـ", "")
	return result

func _submit_word() -> void:
	if selected_word.is_empty() or completed:
		return
	var candidate := _normalize_word(selected_word)
	var answers: Array = levels[level_index]["answers"]
	var matched := ""
	for answer in answers:
		if _normalize_word(str(answer)) == candidate:
			matched = str(answer)
			break
	if matched.is_empty():
		status_label.text = "این واژه در جدول این مرحله نیست. دوباره امتحان کن."
		status_label.add_theme_color_override("font_color", RED)
	elif solved.has(matched):
		status_label.text = "این واژه را قبلاً پیدا کرده‌ای."
	else:
		solved.append(matched)
		status_label.text = "درست بود! یک واژه دیگر پیدا کن."
		status_label.add_theme_color_override("font_color", GREEN)
		coins += 3
		if _is_level_complete():
			completed = true
			coins += int(levels[level_index].get("reward", 25))
			status_label.text = "مرحله کامل شد! پاداش سکه به حسابت اضافه شد."
		_render_board()
		_save()
	_update_controls()
	_clear_selection()

func _is_level_complete() -> bool:
	if levels.is_empty():
		return false
	for answer in levels[level_index]["answers"]:
		if not solved.has(str(answer)):
			return false
	return true

func _use_hint() -> void:
	if completed:
		return
	if coins < 20:
		status_label.text = "سکه کافی نداری. با حل واژه‌ها سکه جمع کن."
		status_label.add_theme_color_override("font_color", RED)
		return
	var target := ""
	for answer in levels[level_index]["answers"]:
		if not solved.has(str(answer)):
			target = str(answer)
			break
	if target.is_empty():
		return
	coins -= 20
	solved.append(target)
	status_label.text = "راهنما یک واژه را آشکار کرد: " + target
	status_label.add_theme_color_override("font_color", GOLD)
	if _is_level_complete():
		completed = true
		coins += int(levels[level_index].get("reward", 25))
		status_label.text += "  مرحله کامل شد!"
	_render_board()
	_update_controls()
	_save()

func _update_controls() -> void:
	coin_label.text = "◆ %d" % coins
	hint_button.disabled = completed or coins < 20
	submit_button.disabled = completed or selected_word.is_empty()
	next_button.visible = completed
	next_button.disabled = level_index >= levels.size() - 1

func _next_level() -> void:
	if not completed or level_index >= levels.size() - 1:
		return
	level_index += 1
	solved.clear()
	_render_level()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
