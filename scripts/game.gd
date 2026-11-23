extends Control

const LEVELS_PATH := "res://data/levels/levels.json"
const BONUS_DICTIONARY_PATH := "res://data/dictionary/bonus_words.json"
const SAVE_PATH_PREFIX := "user://baladi_save_"
const BG := Color("#0b211f")
const PANEL := Color("#153a34")
const PANEL_ALT := Color("#1d4b41")
const GOLD := Color("#edc879")
const CREAM := Color("#fff4df")
const MUTED := Color("#a9c3b8")
const GREEN := Color("#8ed6a5")
const RED := Color("#f08c80")
const TEAL := Color("#55c6b5")

var levels: Array = []
var level_index := 0
var cloud_current_level := 1
var coins := 100
var level_solved: Dictionary = {}
var completed_levels: Array = []
var bonus_word_set: Dictionary = {}
var level_bonus_found: Dictionary = {}
var guest_mode := false
var sfx_player: AudioStreamPlayer
var selected_indices: Array[int] = []
var selected_word := ""
var is_dragging := false
var active_pointer := -1

var page_box: VBoxContainer
var content_box: VBoxContainer
var coin_label: Label
var level_label: Label
var subtitle_label: Label
var board_box: GridContainer
var selection_label: Label
var letters_grid: GridContainer
var status_label: Label
var hint_button: Button
var submit_button: Button
var letter_buttons: Array[Button] = []
var trace_line: Line2D
var auth_email_input: LineEdit
var auth_password_input: LineEdit
var auth_name_input: LineEdit
var auth_status_label: Label
var session_timer: Timer

func _ready() -> void:
	_load_levels()
	_load_bonus_dictionary()
	_build_base()
	_init_audio()
	var restored: bool = await CloudAccount.restore_session()
	if restored:
		await _enter_game()
	else:
		_show_auth()

func _load_bonus_dictionary() -> void:
	if not FileAccess.file_exists(BONUS_DICTIONARY_PATH):
		push_warning("Persian bonus dictionary not found.")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BONUS_DICTIONARY_PATH))
	if parsed is Dictionary:
		for word in parsed.get("words", []):
			bonus_word_set[str(word)] = true

func _save_path() -> String:
	var account_id := str(CloudAccount.user_id)
	if account_id.is_empty():
		return "user://baladi_save_guest.cfg"
	return SAVE_PATH_PREFIX + account_id + ".cfg"

func _enter_game() -> void:
	guest_mode = false
	var response: Dictionary = await CloudAccount.start_game_session()
	if not response.get("ok", false):
		_show_auth(str(response.get("error", "ورود به بازی انجام نشد.")))
		return
	var profile: Dictionary = response.get("profile", {})
	_load_save()
	coins = int(profile.get("coins", 100))
	cloud_current_level = int(profile.get("current_level", 1))
	level_index = clampi(cloud_current_level - 1, 0, max(0, levels.size() - 1))
	var remote_completed = profile.get("completed_levels", [])
	if remote_completed is Array:
		completed_levels = remote_completed.duplicate()
	var found_words = response.get("found_words", [])
	if found_words is Array:
		var active_key := str(int(profile.get("current_level", 1)))
		level_solved[active_key] = found_words.duplicate()
	var found_bonus_words = response.get("found_bonus_words", [])
	if found_bonus_words is Array:
		var active_bonus_key := str(int(profile.get("current_level", 1)))
		level_bonus_found[active_bonus_key] = found_bonus_words.duplicate()
	_save()
	if session_timer == null:
		session_timer = Timer.new()
		session_timer.wait_time = 45.0
		session_timer.timeout.connect(_heartbeat)
		add_child(session_timer)
	session_timer.start()
	_show_map()

func _enter_guest() -> void:
	guest_mode = true
	_load_save()
	cloud_current_level = clampi(cloud_current_level, 1, levels.size() + 1)
	level_index = clampi(cloud_current_level - 1, 0, max(0, levels.size() - 1))
	if session_timer != null:
		session_timer.stop()
	_show_map()
	_set_status("حالت مهمان فعال است؛ پیشرفت فقط روی همین دستگاه می‌ماند.", GOLD)

func _heartbeat() -> void:
	if not guest_mode and CloudAccount.is_authenticated():
		await CloudAccount.touch_session()

func _logout() -> void:
	_save()
	if session_timer != null:
		session_timer.stop()
	if guest_mode:
		guest_mode = false
		_show_auth("از حالت مهمان خارج شدی.")
		return
	await CloudAccount.sign_out()
	_show_auth("از حساب کاربری خارج شدی.")

func _load_levels() -> void:
	if not FileAccess.file_exists(LEVELS_PATH):
		push_error("Level data not found: " + LEVELS_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEVELS_PATH))
	if parsed is Dictionary and parsed.get("levels") is Array:
		levels = parsed["levels"]
	if levels.is_empty():
		push_error("No valid levels found.")

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path()) != OK:
		return
	coins = int(cfg.get_value("player", "coins", 100))
	level_index = clampi(int(cfg.get_value("player", "level_index", 0)), 0, max(0, levels.size() - 1))
	cloud_current_level = int(cfg.get_value("player", "current_level", level_index + 1))
	var saved_levels = cfg.get_value("player", "level_solved", {})
	if saved_levels is Dictionary:
		level_solved = saved_levels
	var saved_completed = cfg.get_value("player", "completed_levels", [])
	if saved_completed is Array:
		completed_levels = saved_completed
	var saved_bonus = cfg.get_value("player", "level_bonus_found", {})
	if saved_bonus is Dictionary:
		level_bonus_found = saved_bonus
	# Migrate saves from the first prototype.
	if level_solved.is_empty():
		var legacy = cfg.get_value("player", "solved", [])
		if legacy is Array and not legacy.is_empty() and not levels.is_empty():
			level_solved[str(levels[level_index].get("id", level_index + 1))] = legacy

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "level_index", level_index)
	cfg.set_value("player", "level_solved", level_solved)
	cfg.set_value("player", "completed_levels", completed_levels)
	cfg.set_value("player", "current_level", cloud_current_level)
	cfg.set_value("player", "level_bonus_found", level_bonus_found)
	cfg.save(_save_path())

func _build_base() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	page_box = VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 14)
	margin.add_child(page_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	page_box.add_child(header)

	var brand_box := VBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_box.add_theme_constant_override("separation", 0)
	header.add_child(brand_box)
	var brand := Label.new()
	brand.text = "بلدی؟"
	brand.add_theme_font_size_override("font_size", 31)
	brand.add_theme_color_override("font_color", GOLD)
	brand_box.add_child(brand)
	var tagline := Label.new()
	tagline.text = "ببین چند کلمه بلدی!"
	tagline.add_theme_font_size_override("font_size", 12)
	tagline.add_theme_color_override("font_color", MUTED)
	brand_box.add_child(tagline)

	var coin_panel := _panel(Color("#604b2b"))
	coin_panel.custom_minimum_size = Vector2(104, 48)
	header.add_child(coin_panel)
	coin_label = Label.new()
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_label.add_theme_font_size_override("font_size", 18)
	coin_label.add_theme_color_override("font_color", CREAM)
	coin_panel.add_child(coin_label)
	var logout_button := _make_button("خروج", Color("#70413b"), CREAM)
	logout_button.custom_minimum_size = Vector2(64, 48)
	logout_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	logout_button.pressed.connect(_logout)
	header.add_child(logout_button)

	var rule := ColorRect.new()
	rule.custom_minimum_size.y = 2
	rule.color = Color("#8d7548")
	page_box.add_child(rule)

	content_box = VBoxContainer.new()
	content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 12)
	page_box.add_child(content_box)

	var footer := Label.new()
	footer.text = "ALISHAMS GAME STUDIO"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color("#78968b"))
	page_box.add_child(footer)

	trace_line = Line2D.new()
	trace_line.width = 7.0
	trace_line.default_color = GOLD
	trace_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trace_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	trace_line.joint_mode = Line2D.LINE_JOINT_ROUND
	trace_line.z_index = 50
	trace_line.antialiased = true
	trace_line.visible = false
	add_child(trace_line)
	coin_label.text = "◆ %d" % coins

func _clear_content() -> void:
	is_dragging = false
	active_pointer = -1
	trace_line.clear_points()
	trace_line.visible = false
	for child in content_box.get_children():
		child.queue_free()

func _show_auth(message: String = "") -> void:
	_clear_content()
	coin_label.text = "حساب"
	var heading := Label.new()
	heading.text = "ورود به بازی"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)

	var intro := Label.new()
	intro.text = "برای بازی، با همان ایمیل و رمز عبور حساب کاربری alishams.ir وارد شو."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.add_theme_color_override("font_color", MUTED)
	content_box.add_child(intro)

	var form := _panel()
	content_box.add_child(form)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 10)
	form.add_child(fields)

	auth_name_input = LineEdit.new()
	auth_name_input.placeholder_text = "نام نمایشی، فقط هنگام ساخت حساب"
	auth_name_input.custom_minimum_size.y = 48
	fields.add_child(auth_name_input)

	auth_email_input = LineEdit.new()
	auth_email_input.placeholder_text = "ایمیل حساب کاربری"
	auth_email_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	auth_email_input.custom_minimum_size.y = 48
	fields.add_child(auth_email_input)

	auth_password_input = LineEdit.new()
	auth_password_input.placeholder_text = "رمز عبور"
	auth_password_input.secret = true
	auth_password_input.custom_minimum_size.y = 48
	fields.add_child(auth_password_input)

	var login_button := _make_button("ورود به حساب", Color("#287c68"), CREAM)
	login_button.pressed.connect(_on_login_pressed)
	fields.add_child(login_button)

	var signup_button := _make_button("ساخت حساب کاربری", Color("#a77a35"), Color("#172b25"))
	signup_button.pressed.connect(_on_signup_pressed)
	fields.add_child(signup_button)

	var guest_button := _make_button("ورود مهمان", Color("#294c43"), GOLD)
	guest_button.pressed.connect(_show_guest_warning)
	fields.add_child(guest_button)

	auth_status_label = Label.new()
	auth_status_label.text = message
	auth_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auth_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auth_status_label.add_theme_color_override("font_color", RED if not message.is_empty() else MUTED)
	content_box.add_child(auth_status_label)

func _show_guest_warning() -> void:
	var warning := ConfirmationDialog.new()
	warning.title = "ورود به‌صورت مهمان"
	warning.dialog_text = "در حالت مهمان، پیشرفت، سکه‌ها و زمان بازی در حساب کاربری alishams.ir ثبت یا همگام‌سازی نمی‌شوند. اطلاعات فقط روی همین دستگاه ذخیره می‌شود و با حذف داده‌های بازی ممکن است از بین برود. برای ثبت دائمی پیشرفت، با حساب کاربری وارد شو."
	warning.ok_button_text = "ادامه به‌عنوان مهمان"
	warning.cancel_button_text = "بازگشت"
	warning.confirmed.connect(_enter_guest)
	add_child(warning)
	warning.popup_centered(Vector2i(420, 260))

func _on_login_pressed() -> void:
	if auth_email_input.text.strip_edges().is_empty() or auth_password_input.text.is_empty():
		auth_status_label.text = "ایمیل و رمز عبور را وارد کن."
		auth_status_label.add_theme_color_override("font_color", RED)
		return
	auth_status_label.text = "در حال ورود به حساب…"
	var result: Dictionary = await CloudAccount.sign_in(auth_email_input.text, auth_password_input.text)
	if not result.get("ok", false):
		auth_status_label.text = str(result.get("error", "ورود انجام نشد."))
		auth_status_label.add_theme_color_override("font_color", RED)
		return
	await _enter_game()

func _on_signup_pressed() -> void:
	if auth_name_input.text.strip_edges().length() < 2 or auth_email_input.text.strip_edges().is_empty() or auth_password_input.text.length() < 8:
		auth_status_label.text = "نام، ایمیل و رمز عبور حداقل ۸ نویسه‌ای را وارد کن."
		auth_status_label.add_theme_color_override("font_color", RED)
		return
	auth_status_label.text = "در حال ساخت حساب…"
	var result: Dictionary = await CloudAccount.sign_up(auth_email_input.text, auth_password_input.text, auth_name_input.text)
	if not result.get("ok", false):
		auth_status_label.text = str(result.get("error", "ساخت حساب انجام نشد."))
		auth_status_label.add_theme_color_override("font_color", RED)
		return
	if result.get("confirmed", false):
		await _enter_game()
	else:
		auth_status_label.text = "حساب ساخته شد. ایمیل تأیید را بررسی کن، سپس با همان حساب وارد شو."
		auth_status_label.add_theme_color_override("font_color", GREEN)

func _apply_cloud_profile(profile: Dictionary) -> void:
	coins = int(profile.get("coins", coins))
	cloud_current_level = int(profile.get("current_level", cloud_current_level))
	var remote_completed = profile.get("completed_levels", completed_levels)
	if remote_completed is Array:
		completed_levels = remote_completed.duplicate()
	_save()
	_update_controls()

func _show_map() -> void:
	_clear_content()
	coin_label.text = "◆ %d" % coins

	var heading := Label.new()
	heading.text = "نقشه مراحل"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", CREAM)
	content_box.add_child(heading)

	var completed_count := completed_levels.size()
	var progress_panel := _panel()
	content_box.add_child(progress_panel)
	var progress_box := VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 7)
	progress_panel.add_child(progress_box)
	var progress_text := Label.new()
	progress_text.text = "پیشرفت تو  ·  %d از %d مرحله" % [completed_count, levels.size()]
	progress_text.add_theme_color_override("font_color", GOLD)
	progress_text.add_theme_font_size_override("font_size", 15)
	progress_box.add_child(progress_text)
	var progress := ProgressBar.new()
	progress.min_value = 0
	progress.max_value = max(1, levels.size())
	progress.value = completed_count
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12
	progress_box.add_child(progress)

	if cloud_current_level > levels.size():
		var finished := Label.new()
		finished.text = "همه مراحل فعلی را با موفقیت به پایان رساندی!\nمراحل تازه به‌زودی اضافه می‌شوند."
		finished.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		finished.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		finished.add_theme_font_size_override("font_size", 18)
		finished.add_theme_color_override("font_color", GOLD)
		content_box.add_child(finished)
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_box.add_child(scroll)
	var stage_list := VBoxContainer.new()
	stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_list.add_theme_constant_override("separation", 10)
	scroll.add_child(stage_list)

	for i in range(levels.size()):
		var data: Dictionary = levels[i]
		var stage_id := int(data.get("id", i + 1))
		var is_done := completed_levels.has(stage_id)
		var is_open := i == 0 or completed_levels.has(int(levels[i - 1].get("id", i)))
		var is_current := i == cloud_current_level - 1
		var stage_button := Button.new()
		stage_button.custom_minimum_size = Vector2(220, 76)
		stage_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stage_button.alignment = HORIZONTAL_ALIGNMENT_FILL
		stage_button.text = ("✓   مرحله %02d     %s" % [stage_id, str(data.get("title", ""))]) if is_done else (("◈   مرحله %02d     %s" % [stage_id, str(data.get("title", ""))]) if is_open else ("🔒   مرحله %02d     قفل است" % stage_id))
		stage_button.disabled = not is_open or is_done or not is_current
		stage_button.add_theme_font_size_override("font_size", 17)
		stage_button.add_theme_color_override("font_color", GOLD if is_done else (CREAM if is_open else MUTED))
		stage_button.add_theme_color_override("font_disabled_color", GOLD if is_done else Color("#70877e"))
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#245448") if is_done else (PANEL_ALT if is_open else Color("#122d29"))
		style.border_color = GOLD if is_done else (TEAL if is_open else Color("#29433c"))
		style.set_border_width_all(1)
		style.set_corner_radius_all(16)
		style.content_margin_left = 14
		style.content_margin_right = 14
		stage_button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = style.bg_color.lightened(0.10)
		stage_button.add_theme_stylebox_override("hover", hover)
		var disabled_style := style.duplicate()
		disabled_style.bg_color = style.bg_color
		stage_button.add_theme_stylebox_override("disabled", disabled_style)
		stage_button.pressed.connect(_open_level.bind(i))
		var route_row := HBoxContainer.new()
		route_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_list.add_child(route_row)
		var route_spacer := Control.new()
		route_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i % 2 == 0:
			route_row.add_child(stage_button)
			route_row.add_child(route_spacer)
		else:
			route_row.add_child(route_spacer)
			route_row.add_child(stage_button)
		stage_button.modulate.a = 0.0
		var node_tween := create_tween()
		node_tween.tween_property(stage_button, "modulate:a", 1.0, 0.24).set_delay(float(i) * 0.018)

func _open_level(index: int) -> void:
	if index < 0 or index >= levels.size():
		return
	if index != cloud_current_level - 1:
		return
	if index > 0 and not completed_levels.has(int(levels[index - 1].get("id", index))):
		return
	level_index = index
	_save()
	_show_game()
	var stage_id := int(levels[level_index].get("id", level_index + 1))
	if _is_level_complete() and not completed_levels.has(stage_id):
		var completion: Dictionary = await CloudAccount.complete_level(stage_id)
		if completion.get("ok", false):
			_apply_cloud_profile(completion.get("profile", {}))
			_set_status("پیشرفت ذخیره‌شده بازیابی شد و مرحله تکمیل شد.", GREEN)
		else:
			_set_status(str(completion.get("error", "ثبت مرحله انجام نشد.")), RED)

func _show_game() -> void:
	_clear_content()
	if levels.is_empty():
		var error_label := Label.new()
		error_label.text = "داده مراحل بارگذاری نشد."
		content_box.add_child(error_label)
		return

	var data: Dictionary = levels[level_index]
	level_label = Label.new()
	level_label.text = "مرحله %02d" % int(data.get("id", level_index + 1))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 25)
	level_label.add_theme_color_override("font_color", GOLD)
	content_box.add_child(level_label)

	subtitle_label = Label.new()
	subtitle_label.text = str(data.get("title", ""))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 13)
	subtitle_label.add_theme_color_override("font_color", MUTED)
	content_box.add_child(subtitle_label)

	var board_panel := _panel()
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_panel.custom_minimum_size.y = 210
	content_box.add_child(board_panel)
	board_box = GridContainer.new()
	board_box.columns = 2
	board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_box.add_theme_constant_override("h_separation", 9)
	board_box.add_theme_constant_override("v_separation", 9)
	board_panel.add_child(board_box)
	_render_board()

	var selection_panel := _panel(Color("#4c432e"))
	selection_panel.custom_minimum_size.y = 60
	content_box.add_child(selection_panel)
	selection_label = Label.new()
	selection_label.text = "حروف را با کشیدن انگشت به هم وصل کن"
	selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selection_label.add_theme_font_size_override("font_size", 22)
	selection_label.add_theme_color_override("font_color", GOLD)
	selection_panel.add_child(selection_label)

	letters_grid = GridContainer.new()
	letters_grid.columns = 4
	letters_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	letters_grid.add_theme_constant_override("h_separation", 9)
	letters_grid.add_theme_constant_override("v_separation", 9)
	content_box.add_child(letters_grid)
	_render_letters()

	status_label = Label.new()
	status_label.text = "از روی حروف بکش و یک واژه بساز."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", MUTED)
	content_box.add_child(status_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content_box.add_child(actions)
	var clear_button := _make_button("پاک‌کردن", PANEL_ALT, CREAM)
	clear_button.pressed.connect(_clear_selection)
	actions.add_child(clear_button)
	hint_button = _make_button("راهنما · ۲۰", Color("#765a31"), CREAM)
	hint_button.pressed.connect(_use_hint)
	actions.add_child(hint_button)
	submit_button = _make_button("ثبت واژه", GOLD, BG)
	submit_button.pressed.connect(_submit_word)
	actions.add_child(submit_button)

	var map_button := _make_button("بازگشت به نقشه مراحل", Color("#203e38"), CREAM)
	map_button.pressed.connect(_show_map)
	content_box.add_child(map_button)
	_update_controls()

func _init_audio() -> void:
	sfx_player = AudioStreamPlayer.new()
	sfx_player.volume_db = -7.0
	add_child(sfx_player)

func _play_sfx(kind: String) -> void:
	if sfx_player == null:
		return
	var notes: Array[float] = [520.0]
	match kind:
		"found":
			notes = [587.0, 740.0, 880.0]
		"bonus":
			notes = [740.0, 932.0, 1175.0]
		"complete":
			notes = [523.0, 659.0, 784.0, 1046.0]
		"select":
			notes = [620.0]
	sfx_player.stream = _make_chime(notes)
	sfx_player.play()

func _make_chime(notes: Array[float]) -> AudioStreamWAV:
	var sample_rate := 22050
	var note_seconds := 0.075
	var samples_per_note := int(sample_rate * note_seconds)
	var pcm := PackedByteArray()
	pcm.resize(samples_per_note * notes.size() * 2)
	for note_index in range(notes.size()):
		for sample_index in range(samples_per_note):
			var progress := float(sample_index) / float(samples_per_note)
			var attack := minf(1.0, progress * 24.0)
			var release := minf(1.0, (1.0 - progress) * 8.0)
			var envelope := minf(attack, release)
			var time := float(sample_index) / float(sample_rate)
			var fundamental := sin(TAU * notes[note_index] * time)
			var harmonic := sin(TAU * notes[note_index] * 2.0 * time) * 0.18
			var sample := (fundamental + harmonic) * 0.22 * envelope
			pcm.encode_s16((note_index * samples_per_note + sample_index) * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = pcm
	return stream

func _panel(border_color: Color = Color("#557b6d")) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(17)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_button(label_text: String, color: Color, text_color: Color) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(13)
	normal.content_margin_left = 9
	normal.content_margin_right = 9
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.12)
	button.add_theme_stylebox_override("pressed", pressed)
	return button

func _render_board() -> void:
	for child in board_box.get_children():
		child.queue_free()
	var data: Dictionary = levels[level_index]
	var answers: Array = data.get("answers", [])
	var words: Array = _words_for_current_level()
	for word_value in answers:
		var word := str(word_value)
		var tile := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#285b49") if words.has(word) else Color("#102e29")
		style.border_color = GOLD if words.has(word) else Color("#41685a")
		style.set_border_width_all(1)
		style.set_corner_radius_all(11)
		style.content_margin_left = 5
		style.content_margin_right = 5
		style.content_margin_top = 9
		style.content_margin_bottom = 9
		tile.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = word if words.has(word) else "•  " + "ـ".repeat(max(2, word.length())) + "  •"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", CREAM if words.has(word) else MUTED)
		tile.add_child(label)
		board_box.add_child(tile)
		if words.has(word):
			tile.scale = Vector2(0.92, 0.92)
			tile.pivot_offset = tile.size / 2.0
			var tween := create_tween()
			tween.tween_property(tile, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _render_letters() -> void:
	for child in letters_grid.get_children():
		child.queue_free()
	letter_buttons.clear()
	selected_indices.clear()
	selected_word = ""
	var letters: Array = levels[level_index].get("letters", [])
	letters_grid.columns = 4 if letters.size() > 4 else max(2, letters.size())
	for i in range(letters.size()):
		var button := _make_button(str(letters[i]), PANEL_ALT, CREAM)
		button.custom_minimum_size = Vector2(0, 64)
		button.add_theme_font_size_override("font_size", 27)
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.pivot_offset = Vector2(40, 32)
		letters_grid.add_child(button)
		letter_buttons.append(button)
	_update_selection_label()

func _words_for_current_level() -> Array:
	var key := str(int(levels[level_index].get("id", level_index + 1)))
	var value = level_solved.get(key, [])
	return value if value is Array else []

func _bonus_words_for_current_level() -> Array:
	var key := str(int(levels[level_index].get("id", level_index + 1)))
	var value = level_bonus_found.get(key, [])
	return value if value is Array else []

func _letter_at(point: Vector2) -> int:
	for i in range(letter_buttons.size()):
		var button := letter_buttons[i]
		if is_instance_valid(button) and button.get_global_rect().has_point(point):
			return i
	return -1

func _begin_trace(point: Vector2, pointer_id: int = -1) -> void:
	var index := _letter_at(point)
	if index < 0:
		return
	is_dragging = true
	active_pointer = pointer_id
	trace_line.clear_points()
	trace_line.visible = true
	_add_trace_letter(index)
	trace_line.add_point(point)

func _continue_trace(point: Vector2) -> void:
	if not is_dragging:
		return
	var index := _letter_at(point)
	if index >= 0 and (selected_indices.is_empty() or selected_indices[-1] != index):
		_add_trace_letter(index)
	var curve := Curve2D.new()
	for selected_index in selected_indices:
		var rect := letter_buttons[selected_index].get_global_rect()
		curve.add_point(rect.get_center())
	curve.add_point(point)
	trace_line.points = curve.get_baked_points()

func _add_trace_letter(index: int) -> void:
	if index < 0 or index >= letter_buttons.size() or selected_indices.has(index):
		return
	selected_indices.append(index)
	var letters: Array = levels[level_index].get("letters", [])
	selected_word += str(letters[index])
	var button := letter_buttons[index]
	button.modulate = GOLD
	_play_sfx("select")
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.16, 1.16), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_update_selection_label()
	_update_controls()

func _finish_trace() -> void:
	if not is_dragging:
		return
	is_dragging = false
	active_pointer = -1
	trace_line.visible = false
	trace_line.clear_points()
	if not selected_word.is_empty():
		_submit_word()

func _input(event: InputEvent) -> void:
	if letters_grid == null or not is_instance_valid(letters_grid):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_trace(event.position)
		else:
			_finish_trace()
	elif event is InputEventMouseMotion and is_dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_continue_trace(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_trace(event.position, event.index)
		elif is_dragging and (active_pointer == -1 or active_pointer == event.index):
			_finish_trace()
	elif event is InputEventScreenDrag and is_dragging:
		if active_pointer == -1 or active_pointer == event.index:
			_continue_trace(event.position)

func _update_selection_label() -> void:
	if selection_label == null or not is_instance_valid(selection_label):
		return
	selection_label.text = selected_word if not selected_word.is_empty() else "حروف را با کشیدن انگشت به هم وصل کن"

func _clear_selection() -> void:
	is_dragging = false
	active_pointer = -1
	trace_line.visible = false
	trace_line.clear_points()
	for index in selected_indices:
		if index < letter_buttons.size():
			letter_buttons[index].modulate = Color.WHITE
			letter_buttons[index].scale = Vector2.ONE
	selected_indices.clear()
	selected_word = ""
	_update_selection_label()
	_update_controls()

func _normalize_word(value: String) -> String:
	var result := value.strip_edges().replace("ي", "ی").replace("ك", "ک")
	result = result.replace("‌", "").replace("ـ", "")
	return result

func _submit_word() -> void:
	if selected_word.is_empty():
		return
	var candidate := _normalize_word(selected_word)
	var stage_id := int(levels[level_index].get("id", level_index + 1))
	var answers: Array = levels[level_index].get("answers", [])
	var matched := ""
	for answer in answers:
		if _normalize_word(str(answer)) == candidate:
			matched = str(answer)
			break

	if not matched.is_empty():
		if _words_for_current_level().has(matched):
			_set_status("این واژه را قبلاً پیدا کرده‌ای.", GOLD)
		elif guest_mode:
			var guest_words := _words_for_current_level()
			guest_words.append(matched)
			level_solved[str(stage_id)] = guest_words
			coins += 3
			_play_sfx("found")
			_animate_coin_reward(3)
			if _is_level_complete():
				_complete_guest_level()
			else:
				_set_status("آفرین! واژه پیدا شد و ۳ سکه گرفتی.", GREEN)
				_render_board()
		else:
			var word_result: Dictionary = await CloudAccount.record_word_found(matched, stage_id)
			if not word_result.get("ok", false):
				_set_status(str(word_result.get("error", "ثبت واژه در حساب انجام نشد.")), RED)
			elif word_result.get("already_found", false):
				_set_status("این واژه قبلاً در حسابت ثبت شده است.", GOLD)
			else:
				_apply_cloud_profile(word_result.get("profile", {}))
				var member_words := _words_for_current_level()
				member_words.append(matched)
				level_solved[str(stage_id)] = member_words
				var awarded := int(word_result.get("coins_awarded", 3))
				if awarded > 0:
					_play_sfx("found")
					_animate_coin_reward(awarded)
				if _is_level_complete():
					var completion: Dictionary = await CloudAccount.complete_level(stage_id)
					if completion.get("ok", false):
						_apply_cloud_profile(completion.get("profile", {}))
						_show_stage_complete(int(levels[level_index].get("reward", 0)))
					else:
						_set_status(str(completion.get("error", "ثبت تکمیل مرحله انجام نشد.")), RED)
						_render_board()
				else:
					_set_status("آفرین! یک واژه دیگر پیدا کردی.", GREEN)
					_render_board()
		_save()
	elif bonus_word_set.has(candidate):
		if _bonus_words_for_current_level().has(candidate):
			_set_status("این واژه اضافه را قبلاً پیدا کرده‌ای و پاداشش را گرفته‌ای.", GOLD)
		elif guest_mode:
			var guest_bonus := _bonus_words_for_current_level()
			guest_bonus.append(candidate)
			level_bonus_found[str(stage_id)] = guest_bonus
			coins += 7
			_play_sfx("bonus")
			_animate_coin_reward(7)
			_show_bonus_word_feedback(candidate)
			_save()
		else:
			var bonus_result: Dictionary = await CloudAccount.record_word_found(candidate, stage_id)
			if not bonus_result.get("ok", false):
				_set_status(str(bonus_result.get("error", "اعتبار واژه بررسی نشد.")), RED)
			elif bonus_result.get("already_found", false):
				_set_status("این واژه را قبلاً پیدا کرده‌ای؛ پاداش آن قبلاً پرداخت شده است.", GOLD)
				var existing_bonus := _bonus_words_for_current_level()
				if not existing_bonus.has(candidate):
					existing_bonus.append(candidate)
					level_bonus_found[str(stage_id)] = existing_bonus
			else:
				_apply_cloud_profile(bonus_result.get("profile", {}))
				var member_bonus := _bonus_words_for_current_level()
				member_bonus.append(candidate)
				level_bonus_found[str(stage_id)] = member_bonus
				var bonus_coins := int(bonus_result.get("coins_awarded", 7))
				if bonus_coins > 0:
					_play_sfx("bonus")
					_animate_coin_reward(bonus_coins)
				_show_bonus_word_feedback(candidate)
				_save()
	else:
		_set_status("این واژه در واژه‌نامه فارسی پیدا نشد. دوباره تلاش کن.", RED)
	_clear_selection()
	_update_controls()

func _complete_guest_level() -> void:
	var stage_id := int(levels[level_index].get("id", level_index + 1))
	if completed_levels.has(stage_id):
		return
	completed_levels.append(stage_id)
	var reward := int(levels[level_index].get("reward", 0))
	coins += reward
	cloud_current_level = stage_id + 1
	_save()
	_show_stage_complete(reward)

func _show_bonus_word_feedback(word: String) -> void:
	_set_status("«%s» واژه فارسی معتبری است، اما پاسخ اصلی این مرحله نیست؛ ۷ سکه هدیه گرفتی!" % word, GOLD)
	_spawn_floating_text("+۷ سکه هدیه", GOLD)

func _spawn_floating_text(message: String, color: Color) -> void:
	var popup := Label.new()
	popup.text = message
	popup.add_theme_font_size_override("font_size", 19)
	popup.add_theme_color_override("font_color", color)
	popup.add_theme_color_override("font_shadow_color", Color("#071613"))
	popup.add_theme_constant_override("shadow_offset_x", 1)
	popup.add_theme_constant_override("shadow_offset_y", 2)
	popup.z_index = 100
	popup.position = Vector2(size.x * 0.5 - 100, size.y * 0.58)
	popup.size = Vector2(200, 38)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(popup)
	popup.scale = Vector2(0.65, 0.65)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 78, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.85).set_delay(0.22)
	tween.chain().tween_callback(popup.queue_free)

func _animate_coin_reward(amount: int) -> void:
	if amount == 0:
		return
	if coin_label != null and is_instance_valid(coin_label):
		var pulse := create_tween()
		pulse.tween_property(coin_label, "scale", Vector2(1.24, 1.24), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pulse.tween_property(coin_label, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		coin_label.text = "◆ %d" % coins
	var display_text := "+%d ◆" % amount if amount > 0 else "−%d ◆" % abs(amount)
	_spawn_floating_text(display_text, GOLD if amount > 0 else CREAM)

func _show_stage_complete(reward: int) -> void:
	_play_sfx("complete")
	_animate_coin_reward(reward)
	var overlay := ColorRect.new()
	overlay.color = Color("#061512")
	overlay.modulate.a = 0.0
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := _panel(GOLD)
	card.custom_minimum_size = Vector2(310, 270)
	center.add_child(card)
	card.scale = Vector2(0.72, 0.72)
	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 14)
	card.add_child(body)
	var title := Label.new()
	title.text = "مرحله با موفقیت کامل شد!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", GOLD)
	body.add_child(title)
	var reward_label := Label.new()
	reward_label.text = "◆  +%d سکه پاداش" % reward
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_label.add_theme_font_size_override("font_size", 21)
	reward_label.add_theme_color_override("font_color", CREAM)
	body.add_child(reward_label)
	var next_button := _make_button("رفتن به مرحله بعد", Color("#287c68"), CREAM)
	next_button.disabled = cloud_current_level > levels.size()
	next_button.pressed.connect(func():
		overlay.queue_free()
		if level_index + 1 < levels.size():
			_open_level(level_index + 1)
		else:
			_show_map()
	)
	body.add_child(next_button)
	var map_button := _make_button("مشاهده نقشه مراحل", Color("#294c43"), GOLD)
	map_button.pressed.connect(func():
		overlay.queue_free()
		_show_map()
	)
	body.add_child(map_button)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 0.82, 0.22)
	tween.tween_property(card, "scale", Vector2.ONE, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _set_status(message: String, color: Color) -> void:
	if status_label != null and is_instance_valid(status_label):
		status_label.text = message
		status_label.add_theme_color_override("font_color", color)

func _is_level_complete() -> bool:
	if levels.is_empty():
		return false
	var answers: Array = levels[level_index].get("answers", [])
	var words := _words_for_current_level()
	for answer in answers:
		if not words.has(str(answer)):
			return false
	return true

func _use_hint() -> void:
	if coins < 20:
		_set_status("سکه کافی نداری. با حل واژه‌ها سکه جمع کن.", RED)
		return
	var target := ""
	for answer in levels[level_index].get("answers", []):
		if not _words_for_current_level().has(str(answer)):
			target = str(answer)
			break
	if target.is_empty():
		return
	var stage_id := int(levels[level_index].get("id", level_index + 1))
	if guest_mode:
		coins -= 20
		var guest_words := _words_for_current_level()
		guest_words.append(target)
		level_solved[str(stage_id)] = guest_words
		_play_sfx("select")
		_animate_coin_reward(-20)
		if _is_level_complete():
			_complete_guest_level()
		else:
			_set_status("راهنما واژه «%s» را آشکار کرد." % target, GOLD)
			_render_board()
		_save()
		_update_controls()
		return
	var spend_result: Dictionary = await CloudAccount.use_hint(target, stage_id)
	if not spend_result.get("ok", false):
		_set_status(str(spend_result.get("error", "مصرف سکه انجام نشد.")), RED)
		return
	_apply_cloud_profile(spend_result.get("profile", {}))
	var words := _words_for_current_level()
	words.append(target)
	level_solved[str(stage_id)] = words
	_animate_coin_reward(-20)
	if _is_level_complete():
		var completion: Dictionary = await CloudAccount.complete_level(stage_id)
		if completion.get("ok", false):
			_apply_cloud_profile(completion.get("profile", {}))
			_show_stage_complete(int(levels[level_index].get("reward", 0)))
		else:
			_set_status(str(completion.get("error", "ثبت تکمیل مرحله انجام نشد.")), RED)
	else:
		_set_status("راهنما واژه «%s» را آشکار کرد." % target, GOLD)
		_render_board()
	_save()
	_update_controls()

func _update_controls() -> void:
	if coin_label != null and is_instance_valid(coin_label):
		coin_label.text = "◆ %d" % coins
	if hint_button != null and is_instance_valid(hint_button):
		hint_button.disabled = _is_level_complete() or coins < 20
	if submit_button != null and is_instance_valid(submit_button):
		submit_button.disabled = _is_level_complete() or selected_word.is_empty()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
		if not guest_mode and CloudAccount.is_authenticated():
			await CloudAccount.end_session()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_save()
		if not guest_mode and CloudAccount.is_authenticated():
			await CloudAccount.touch_session()
