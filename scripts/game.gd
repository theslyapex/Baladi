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
var hint_history: Dictionary = {}
var guest_mode := false
var sfx_player: AudioStreamPlayer
var selected_indices: Array[int] = []
var selected_word := ""
var is_dragging := false
var active_pointer := -1

var page_box: VBoxContainer
var content_box: VBoxContainer
var coin_label: Label
var coin_panel: PanelContainer
var coin_icon_control: TextureRect
var level_label: Label
var subtitle_label: Label
var board_box: GridContainer
var selection_label: Label
var letters_grid: Control
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
var exit_button: Button
var profile_button: Button
var profile_name_input: LineEdit
var profile_rename_button: Button
var profile_status_label: Label
var display_name := "بازیکن"
var diamonds := 0
var name_change_count := 0
var sound_enabled := true
var daily_streak := 0
var last_checkin_date := ""
var avatar_path := ""
var avatar_unlocked := false
var equipped_frame_id := "frame_default"
var wins := 0
var losses := 0
var chat_unlocked := false
var chat_poll_timer: Timer
var chat_messages_box: VBoxContainer
var chat_input: LineEdit
var chat_status_label: Label
var chat_poll_busy := false
var active_group_chat_id := ""
var active_group_chat_name := ""
var active_group_role := ""
var group_name_input: LineEdit
var group_description_input: LineEdit
var duel_mode := false
var duel_match_id := ""
var duel_round_number := 1
var duel_answer_count := 0
var duel_current_letters: Array = []
var duel_found_words: Array = []
var duel_poll_timer: Timer
var duel_poll_busy := false
var crop_source_image: Image
var crop_viewport: Control
var crop_texture_rect: TextureRect
var crop_zoom_slider: HSlider
var crop_zoom := 1.0
var crop_offset := Vector2.ZERO
var crop_dragging := false
var auth_signup_mode := false
var auth_login_button: Button
var auth_mode_toggle_button: Button
var stage_scroll: ScrollContainer
var stage_touch_active := false
var stage_touch_y := 0.0

var startup_action_taken := false
var startup_restore_in_progress := false
var current_page := "auth"
var back_confirm: ConfirmationDialog
var back_navigation := {
	"profile": "map", "global_chat": "map", "groups": "map", "settings": "map", "privacy": "settings", "faq": "settings",
	"group_chat": "groups", "sticker_picker": "global_chat",
	"cosmetic_shop": "profile", "leaderboard": "map",
	"duel_invites": "map", "duel_game": "duel_invites",
	"duel_result": "duel_invites", "public_profile": "leaderboard",
	"avatar_crop": "profile", "game": "map", "map": "exit"
}

func _ready() -> void:
	back_confirm = ConfirmationDialog.new()
	back_confirm.title = "خروج از بازی"
	back_confirm.dialog_text = "می‌خواهی از برنامه خارج شوی؟"
	back_confirm.ok_button_text = "خروج از برنامه"
	back_confirm.cancel_button_text = "ادامه بازی"
	back_confirm.confirmed.connect(_confirm_app_exit)
	add_child(back_confirm)
	_load_levels()
	_load_bonus_dictionary()
	_build_base()
	_init_audio()
	startup_restore_in_progress = true
	_show_auth("در حال بررسی حساب ذخیره‌شده…")
	print("[Baladi] UI initialized; checking saved account in background.")
	var restored: bool = await CloudAccount.restore_session()
	startup_restore_in_progress = false
	if startup_action_taken or guest_mode:
		return
	if restored:
		print("[Baladi] Saved account restored; starting game session.")
		await _enter_game()
	else:
		print("[Baladi] No saved account; showing sign-in screen.")
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
	if guest_mode or not CloudAccount.is_authenticated():
		return "user://baladi_save_guest.cfg"
	return SAVE_PATH_PREFIX + str(CloudAccount.user_id) + ".cfg"

func _enter_game() -> void:
	guest_mode = false
	var response: Dictionary = await CloudAccount.start_game_session()
	if not response.get("ok", false):
		_show_auth(str(response.get("error", "ورود به بازی انجام نشد.")))
		return
	var profile: Dictionary = response.get("profile", {})
	_load_save()
	coins = int(profile.get("coins", 100))
	diamonds = int(profile.get("diamonds", 0))
	name_change_count = int(profile.get("name_change_count", 0))
	var profile_name = profile.get("display_name", null)
	display_name = _safe_player_name(profile_name, CloudAccount.display_name)
	if display_name.is_empty():
		display_name = CloudAccount.display_name if not CloudAccount.display_name.is_empty() else "بازیکن"
	daily_streak = int(profile.get("daily_streak", 0))
	last_checkin_date = str(profile.get("last_checkin_date", ""))
	avatar_path = str(profile.get("avatar_path", ""))
	avatar_unlocked = bool(profile.get("avatar_unlocked", false))
	equipped_frame_id = str(profile.get("equipped_frame_id", "frame_default"))
	wins = int(profile.get("wins", 0))
	losses = int(profile.get("losses", 0))
	var chat_stamp = profile.get("chat_unlocked_at", null)
	chat_unlocked = chat_stamp != null and not str(chat_stamp).is_empty()
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
	var checkin_result: Dictionary = await CloudAccount.daily_checkin()
	if checkin_result.get("ok", false):
		_apply_cloud_profile(checkin_result.get("profile", {}))
		var daily_reward := int(checkin_result.get("reward", 0))
		_save()
		if daily_reward > 0:
			_animate_coin_reward(daily_reward)
			_spawn_floating_text("جایزهٔ روز %d: +%d سکه" % [int(checkin_result.get("cycle_day", 1)), daily_reward], GOLD)
		elif int(checkin_result.get("cycle_day", 1)) > 0:
			_spawn_floating_text("روز %d از زنجیرهٔ حضور" % int(checkin_result.get("cycle_day", 1)), TEAL)
	if session_timer == null:
		session_timer = Timer.new()
		session_timer.wait_time = 45.0
		session_timer.timeout.connect(_heartbeat)
		add_child(session_timer)
	session_timer.start()
	_show_map()

func _enter_guest() -> void:
	startup_action_taken = true
	guest_mode = true
	_load_save()
	_guest_daily_checkin()
	cloud_current_level = clampi(cloud_current_level, 1, levels.size() + 1)
	level_index = clampi(cloud_current_level - 1, 0, max(0, levels.size() - 1))
	if session_timer != null:
		session_timer.stop()
	_show_map()
	_set_status("حالت مهمان فعال است؛ پیشرفت فقط روی همین دستگاه می‌ماند.", GOLD)

func _tehran_date_string() -> String:
	var tehran_time := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + 12600)
	return "%04d-%02d-%02d" % [tehran_time.year, tehran_time.month, tehran_time.day]

func _guest_daily_checkin() -> void:
	var today := _tehran_date_string()
	if last_checkin_date == today:
		return
	var consecutive := false
	if not last_checkin_date.is_empty():
		var previous := Time.get_datetime_dict_from_datetime_string(last_checkin_date + "T00:00:00", false)
		var current := Time.get_datetime_dict_from_datetime_string(today + "T00:00:00", false)
		var previous_stamp := Time.get_unix_time_from_datetime_dict(previous)
		var current_stamp := Time.get_unix_time_from_datetime_dict(current)
		consecutive = current_stamp - previous_stamp >= 86300.0 and current_stamp - previous_stamp <= 86500.0
	daily_streak = daily_streak + 1 if consecutive else 1
	last_checkin_date = today
	var cycle_day := ((daily_streak - 1) % 20) + 1
	var reward_by_day := {1: 20, 4: 80, 6: 180, 10: 250, 15: 500, 20: 1000}
	var reward := int(reward_by_day.get(cycle_day, 0))
	if reward > 0:
		coins += reward
		_play_sfx("complete")
		_animate_coin_reward(reward)
		_spawn_floating_text("جایزهٔ روز %d: +%d سکه" % [cycle_day, reward], GOLD)
	else:
		_spawn_floating_text("روز %d از زنجیرهٔ حضور" % cycle_day, TEAL)
	_save()

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
	diamonds = int(cfg.get_value("player", "diamonds", 0))
	name_change_count = int(cfg.get_value("player", "name_change_count", 0))
	sound_enabled = bool(cfg.get_value("player", "sound_enabled", true))
	level_index = clampi(int(cfg.get_value("player", "level_index", 0)), 0, max(0, levels.size() - 1))
	cloud_current_level = int(cfg.get_value("player", "current_level", level_index + 1))
	display_name = _safe_player_name(cfg.get_value("player", "display_name", "بازیکن"))
	daily_streak = int(cfg.get_value("player", "daily_streak", 0))
	last_checkin_date = str(cfg.get_value("player", "last_checkin_date", ""))
	var saved_levels = cfg.get_value("player", "level_solved", {})
	if saved_levels is Dictionary:
		level_solved = saved_levels
	var saved_completed = cfg.get_value("player", "completed_levels", [])
	if saved_completed is Array:
		completed_levels = saved_completed
	var saved_bonus = cfg.get_value("player", "level_bonus_found", {})
	if saved_bonus is Dictionary:
		level_bonus_found = saved_bonus
	var saved_hints = cfg.get_value("player", "hint_history", {})
	if saved_hints is Dictionary:
		hint_history = saved_hints
	# Migrate saves from the first prototype.
	if level_solved.is_empty():
		var legacy = cfg.get_value("player", "solved", [])
		if legacy is Array and not legacy.is_empty() and not levels.is_empty():
			level_solved[str(levels[level_index].get("id", level_index + 1))] = legacy

func _safe_player_name(value: Variant, fallback: String = "بازیکن") -> String:
	var candidate := str(value).strip_edges()
	if candidate.is_empty() or candidate.to_lower() in ["null", "none"]:
		return fallback
	return candidate

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "diamonds", diamonds)
	cfg.set_value("player", "name_change_count", name_change_count)
	cfg.set_value("player", "sound_enabled", sound_enabled)
	cfg.set_value("player", "level_index", level_index)
	cfg.set_value("player", "level_solved", level_solved)
	cfg.set_value("player", "completed_levels", completed_levels)
	cfg.set_value("player", "current_level", cloud_current_level)
	cfg.set_value("player", "level_bonus_found", level_bonus_found)
	cfg.set_value("player", "hint_history", hint_history)
	cfg.set_value("player", "display_name", display_name)
	cfg.set_value("player", "daily_streak", daily_streak)
	cfg.set_value("player", "last_checkin_date", last_checkin_date)
	cfg.save(_save_path())

func _build_base() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	theme = preload("res://assets/theme/baladi_theme.tres")
	var background := TextureRect.new()
	background.texture = load("res://assets/backgrounds/ambient.svg")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.name = "MainMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	page_box = VBoxContainer.new()
	page_box.name = "PageBox"
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_box.add_theme_constant_override("separation", 14)
	margin.add_child(page_box)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	page_box.add_child(header)

	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 10)
	header.add_child(brand_row)
	var brand_box := VBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_box.add_theme_constant_override("separation", 0)
	brand_row.add_child(brand_box)
	var brand := Label.new()
	brand.text = "بلدی؟"
	brand.add_theme_font_size_override("font_size", 32)
	brand.add_theme_color_override("font_color", GOLD)
	brand_box.add_child(brand)
	var tagline := Label.new()
	tagline.text = "ببین چند کلمه بلدی!"
	tagline.add_theme_font_size_override("font_size", 12)
	tagline.add_theme_color_override("font_color", MUTED)
	brand_box.add_child(tagline)

	coin_panel = _panel(Color("#b98a35"))
	coin_panel.custom_minimum_size = Vector2(96, 46)
	brand_row.add_child(coin_panel)
	var coin_row := HBoxContainer.new()
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_theme_constant_override("separation", 6)
	coin_panel.add_child(coin_row)
	coin_icon_control = TextureRect.new()
	coin_icon_control.texture = load("res://assets/icons/coin.svg")
	coin_icon_control.custom_minimum_size = Vector2(27, 27)
	coin_icon_control.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	coin_icon_control.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_row.add_child(coin_icon_control)
	coin_label = Label.new()
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_label.add_theme_font_size_override("font_size", 18)
	coin_label.add_theme_color_override("font_color", CREAM)
	coin_row.add_child(coin_label)

	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_END
	action_row.add_theme_constant_override("separation", 8)
	header.add_child(action_row)
	profile_button = _make_button("پروفایل", Color("#294c43"), CREAM)
	profile_button.icon = load("res://assets/icons/profile.svg")
	profile_button.add_theme_constant_override("icon_max_width", 25)
	profile_button.custom_minimum_size = Vector2(112, 44)
	profile_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	profile_button.pressed.connect(_show_profile)
	action_row.add_child(profile_button)

	exit_button = _make_button("خروج", Color("#70413b"), CREAM)
	exit_button.custom_minimum_size = Vector2(104, 44)
	exit_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	exit_button.pressed.connect(_logout)
	action_row.add_child(exit_button)

	var rule := ColorRect.new()
	rule.custom_minimum_size.y = 2
	rule.color = Color("#8d7548")
	page_box.add_child(rule)

	var content_scroll := ScrollContainer.new()
	content_scroll.name = "ScreenContentScroll"
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.size_flags_stretch_ratio = 1.0
	page_box.add_child(content_scroll)

	content_box = VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content_box.add_theme_constant_override("separation", 12)
	content_scroll.add_child(content_box)
	stage_scroll = content_scroll

	var footer := Label.new()
	footer.text = "ALISHAMS GAME STUDIO"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color("#78968b"))
	page_box.add_child(footer)

	trace_line = Line2D.new()
	trace_line.width = 8.5
	trace_line.default_color = GOLD
	var trace_gradient := Gradient.new()
	trace_gradient.colors = PackedColorArray([Color("#f4d48e"), Color("#55c6b5")])
	trace_line.gradient = trace_gradient
	trace_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trace_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	trace_line.joint_mode = Line2D.LINE_JOINT_ROUND
	trace_line.z_index = 50
	trace_line.antialiased = true
	trace_line.visible = false
	add_child(trace_line)
	coin_label.text = "%d" % coins

func _clear_content() -> void:
	stage_scroll = null
	stage_touch_active = false
	is_dragging = false
	active_pointer = -1
	if chat_poll_timer != null:
		chat_poll_timer.stop()
	chat_messages_box = null
	chat_input = null
	chat_status_label = null
	trace_line.clear_points()
	trace_line.visible = false
	for child in content_box.get_children():
		child.queue_free()

func _add_section_art(asset_path: String, height: float = 104.0) -> void:
	if content_box == null or not is_instance_valid(content_box):
		return
	var art_panel := PanelContainer.new()
	art_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var art_style := StyleBoxFlat.new()
	art_style.bg_color = Color("#183d35")
	art_style.border_color = Color("#8d7548")
	art_style.set_border_width_all(1)
	art_style.set_corner_radius_all(18)
	art_panel.add_theme_stylebox_override("panel", art_style)
	content_box.add_child(art_panel)
	var art := TextureRect.new()
	art.texture = load("res://" + asset_path)
	art.custom_minimum_size = Vector2(0, height)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_panel.add_child(art)

func _show_auth(message: String = "") -> void:
	current_page = "auth"
	_clear_content()
	auth_signup_mode = false
	if exit_button != null:
		exit_button.visible = false
	if profile_button != null:
		profile_button.visible = false
	coin_panel.visible = false
	var auth_mascot := TextureRect.new()
	auth_mascot.texture = load("res://assets/characters/mascot.svg")
	auth_mascot.custom_minimum_size = Vector2(104, 104)
	auth_mascot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	auth_mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	auth_mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	auth_mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(auth_mascot)
	var heading := Label.new()
	heading.text = "خوش آمدی!"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)

	var intro_panel := _panel(Color("#8e7544"))
	content_box.add_child(intro_panel)
	var intro := Label.new()
	intro.text = "برای ذخیره دائمی پیشرفت، با حساب alishams.ir وارد شو یا یک حساب تازه بساز.\nمی‌توانی بدون ثبت‌نام هم به‌صورت مهمان بازی کنی."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.add_theme_color_override("font_color", CREAM)
	intro_panel.add_child(intro)
	var form := _panel()
	content_box.add_child(form)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 10)
	form.add_child(fields)

	auth_name_input = LineEdit.new()
	auth_name_input.placeholder_text = "نام نمایشی"
	auth_name_input.custom_minimum_size.y = 48
	auth_name_input.visible = false
	_style_input(auth_name_input)
	fields.add_child(auth_name_input)

	auth_email_input = LineEdit.new()
	auth_email_input.placeholder_text = "ایمیل حساب کاربری"
	auth_email_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	auth_email_input.custom_minimum_size.y = 48
	_style_input(auth_email_input)
	fields.add_child(auth_email_input)

	auth_password_input = LineEdit.new()
	auth_password_input.placeholder_text = "رمز عبور"
	auth_password_input.secret = true
	auth_password_input.custom_minimum_size.y = 48
	_style_input(auth_password_input)
	fields.add_child(auth_password_input)

	auth_login_button = _make_button("ورود به حساب", Color("#287c68"), CREAM)
	auth_login_button.disabled = startup_restore_in_progress
	auth_login_button.pressed.connect(_on_login_pressed)
	fields.add_child(auth_login_button)

	auth_mode_toggle_button = _make_button("ساخت حساب جدید", Color("#a77a35"), Color("#172b25"))
	auth_mode_toggle_button.disabled = startup_restore_in_progress
	auth_mode_toggle_button.pressed.connect(_toggle_signup_mode)
	fields.add_child(auth_mode_toggle_button)

	if CloudAccount.has_saved_session() and not startup_restore_in_progress:
		var retry_button := _make_button("تلاش دوباره برای ورود خودکار", Color("#385b75"), CREAM)
		retry_button.pressed.connect(_retry_saved_login)
		fields.add_child(retry_button)
	var guest_button := _make_button("ورود مهمان", Color("#294c43"), GOLD)
	guest_button.pressed.connect(_show_guest_warning)
	fields.add_child(guest_button)

	auth_status_label = Label.new()
	auth_status_label.text = message
	auth_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auth_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auth_status_label.add_theme_color_override("font_color", RED if not message.is_empty() else MUTED)
	content_box.add_child(auth_status_label)

func _retry_saved_login() -> void:
	startup_action_taken = true
	if auth_status_label != null:
		auth_status_label.text = "در حال بازیابی نشست ذخیره‌شده…"
		auth_status_label.add_theme_color_override("font_color", GOLD)
	var restored: bool = await CloudAccount.restore_session()
	if restored:
		await _enter_game()
	else:
		if not CloudAccount.has_saved_session():
			_show_auth("نشست ذخیره‌شده معتبر نیست. لطفاً دوباره وارد شو.")
		elif auth_status_label != null:
			auth_status_label.text = "ورود خودکار انجام نشد. اتصال اینترنت را بررسی کن یا دوباره تلاش کن."
			auth_status_label.add_theme_color_override("font_color", RED)

func _show_guest_warning() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.015, 0.055, 0.048, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 180
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 18
	center.offset_right = -18
	overlay.add_child(center)

	var card := _panel(GOLD)
	card.custom_minimum_size = Vector2(300, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 13)
	card.add_child(body)

	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/icons/profile.svg")
	emblem.custom_minimum_size = Vector2(52, 52)
	emblem.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(emblem)

	var title := Label.new()
	title.text = "ورود به‌صورت مهمان"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", GOLD)
	body.add_child(title)

	var description := Label.new()
	description.text = "پیشرفت و سکه‌ها فقط روی همین دستگاه ذخیره می‌شوند. با حذف داده‌های بازی ممکن است از بین بروند. برای نگهداری دائمی، با حساب alishams.ir وارد شو."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override("font_color", CREAM)
	body.add_child(description)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	var back := _make_button("بازگشت", PANEL_ALT, CREAM)
	back.pressed.connect(overlay.queue_free)
	actions.add_child(back)
	var proceed := _make_button("ادامه مهمان", Color("#287c68"), CREAM)
	proceed.pressed.connect(func():
		overlay.queue_free()
		_enter_guest()
	)
	actions.add_child(proceed)

	card.modulate.a = 0.0
	card.scale = Vector2(0.94, 0.94)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.18)
	tween.tween_property(card, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _toggle_signup_mode() -> void:
	auth_signup_mode = not auth_signup_mode
	auth_name_input.visible = auth_signup_mode
	auth_login_button.text = "ثبت‌نام و ساخت حساب" if auth_signup_mode else "ورود به حساب"
	auth_mode_toggle_button.text = "بازگشت به ورود" if auth_signup_mode else "ساخت حساب جدید"
	auth_status_label.text = "نام نمایشی را هم وارد کن." if auth_signup_mode else "ایمیل و رمز عبور حساب را وارد کن."
	auth_status_label.add_theme_color_override("font_color", MUTED)

func _on_login_pressed() -> void:
	startup_action_taken = true
	if auth_signup_mode:
		await _on_signup_pressed()
		return
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
	startup_action_taken = true
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
		var name_result: Dictionary = await CloudAccount.update_profile_name(auth_name_input.text.strip_edges())
		if name_result.get("ok", false):
			_apply_cloud_profile(name_result.get("profile", {}))
	else:
		auth_status_label.text = "حساب ساخته شد. ایمیل تأیید را بررسی کن، سپس با همان حساب وارد شو."
		auth_status_label.add_theme_color_override("font_color", GREEN)

func _apply_cloud_profile(profile: Dictionary) -> void:
	coins = int(profile.get("coins", coins))
	diamonds = int(profile.get("diamonds", diamonds))
	name_change_count = int(profile.get("name_change_count", name_change_count))
	var profile_name = profile.get("display_name", null)
	if profile_name != null and not str(profile_name).strip_edges().is_empty():
		display_name = str(profile_name)
	elif display_name.is_empty():
		display_name = CloudAccount.display_name if not CloudAccount.display_name.is_empty() else "بازیکن"
	daily_streak = int(profile.get("daily_streak", daily_streak))
	last_checkin_date = str(profile.get("last_checkin_date", last_checkin_date))
	var new_avatar_path = profile.get("avatar_path", avatar_path)
	avatar_path = "" if new_avatar_path == null else str(new_avatar_path)
	avatar_unlocked = bool(profile.get("avatar_unlocked", avatar_unlocked))
	equipped_frame_id = str(profile.get("equipped_frame_id", equipped_frame_id))
	wins = int(profile.get("wins", wins))
	losses = int(profile.get("losses", losses))
	chat_unlocked = not str(profile.get("chat_unlocked_at", "")).is_empty()
	cloud_current_level = int(profile.get("current_level", cloud_current_level))
	var remote_completed = profile.get("completed_levels", completed_levels)
	if remote_completed is Array:
		completed_levels = remote_completed.duplicate()
	_save()
	_update_controls()

func _show_map() -> void:
	current_page = "map"
	if duel_poll_timer != null:
		duel_poll_timer.stop()
	duel_mode = false
	duel_match_id = ""
	_clear_content()
	if exit_button != null:
		exit_button.visible = true
		exit_button.text = "خروج مهمان" if guest_mode else "خروج از حساب"
	if profile_button != null:
		profile_button.visible = true
	coin_panel.visible = true
	coin_label.text = "%d" % coins

	var heading := Label.new()
	heading.text = "نقشه مراحل"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", CREAM)
	content_box.add_child(heading)
	var greeting := Label.new()
	greeting.text = "سلام، %s! آماده‌ای؟" % display_name
	greeting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	greeting.add_theme_font_size_override("font_size", 16)
	greeting.add_theme_color_override("font_color", GOLD)
	content_box.add_child(greeting)
	var diamond_row := HBoxContainer.new()
	diamond_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diamond_row.add_theme_constant_override("separation", 7)
	var diamond_icon := TextureRect.new()
	diamond_icon.texture = load("res://assets/icons/diamond.svg")
	diamond_icon.custom_minimum_size = Vector2(25, 25)
	diamond_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	diamond_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	diamond_row.add_child(diamond_icon)
	var diamond_label := Label.new()
	diamond_label.text = "%d الماس" % diamonds
	diamond_label.add_theme_color_override("font_color", TEAL)
	diamond_label.add_theme_font_size_override("font_size", 15)
	diamond_row.add_child(diamond_label)
	content_box.add_child(diamond_row)
	var guide_panel := _panel(Color("#287c68"))
	guide_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(guide_panel)
	var guide_body := VBoxContainer.new()
	guide_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_body.add_theme_constant_override("separation", 6)
	guide_panel.add_child(guide_body)
	var guide_mascot := TextureRect.new()
	guide_mascot.texture = load("res://assets/characters/mascot.svg")
	guide_mascot.custom_minimum_size = Vector2(0, 76)
	guide_mascot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	guide_mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	guide_mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide_body.add_child(guide_mascot)
	var guide_text := Label.new()
	guide_text.text = "من راهنمای توام! هر ۲۰ مرحله یک سرزمین تازه منتظرته."
	guide_text.custom_minimum_size = Vector2(0, 42)
	guide_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	guide_text.add_theme_font_size_override("font_size", 14)
	guide_text.add_theme_color_override("font_color", CREAM)
	guide_body.add_child(guide_text)

	var map_art := TextureRect.new()
	map_art.texture = load("res://assets/backgrounds/wordlands.svg")
	map_art.custom_minimum_size = Vector2(0, 116)
	map_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(map_art)

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

	var social_row := HBoxContainer.new()
	social_row.add_theme_constant_override("separation", 7)
	content_box.add_child(social_row)
	var chat_nav := _make_button("چت عمومی", Color("#765a31"), CREAM)
	chat_nav.custom_minimum_size = Vector2(0, 44)
	chat_nav.pressed.connect(_show_global_chat)
	social_row.add_child(chat_nav)
	var shop_nav := _make_button("فروشگاه", Color("#245448"), CREAM)
	shop_nav.custom_minimum_size = Vector2(0, 44)
	shop_nav.pressed.connect(_show_cosmetic_shop)
	social_row.add_child(shop_nav)
	var ranks_nav := _make_button("رتبه‌بندی", Color("#294c43"), GOLD)
	ranks_nav.custom_minimum_size = Vector2(0, 44)
	ranks_nav.pressed.connect(_show_leaderboard)
	social_row.add_child(ranks_nav)
	var groups_nav := _make_button("گروه", Color("#385b75"), CREAM)
	groups_nav.custom_minimum_size = Vector2(0, 44)
	groups_nav.pressed.connect(_show_groups)
	social_row.add_child(groups_nav)
	var settings_nav := _make_button("تنظیمات", Color("#294c43"), GOLD)
	settings_nav.custom_minimum_size = Vector2(0, 44)
	settings_nav.pressed.connect(_show_settings)
	social_row.add_child(settings_nav)

	if cloud_current_level > levels.size():
		var finished := Label.new()
		finished.text = "همه مراحل فعلی را با موفقیت به پایان رساندی!\nمراحل تازه به‌زودی اضافه می‌شوند."
		finished.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		finished.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		finished.add_theme_font_size_override("font_size", 18)
		finished.add_theme_color_override("font_color", GOLD)
		content_box.add_child(finished)
		return

	stage_scroll = get_node_or_null("MainMargin/PageBox/ScreenContentScroll") as ScrollContainer
	var stage_list := VBoxContainer.new()
	stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_list.add_theme_constant_override("separation", 18)
	content_box.add_child(stage_list)

	var chapter_count := int(ceil(float(levels.size()) / 20.0))
	for chapter_index in range(chapter_count):
		var first_index := chapter_index * 20
		var last_index := mini(first_index + 20, levels.size())
		var first_level := int(levels[first_index].get("id", first_index + 1))
		var last_level := int(levels[last_index - 1].get("id", last_index))
		var chapter_panel := _panel(Color("#8e6b35"))
		chapter_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_list.add_child(chapter_panel)
		var chapter_box := VBoxContainer.new()
		chapter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chapter_box.add_theme_constant_override("separation", 10)
		chapter_panel.add_child(chapter_box)
		var chapter_banner := _build_chapter_banner(first_level)
		chapter_banner.custom_minimum_size = Vector2(0, 104)
		chapter_box.add_child(chapter_banner)
		var chapter_meta := Label.new()
		chapter_meta.text = "مراحل %d تا %d" % [first_level, last_level]
		chapter_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chapter_meta.add_theme_font_size_override("font_size", 13)
		chapter_meta.add_theme_color_override("font_color", MUTED)
		chapter_box.add_child(chapter_meta)

		var chapter_done := 0
		for stage_index in range(first_index, last_index):
			var stage_data: Dictionary = levels[stage_index]
			var stage_id := int(stage_data.get("id", stage_index + 1))
			if completed_levels.has(stage_id):
				chapter_done += 1
		var chapter_progress := ProgressBar.new()
		chapter_progress.min_value = 0
		chapter_progress.max_value = max(1, last_index - first_index)
		chapter_progress.value = chapter_done
		chapter_progress.show_percentage = false
		chapter_progress.custom_minimum_size.y = 8
		chapter_box.add_child(chapter_progress)
		var chapter_count_label := Label.new()
		chapter_count_label.text = "%d از %d مرحله تکمیل شده" % [chapter_done, last_index - first_index]
		chapter_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chapter_count_label.add_theme_font_size_override("font_size", 12)
		chapter_count_label.add_theme_color_override("font_color", GOLD)
		chapter_box.add_child(chapter_count_label)

		var stage_grid := GridContainer.new()
		stage_grid.columns = 4
		stage_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_grid.add_theme_constant_override("h_separation", 8)
		stage_grid.add_theme_constant_override("v_separation", 8)
		chapter_box.add_child(stage_grid)
		for stage_index in range(first_index, last_index):
			var stage_data: Dictionary = levels[stage_index]
			var stage_id := int(stage_data.get("id", stage_index + 1))
			var is_done := completed_levels.has(stage_id)
			var is_open := stage_index == 0 or completed_levels.has(int(levels[stage_index - 1].get("id", stage_index)))
			var is_current := stage_index == cloud_current_level - 1
			var stage_button := Button.new()
			stage_button.custom_minimum_size = Vector2(0, 62)
			stage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stage_button.text = "✓" if is_done else "%02d" % stage_id
			stage_button.disabled = not is_open or is_done or not is_current
			stage_button.add_theme_font_size_override("font_size", 18)
			stage_button.add_theme_color_override("font_color", Color("#fff4d0") if is_current else (GOLD if is_done else (CREAM if is_open else MUTED)))
			stage_button.add_theme_color_override("font_disabled_color", GOLD if is_done else Color("#71837d"))
			var node_style := StyleBoxFlat.new()
			node_style.bg_color = Color("#246d59") if is_current else (Color("#315f4f") if is_done else (Color("#183b34") if is_open else Color("#142d29")))
			node_style.border_color = GOLD if is_current or is_done else (TEAL if is_open else Color("#29443d"))
			node_style.set_border_width_all(2 if is_current else 1)
			node_style.set_corner_radius_all(18)
			node_style.shadow_color = Color(0, 0, 0, 0.20)
			node_style.shadow_size = 4 if is_current else 1
			node_style.content_margin_left = 2
			node_style.content_margin_right = 2
			stage_button.add_theme_stylebox_override("normal", node_style)
			var node_hover := node_style.duplicate()
			node_hover.bg_color = node_style.bg_color.lightened(0.12)
			stage_button.add_theme_stylebox_override("hover", node_hover)
			stage_button.add_theme_stylebox_override("disabled", node_style)
			stage_button.pressed.connect(_open_level.bind(stage_index))
			stage_grid.add_child(stage_button)

func _show_settings() -> void:
	current_page = "settings"
	_clear_content()
	var heading := Label.new()
	heading.text = "تنظیمات"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var sound_panel := _panel(TEAL)
	content_box.add_child(sound_panel)
	var sound_row := HBoxContainer.new()
	sound_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sound_row.add_theme_constant_override("separation", 12)
	sound_panel.add_child(sound_row)
	var sound_label := Label.new()
	sound_label.text = "صدای بازی"
	sound_label.add_theme_font_size_override("font_size", 17)
	sound_label.add_theme_color_override("font_color", CREAM)
	sound_row.add_child(sound_label)
	var sound_toggle := CheckButton.new()
	sound_toggle.button_pressed = sound_enabled
	sound_toggle.toggled.connect(func(enabled: bool):
		sound_enabled = enabled
		_save()
		if enabled:
			_play_sfx("select")
	)
	sound_row.add_child(sound_toggle)
	var privacy := _make_button("حریم خصوصی و اطلاعات کاربران", Color("#245448"), CREAM)
	privacy.pressed.connect(_show_privacy_info)
	content_box.add_child(privacy)
	var faq := _make_button("پرسش‌های متداول", Color("#385b75"), CREAM)
	faq.pressed.connect(_show_game_faq)
	content_box.add_child(faq)
	var coins_button := _make_button("درخواست خرید سکه · هر ۱۰۰۰ سکه ۸٬۹۰۰ تومان", Color("#765a31"), CREAM)
	coins_button.pressed.connect(func(): OS.shell_open("https://alishams.ir/game-coins.html"))
	content_box.add_child(coins_button)
	var diamond_panel := _panel(Color("#55c6b5"))
	content_box.add_child(diamond_panel)
	var diamond_text := Label.new()
	diamond_text.text = "الماس‌های تو: %d\nبا هر فصل کامل، یک الماس می‌گیری. اولین تغییر نام رایگان است و دفعات بعد یک الماس هزینه دارد." % diamonds
	diamond_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diamond_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diamond_text.add_theme_color_override("font_color", CREAM)
	diamond_panel.add_child(diamond_text)
	var delete_button := _make_button("حذف حساب بازی و اطلاعات آن", Color("#713e3b"), CREAM)
	delete_button.pressed.connect(_confirm_delete_game_account)
	content_box.add_child(delete_button)
	var note := Label.new()
	note.text = "حذف حساب بازی، اطلاعات بازی و تصاویر پروفایل را پاک می‌کند؛ حساب ورود سایت علی شمس حذف نمی‌شود."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", MUTED)
	content_box.add_child(note)
	var back := _make_button("بازگشت", PANEL_ALT, CREAM)
	back.pressed.connect(_show_map)
	content_box.add_child(back)

func _show_privacy_info() -> void:
	current_page = "privacy"
	_clear_content()
	var heading := Label.new()
	heading.text = "حریم خصوصی"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var body := Label.new()
	body.text = "برای حساب بازی، شناسه کاربر، نام نمایشی، پیشرفت مراحل، موجودی سکه و الماس، آمار رقابت و پیام‌های ارسالی ذخیره می‌شود.\n\nاطلاعات حساب برای اجرای امکانات آنلاین، رتبه‌بندی، گروه‌ها و همگام‌سازی پیشرفت استفاده می‌شود. رمز عبور در بازی ذخیره نمی‌شود و ورود از طریق سرویس احراز هویت انجام می‌گیرد.\n\nتصویر پروفایل در فضای ذخیره‌سازی اختصاصی بازی نگهداری می‌شود. با حذف حساب بازی، پیشرفت، پیام‌ها و تصویر پروفایل حذف می‌شوند. درخواست‌های خرید و رسیدهای مالی برای پیگیری و سوابق مالی نگهداری خواهند شد. حساب ورود سایت علی شمس مستقل باقی می‌ماند."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", CREAM)
	var panel := _panel()
	panel.add_child(body)
	content_box.add_child(panel)
	var back := _make_button("بازگشت به تنظیمات", PANEL_ALT, CREAM)
	back.pressed.connect(_show_settings)
	content_box.add_child(back)

func _show_game_faq() -> void:
	current_page = "faq"
	_clear_content()
	var heading := Label.new()
	heading.text = "پرسش‌های متداول"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var questions := [
		["چطور الماس بگیرم؟", "با تکمیل هر فصل ۲۰ مرحله‌ای، یک الماس به حسابت اضافه می‌شود."],
		["تغییر نام چقدر هزینه دارد؟", "اولین بار رایگان است. از بار دوم، هر بار یک الماس مصرف می‌شود."],
		["سکه را چطور بخرم؟", "از تنظیمات وارد صفحه خرید سکه در وب‌سایت علی شمس شو. هر ۱۰۰۰ سکه ۸٬۹۰۰ تومان است."],
		["پیشرفت مهمان ذخیره می‌شود؟", "بله، روی همان دستگاه ذخیره می‌شود؛ اما به حساب آنلاین منتقل نمی‌شود."],
		["اگر بازی را حذف کنم چه می‌شود؟", "پیشرفت مهمان ممکن است از بین برود. برای همگام‌سازی دائمی از حساب کاربری استفاده کن."]
	]
	for item in questions:
		var panel := _panel(TEAL)
		content_box.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 5)
		panel.add_child(box)
		var q := Label.new()
		q.text = item[0]
		q.add_theme_color_override("font_color", GOLD)
		q.add_theme_font_size_override("font_size", 16)
		box.add_child(q)
		var a := Label.new()
		a.text = item[1]
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		a.add_theme_color_override("font_color", CREAM)
		box.add_child(a)
	var back := _make_button("بازگشت به تنظیمات", PANEL_ALT, CREAM)
	back.pressed.connect(_show_settings)
	content_box.add_child(back)

func _confirm_delete_game_account() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "حذف حساب بازی"
	dialog.dialog_text = "تمام پیشرفت، سکه‌ها، الماس‌ها، پیام‌ها و تصاویر پروفایل بازی حذف می‌شوند. حساب ورود alishams.ir باقی می‌ماند. ادامه می‌دهی؟"
	dialog.ok_button_text = "حذف دائمی اطلاعات بازی"
	dialog.cancel_button_text = "انصراف"
	add_child(dialog)
	dialog.confirmed.connect(func():
		if guest_mode:
			var save_file := ProjectSettings.globalize_path("user://baladi_save_guest.cfg")
			if FileAccess.file_exists("user://baladi_save_guest.cfg"):
				DirAccess.remove_absolute(save_file)
			coins = 100
			diamonds = 0
			name_change_count = 0
			level_index = 0
			cloud_current_level = 1
			display_name = "بازیکن"
			completed_levels.clear()
			level_solved.clear()
			_show_auth("اطلاعات مهمان این دستگاه حذف شد.")
		else:
			var result: Dictionary = await CloudAccount.delete_account()
			if result.get("ok", false):
				guest_mode = true
				coins = 100
				diamonds = 0
				name_change_count = 0
				level_index = 0
				cloud_current_level = 1
				display_name = "بازیکن"
				completed_levels.clear()
				level_solved.clear()
				_show_auth("اطلاعات بازی حذف شد. برای شروع دوباره وارد شو.")
			else:
				_show_settings()
				_set_status(str(result.get("error", "حذف اطلاعات بازی انجام نشد.")), RED)
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.popup_centered()

func _show_profile() -> void:
	current_page = "profile"
	_clear_content()
	stage_scroll = get_node_or_null("MainMargin/PageBox/ScreenContentScroll") as ScrollContainer
	if profile_button != null:
		profile_button.visible = true

	var heading := Label.new()
	heading.text = "پروفایل بازیکن"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)

	var identity := _panel(GOLD)
	content_box.add_child(identity)
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 14)
	identity.add_child(identity_row)
	var avatar := _build_avatar_widget(avatar_path, equipped_frame_id, 76)
	identity_row.add_child(avatar)
	var identity_info := VBoxContainer.new()
	identity_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_info.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_info.add_theme_constant_override("separation", 4)
	identity_row.add_child(identity_info)
	var player_name := Label.new()
	player_name.text = display_name
	player_name.add_theme_font_size_override("font_size", 22)
	player_name.add_theme_color_override("font_color", CREAM)
	identity_info.add_child(player_name)
	var player_tag := Label.new()
	player_tag.text = "ماجراجوی واژه‌ها"
	player_tag.add_theme_font_size_override("font_size", 13)
	player_tag.add_theme_color_override("font_color", GOLD)
	identity_info.add_child(player_tag)

	var name_title := Label.new()
	name_title.text = "نام نمایشی"
	name_title.add_theme_color_override("font_color", MUTED)
	content_box.add_child(name_title)
	profile_name_input = LineEdit.new()
	profile_name_input.text = display_name
	profile_name_input.placeholder_text = "نامی که در بازی نمایش داده می‌شود"
	profile_name_input.custom_minimum_size.y = 50
	_style_input(profile_name_input)
	content_box.add_child(profile_name_input)
	var rename_label := "ذخیره نام پروفایل · رایگان" if name_change_count == 0 else "تغییر نام · ۱ الماس"
	profile_rename_button = _make_button(rename_label, Color("#287c68"), CREAM)
	profile_rename_button.pressed.connect(_save_profile_name)
	content_box.add_child(profile_rename_button)

	var words_total := 0
	for value in level_solved.values():
		if value is Array:
			words_total += value.size()
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("h_separation", 9)
	stats_grid.add_theme_constant_override("v_separation", 9)
	content_box.add_child(stats_grid)
	_add_profile_stat(stats_grid, "مرحله فعلی", "%d / %d" % [cloud_current_level, levels.size()], GOLD)
	_add_profile_stat(stats_grid, "مراحل کامل‌شده", str(completed_levels.size()), GREEN)
	_add_profile_stat(stats_grid, "واژه‌های پیدا‌شده", str(words_total), TEAL)
	_add_profile_stat(stats_grid, "موجودی سکه", str(coins), GOLD)
	_add_profile_stat(stats_grid, "موجودی الماس", str(diamonds), TEAL)
	_add_profile_stat(stats_grid, "برد دونفره", str(wins), GREEN)
	_add_profile_stat(stats_grid, "باخت دونفره", str(losses), RED)

	var streak_panel := _panel(Color("#a77a35"))
	content_box.add_child(streak_panel)
	var streak_box := VBoxContainer.new()
	streak_box.add_theme_constant_override("separation", 5)
	streak_panel.add_child(streak_box)
	var streak_title := Label.new()
	streak_title.text = "زنجیره حضور روزانه"
	streak_title.add_theme_font_size_override("font_size", 17)
	streak_title.add_theme_color_override("font_color", GOLD)
	streak_box.add_child(streak_title)
	var cycle_day := ((daily_streak - 1) % 20) + 1 if daily_streak > 0 else 0
	var streak_value := Label.new()
	streak_value.text = "%d / 20 روز متوالی" % cycle_day
	streak_value.add_theme_font_size_override("font_size", 20)
	streak_value.add_theme_color_override("font_color", CREAM)
	streak_box.add_child(streak_value)
	var reward_by_day := {1: 20, 4: 80, 6: 180, 10: 250, 15: 500, 20: 1000}
	var next_day := (cycle_day % 20) + 1
	var next_reward := int(reward_by_day.get(next_day, 0))
	var streak_hint := Label.new()
	streak_hint.text = "پاداش روز %d: %d سکه" % [next_day, next_reward] if next_reward > 0 else "فقط با ورود هر روز، زنجیره را حفظ کن."
	streak_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	streak_hint.add_theme_color_override("font_color", MUTED)
	streak_box.add_child(streak_hint)

	if avatar_unlocked:
		var change_avatar := _make_button("انتخاب یا تغییر عکس پروفایل", Color("#765a31"), CREAM)
		change_avatar.pressed.connect(_pick_avatar_from_gallery)
		content_box.add_child(change_avatar)
	var settings_button := _make_button("تنظیمات بازی", Color("#294c43"), GOLD)
	settings_button.pressed.connect(_show_settings)
	content_box.add_child(settings_button)
	var shop_button := _make_button("فروشگاه قاب‌ها و تصویر پروفایل", Color("#765a31"), CREAM)
	shop_button.pressed.connect(_show_cosmetic_shop)
	content_box.add_child(shop_button)
	var leaderboard_button := _make_button("جدول رتبه‌بندی بازیکنان", Color("#245448"), GOLD)
	leaderboard_button.pressed.connect(_show_leaderboard)
	content_box.add_child(leaderboard_button)
	var duel_invites_button := _make_button("درخواست‌های بازی دونفره", Color("#385b75"), CREAM)
	duel_invites_button.pressed.connect(_show_duel_invites)
	content_box.add_child(duel_invites_button)
	var resume_duel_button := _make_button("ادامه مسابقه فعال", Color("#287c68"), CREAM)
	resume_duel_button.pressed.connect(_resume_active_duel)
	content_box.add_child(resume_duel_button)

	profile_status_label = Label.new()
	profile_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	profile_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_status_label.add_theme_color_override("font_color", MUTED)
	content_box.add_child(profile_status_label)
	var back := _make_button("بازگشت به نقشه مراحل", Color("#294c43"), CREAM)
	back.pressed.connect(_show_map)
	content_box.add_child(back)

func _current_letters() -> Array:
	if duel_mode:
		return duel_current_letters
	return levels[level_index].get("letters", [])

func _show_duel_game(match_id: String) -> void:
	current_page = "duel_game"
	duel_mode = true
	duel_match_id = match_id
	await _refresh_duel_round()
	if duel_mode:
		_show_game()
		if duel_poll_timer == null:
			duel_poll_timer = Timer.new()
			duel_poll_timer.wait_time = 2.5
			duel_poll_timer.timeout.connect(_poll_duel_status)
			add_child(duel_poll_timer)
		duel_poll_timer.start()

func _refresh_duel_round() -> void:
	var result: Dictionary = await CloudAccount.get_duel_state(duel_match_id)
	if not result.get("ok", false):
		duel_mode = false
		_set_status(str(result.get("error", "وضعیت مسابقه دریافت نشد.")), RED)
		_show_map()
		return
	var state: Dictionary = result.get("state", {})
	_apply_cloud_profile(result.get("profile", {}))
	if str(state.get("status", "")) == "completed":
		_show_duel_result(str(state.get("winner_id", "")), int(state.get("winner_elapsed_ms", 0)))
		return
	duel_round_number = int(state.get("current_round", 1))
	duel_current_letters = state.get("letters", [])
	duel_answer_count = int(state.get("answer_count", 0))
	duel_found_words = state.get("found_words", [])
	if level_label != null and is_instance_valid(level_label):
		level_label.text = "رقابت %02d از ۱۰" % duel_round_number
	if subtitle_label != null and is_instance_valid(subtitle_label):
		subtitle_label.text = "مرحله تصادفی · همه واژه‌ها را پیدا کن"
	if board_box != null and is_instance_valid(board_box):
		_render_board()
	if letters_grid != null and is_instance_valid(letters_grid):
		_render_letters()

func _poll_duel_status() -> void:
	if not duel_mode or duel_poll_busy or duel_match_id.is_empty():
		return
	duel_poll_busy = true
	var result: Dictionary = await CloudAccount.get_duel_state(duel_match_id)
	if result.get("ok", false):
		_apply_cloud_profile(result.get("profile", {}))
		var state: Dictionary = result.get("state", {})
		if str(state.get("status", "")) == "completed":
			_show_duel_result(str(state.get("winner_id", "")), int(state.get("winner_elapsed_ms", 0)))
	duel_poll_busy = false

func _show_duel_result(winner_id: String, elapsed_ms: int) -> void:
	current_page = "duel_result"
	if duel_poll_timer != null:
		duel_poll_timer.stop()
	duel_mode = false
	_clear_content()
	var won := winner_id == CloudAccount.user_id
	var result_art := TextureRect.new()
	result_art.texture = load("res://assets/rewards/treasure-chest.svg") if won else load("res://assets/characters/mascot.svg")
	result_art.custom_minimum_size = Vector2(128, 92)
	result_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_box.add_child(result_art)
	var heading := Label.new()
	heading.text = "پیروزی در رقابت!" if won else "این بار حریف برنده شد"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", GOLD if won else RED)
	content_box.add_child(heading)
	var detail := Label.new()
	detail.text = "زمان ثبت‌شده برنده: %.1f ثانیه" % (float(elapsed_ms) / 1000.0)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 18)
	detail.add_theme_color_override("font_color", CREAM)
	content_box.add_child(detail)
	var record := Label.new()
	record.text = "تعداد بردها: %d  ·  تعداد باخت‌ها: %d" % [wins, losses]
	record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record.add_theme_color_override("font_color", MUTED)
	content_box.add_child(record)
	var back := _make_button("بازگشت به نقشه", Color("#287c68"), CREAM)
	back.pressed.connect(_show_map)
	content_box.add_child(back)

func _leave_duel_to_map() -> void:
	duel_mode = false
	duel_match_id = ""
	_show_map()

func _send_duel_invite_to(target_user_id: String) -> void:
	if guest_mode or target_user_id.is_empty() or target_user_id == CloudAccount.user_id:
		return
	var result: Dictionary = await CloudAccount.send_duel_invite(target_user_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ارسال دعوت مسابقه انجام نشد.")), RED)
		return
	_set_status("دعوت مسابقهٔ ۱۰مرحله‌ای ارسال شد.", GREEN)

func _resume_active_duel() -> void:
	var result: Dictionary = await CloudAccount.get_active_duel()
	if not result.get("ok", false):
		_set_status(str(result.get("error", "مسابقه فعال پیدا نشد.")), RED)
		return
	var match_id := str(result.get("match_id", ""))
	if match_id.is_empty():
		_set_status("در حال حاضر مسابقه فعالی نداری.", MUTED)
		return
	_show_duel_game(match_id)

func _show_duel_invites() -> void:
	current_page = "duel_invites"
	_clear_content()
	_add_section_art("assets/backgrounds/letter-wheel.svg", 92)
	var heading := Label.new()
	heading.text = "درخواست‌های مسابقه"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var result: Dictionary = await CloudAccount.get_duel_invites()
	if not result.get("ok", false):
		_set_status(str(result.get("error", "درخواست‌ها بارگذاری نشدند.")), RED)
	else:
		var invites: Array = result.get("invites", [])
		if invites.is_empty():
			var empty := Label.new()
			empty.text = "در حال حاضر دعوت مسابقه‌ای نداری."
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.add_theme_color_override("font_color", MUTED)
			content_box.add_child(empty)
		for invite in invites:
			var invite_id := str(invite.get("id", ""))
			var sender: Dictionary = invite.get("sender", {})
			var card := _panel(GOLD)
			content_box.add_child(card)
			var body := VBoxContainer.new()
			body.add_theme_constant_override("separation", 7)
			card.add_child(body)
			var name := Label.new()
			name.text = "%s تو را به رقابت دعوت کرده است." % _safe_player_name(sender.get("display_name", null))
			name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name.add_theme_color_override("font_color", CREAM)
			body.add_child(name)
			var accept := _make_button("پذیرش و شروع مسابقه", Color("#287c68"), CREAM)
			accept.pressed.connect(func(): _accept_duel_invite(invite_id))
			body.add_child(accept)
			var decline := _make_button("رد دعوت", Color("#713e3b"), CREAM)
			decline.pressed.connect(func(): _decline_duel_invite(invite_id))
			body.add_child(decline)
	var back := _make_button("بازگشت به پروفایل", PANEL_ALT, CREAM)
	back.pressed.connect(_show_profile)
	content_box.add_child(back)

func _accept_duel_invite(invite_id: String) -> void:
	var result: Dictionary = await CloudAccount.accept_duel_invite(invite_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "شروع مسابقه انجام نشد.")), RED)
		return
	_show_duel_game(str(result.get("match_id", "")))

func _decline_duel_invite(invite_id: String) -> void:
	var result: Dictionary = await CloudAccount.decline_duel_invite(invite_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "رد دعوت انجام نشد.")), RED)
		return
	_show_duel_invites()

func _show_global_chat() -> void:
	current_page = "global_chat"
	active_group_chat_id = ""
	active_group_chat_name = ""
	_clear_content()
	_add_section_art("assets/backgrounds/ambient.svg", 92)
	var heading := Label.new()
	heading.text = "گفت‌وگوی بازیکنان"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	if guest_mode:
		var guest_note := Label.new()
		guest_note.text = "برای حضور در گفت‌وگوی عمومی، با حساب کاربری وارد شو."
		guest_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		guest_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		guest_note.add_theme_color_override("font_color", MUTED)
		content_box.add_child(guest_note)
		var guest_back := _make_button("بازگشت به نقشه", PANEL_ALT, CREAM)
		guest_back.pressed.connect(_show_map)
		content_box.add_child(guest_back)
		return
	if not chat_unlocked:
		var lock_panel := _panel(GOLD)
		content_box.add_child(lock_panel)
		var lock_body := VBoxContainer.new()
		lock_body.add_theme_constant_override("separation", 10)
		lock_panel.add_child(lock_body)
		var lock_title := Label.new()
		lock_title.text = "دروازه گفت‌وگوی بلدی؟"
		lock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_title.add_theme_font_size_override("font_size", 20)
		lock_title.add_theme_color_override("font_color", GOLD)
		lock_body.add_child(lock_title)
		var lock_text := Label.new()
		lock_text.text = "با پرداخت یک‌بارهٔ ۱۸٬۰۰۰ سکه، چت عمومی برای همیشه برای حسابت فعال می‌شود."
		lock_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_text.add_theme_color_override("font_color", CREAM)
		lock_body.add_child(lock_text)
		var unlock := _make_button("بازکردن دائمی چت · ۱۸٬۰۰۰ سکه", Color("#a77a35"), CREAM)
		unlock.pressed.connect(_unlock_global_chat)
		lock_body.add_child(unlock)
		var sticker_shop := _make_button("فروشگاه استیکرها", PANEL_ALT, GOLD)
		sticker_shop.pressed.connect(_show_sticker_picker)
		lock_body.add_child(sticker_shop)
	else:
		var messages_scroll := ScrollContainer.new()
		messages_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		messages_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		messages_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_box.add_child(messages_scroll)
		chat_messages_box = VBoxContainer.new()
		chat_messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chat_messages_box.add_theme_constant_override("separation", 7)
		messages_scroll.add_child(chat_messages_box)
		var composer := HBoxContainer.new()
		composer.add_theme_constant_override("separation", 6)
		content_box.add_child(composer)
		chat_input = LineEdit.new()
		chat_input.placeholder_text = "پیامت را بنویس..."
		chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chat_input.custom_minimum_size.y = 48
		_style_input(chat_input)
		composer.add_child(chat_input)
		var send := _make_button("ارسال", Color("#287c68"), CREAM)
		send.custom_minimum_size = Vector2(76, 48)
		send.size_flags_horizontal = Control.SIZE_SHRINK_END
		send.pressed.connect(_send_global_chat_message)
		composer.add_child(send)
		var sticker_button := _make_button("استیکرها", Color("#765a31"), CREAM)
		sticker_button.pressed.connect(_show_sticker_picker)
		content_box.add_child(sticker_button)
		chat_status_label = Label.new()
		chat_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chat_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		chat_status_label.add_theme_color_override("font_color", MUTED)
		content_box.add_child(chat_status_label)
		await _refresh_global_chat()
		if chat_poll_timer == null:
			chat_poll_timer = Timer.new()
			chat_poll_timer.wait_time = 5.0
			chat_poll_timer.timeout.connect(_refresh_global_chat)
			add_child(chat_poll_timer)
		chat_poll_timer.start()
	var back := _make_button("بازگشت به نقشه مراحل", PANEL_ALT, CREAM)
	back.pressed.connect(_show_map)
	content_box.add_child(back)

func _unlock_global_chat() -> void:
	if coins < 18000:
		_set_status("برای بازکردن چت، ۱۸٬۰۰۰ سکه لازم داری.", RED)
		return
	var result: Dictionary = await CloudAccount.unlock_global_chat()
	if not result.get("ok", false):
		_set_status(str(result.get("error", "بازکردن چت انجام نشد.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	_animate_coin_reward(-18000)
	_show_global_chat()

func _refresh_global_chat() -> void:
	if chat_poll_busy or chat_messages_box == null or not is_instance_valid(chat_messages_box):
		return
	chat_poll_busy = true
	var result: Dictionary
	if active_group_chat_id.is_empty():
		result = await CloudAccount.get_global_chat_messages()
	else:
		result = await CloudAccount.get_group_chat_messages(active_group_chat_id)
	if result.get("ok", false) and chat_messages_box != null and is_instance_valid(chat_messages_box):
		for child in chat_messages_box.get_children():
			child.queue_free()
		for message in result.get("messages", []):
			var card := _panel(TEAL if str(message.get("user_id", "")) == CloudAccount.user_id else Color("#456b5b"))
			chat_messages_box.add_child(card)
			var body := VBoxContainer.new()
			body.add_theme_constant_override("separation", 3)
			card.add_child(body)
			var player: Dictionary = message.get("player", {})
			var player_id := str(message.get("user_id", ""))
			var name_label := _make_button(_safe_player_name(player.get("display_name", null)), Color("#294c43"), GOLD)
			name_label.custom_minimum_size = Vector2(0, 34)
			name_label.add_theme_font_size_override("font_size", 12)
			if player_id == CloudAccount.user_id:
				name_label.disabled = true
			else:
				name_label.pressed.connect(func(): _show_public_profile(player_id))
			body.add_child(name_label)
			var sticker_id := str(message.get("sticker_id", ""))
			if not sticker_id.is_empty():
				var sticker_art := TextureRect.new()
				var sticker_file := sticker_id.trim_prefix("sticker_")
				sticker_art.texture = load("res://assets/stickers/%s.svg" % sticker_file)
				sticker_art.custom_minimum_size = Vector2(72, 72)
				sticker_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				sticker_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				body.add_child(sticker_art)
			else:
				var message_label := Label.new()
				message_label.text = str(message.get("body", ""))
				message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				message_label.add_theme_color_override("font_color", CREAM)
				body.add_child(message_label)
			if not active_group_chat_id.is_empty() and bool(message.get("is_pinned", false)):
				var pinned_label := Label.new()
				pinned_label.text = "پیام سنجاق‌شده"
				pinned_label.add_theme_color_override("font_color", GOLD)
				body.add_child(pinned_label)
			if not active_group_chat_id.is_empty() and active_group_role in ["veteran", "deputy", "leader"]:
				var pin_button := _make_button("برداشتن سنجاق" if bool(message.get("is_pinned", false)) else "سنجاق پیام", Color("#765a31"), CREAM)
				var group_message_id := int(message.get("id", 0))
				var should_pin := not bool(message.get("is_pinned", false))
				pin_button.pressed.connect(func(): _toggle_group_message_pin(active_group_chat_id, group_message_id, should_pin))
				body.add_child(pin_button)
	elif not result.get("ok", false) and chat_status_label != null and is_instance_valid(chat_status_label):
		chat_status_label.text = str(result.get("error", "دریافت پیام‌ها انجام نشد."))
	chat_poll_busy = false

func _toggle_group_message_pin(group_id: String, message_id: int, pinned: bool) -> void:
	var result: Dictionary = await CloudAccount.pin_group_chat_message(group_id, message_id, pinned)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "تغییر وضعیت پیام انجام نشد.")), RED)
		return
	await _refresh_global_chat()

func _send_global_chat_message() -> void:
	if chat_input == null or not is_instance_valid(chat_input):
		return
	var message := chat_input.text.strip_edges()
	if message.is_empty():
		return
	var result: Dictionary
	if active_group_chat_id.is_empty():
		result = await CloudAccount.send_global_chat_message(message)
	else:
		result = await CloudAccount.send_group_chat_message(active_group_chat_id, message)
	if not result.get("ok", false):
		if chat_status_label != null and is_instance_valid(chat_status_label):
			chat_status_label.text = str(result.get("error", "ارسال پیام انجام نشد."))
		return
	chat_input.clear()
	await _refresh_global_chat()

func _show_sticker_picker() -> void:
	current_page = "sticker_picker"
	_clear_content()
	var heading := Label.new()
	heading.text = "گالری استیکرهای بلدی؟"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	if guest_mode:
		_set_status("برای خرید یا ارسال استیکر، وارد حساب کاربری شو.", GOLD)
	else:
		var result: Dictionary = await CloudAccount.get_cosmetics_catalog()
		if result.get("ok", false):
			var owned: Dictionary = {}
			for entry in result.get("owned", []):
				owned[str(entry.get("cosmetic_id", ""))] = true
			for item in result.get("catalog", []):
				if str(item.get("kind", "")) != "sticker":
					continue
				var sticker_id := str(item.get("id", ""))
				var card := _panel(GOLD)
				content_box.add_child(card)
				var title := Label.new()
				title.text = str(item.get("display_name", "استیکر"))
				title.add_theme_color_override("font_color", CREAM)
				card.add_child(title)
				var sticker_art := TextureRect.new()
				sticker_art.texture = load("res://" + str(item.get("asset_path", "")))
				sticker_art.custom_minimum_size = Vector2(104, 104)
				sticker_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				sticker_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				sticker_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				card.add_child(sticker_art)
				var can_send_sticker := not active_group_chat_id.is_empty() or chat_unlocked
				var action_text := "ارسال استیکر" if owned.has(sticker_id) and can_send_sticker else ("برای ارسال، چت را باز کن" if owned.has(sticker_id) else "خرید · %d سکه" % int(item.get("price_coins", 0)))
				var action := _make_button(action_text, Color("#765a31"), CREAM)
				action.disabled = owned.has(sticker_id) and not can_send_sticker
				action.pressed.connect(func():
					if owned.has(sticker_id):
						_send_global_chat_sticker(sticker_id)
					else:
						_purchase_sticker(sticker_id)
				)
				card.add_child(action)
		else:
			_set_status(str(result.get("error", "فروشگاه استیکر بارگذاری نشد.")), RED)
	var back := _make_button("بازگشت به چت", PANEL_ALT, CREAM)
	if active_group_chat_id.is_empty():
		back.pressed.connect(_show_global_chat)
	else:
		back.pressed.connect(func(): _show_group_chat(active_group_chat_id, active_group_chat_name))
	content_box.add_child(back)

func _purchase_sticker(sticker_id: String) -> void:
	var result: Dictionary = await CloudAccount.purchase_cosmetic(sticker_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "خرید استیکر انجام نشد.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	_show_sticker_picker()

func _send_global_chat_sticker(sticker_id: String) -> void:
	var result: Dictionary
	if active_group_chat_id.is_empty():
		result = await CloudAccount.send_global_chat_sticker(sticker_id)
	else:
		result = await CloudAccount.send_group_chat_sticker(active_group_chat_id, sticker_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ارسال استیکر انجام نشد.")), RED)
		return
	if active_group_chat_id.is_empty():
		_show_global_chat()
	else:
		_show_group_chat(active_group_chat_id, active_group_chat_name)

func _show_groups() -> void:
	current_page = "groups"
	active_group_chat_id = ""
	active_group_chat_name = ""
	active_group_role = ""
	_clear_content()
	_add_section_art("assets/backgrounds/chapter-caravanserai.svg", 92)
	var heading := Label.new()
	heading.text = "باشگاه گروه‌ها"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	if guest_mode:
		var note := Label.new()
		note.text = "برای ساخت گروه یا عضویت در گروه‌ها، وارد حساب کاربری شو."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", MUTED)
		content_box.add_child(note)
	else:
		var mine: Dictionary = await CloudAccount.get_my_group()
		if mine.get("ok", false) and mine.get("group", null) != null:
			_render_my_group(mine.get("group", {}), mine.get("members", []))
		else:
			_render_group_discovery()
	var back := _make_button("بازگشت به نقشه", PANEL_ALT, CREAM)
	back.pressed.connect(_show_map)
	content_box.add_child(back)

func _render_group_discovery() -> void:
	var create_panel := _panel(GOLD)
	content_box.add_child(create_panel)
	var create_box := VBoxContainer.new()
	create_box.add_theme_constant_override("separation", 7)
	create_panel.add_child(create_box)
	var create_title := Label.new()
	create_title.text = "ساخت گروه جدید"
	create_title.add_theme_font_size_override("font_size", 18)
	create_title.add_theme_color_override("font_color", GOLD)
	create_box.add_child(create_title)
	group_name_input = LineEdit.new()
	group_name_input.placeholder_text = "نام گروه، ۳ تا ۲۸ نویسه"
	group_name_input.custom_minimum_size.y = 46
	_style_input(group_name_input)
	create_box.add_child(group_name_input)
	group_description_input = LineEdit.new()
	group_description_input.placeholder_text = "توضیح کوتاه گروه (اختیاری)"
	group_description_input.custom_minimum_size.y = 46
	_style_input(group_description_input)
	create_box.add_child(group_description_input)
	var create_button := _make_button("ساخت گروه · رایگان", Color("#287c68"), CREAM)
	create_button.pressed.connect(_create_group_from_form)
	create_box.add_child(create_button)

	var list_title := Label.new()
	list_title.text = "گروه‌های قابل عضویت"
	list_title.add_theme_font_size_override("font_size", 19)
	list_title.add_theme_color_override("font_color", GOLD)
	content_box.add_child(list_title)
	var result: Dictionary = await CloudAccount.fetch_groups()
	if not result.get("ok", false):
		_set_status(str(result.get("error", "فهرست گروه‌ها بارگذاری نشد.")), RED)
		return
	for group in result.get("groups", []):
		var card := _panel(TEAL)
		content_box.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 5)
		card.add_child(body)
		var title := Label.new()
		title.text = str(group.get("name", "گروه"))
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", CREAM)
		body.add_child(title)
		var info := Label.new()
		info.text = "رهبر: %s  ·  اعضا: %d / %d" % [_safe_player_name(group.get("leader_name", null)), int(group.get("member_count", 0)), int(group.get("capacity", 20))]
		info.add_theme_color_override("font_color", MUTED)
		body.add_child(info)
		if int(group.get("member_count", 0)) < int(group.get("capacity", 20)):
			var join := _make_button("درخواست عضویت / ورود", Color("#287c68"), CREAM)
			var group_id := str(group.get("id", ""))
			join.pressed.connect(func(): _join_group_now(group_id))
			body.add_child(join)
		else:
			var full := Label.new()
			full.text = "ظرفیت تکمیل است"
			full.add_theme_color_override("font_color", RED)
			body.add_child(full)

func _create_group_from_form() -> void:
	if group_name_input == null or not is_instance_valid(group_name_input):
		return
	var result: Dictionary = await CloudAccount.create_group(group_name_input.text.strip_edges(), group_description_input.text.strip_edges() if group_description_input != null else "")
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ساخت گروه انجام نشد.")), RED)
		return
	_show_groups()

func _join_group_now(group_id: String) -> void:
	var result: Dictionary = await CloudAccount.join_group(group_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "عضویت انجام نشد.")), RED)
		return
	_show_groups()

func _render_my_group(group: Dictionary, members: Array) -> void:
	var group_id := str(group.get("id", ""))
	var role := str(group.get("my_role", "member"))
	active_group_role = role
	var card := _panel(GOLD)
	content_box.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(body)
	var title := Label.new()
	title.text = str(group.get("name", "گروه من"))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GOLD)
	body.add_child(title)
	var capacity := int(group.get("capacity", 20))
	var count := members.size()
	var summary := Label.new()
	summary.text = "مقام تو: %s  ·  اعضا: %d / %d" % [_group_role_label(role), count, capacity]
	summary.add_theme_color_override("font_color", CREAM)
	body.add_child(summary)
	var chat := _make_button("ورود به گفت‌وگوی گروه", Color("#287c68"), CREAM)
	chat.pressed.connect(func(): _show_group_chat(group_id, str(group.get("name", "گروه"))))
	body.add_child(chat)
	if role == "leader":
		var upgrade := _make_button("افزایش ظرفیت به %d نفر · ۵۰٬۰۰۰ سکه" % (capacity + 5), Color("#765a31"), CREAM)
		upgrade.disabled = coins < 50000
		upgrade.pressed.connect(func(): _upgrade_my_group(group_id, capacity + 5))
		body.add_child(upgrade)
	if role != "leader":
		var leave := _make_button("ترک گروه", Color("#713e3b"), CREAM)
		leave.pressed.connect(func(): _leave_my_group(group_id))
		body.add_child(leave)

	var members_title := Label.new()
	members_title.text = "اعضای گروه"
	members_title.add_theme_font_size_override("font_size", 18)
	members_title.add_theme_color_override("font_color", GOLD)
	content_box.add_child(members_title)
	for member in members:
		var player: Dictionary = member.get("player", {})
		var member_id := str(member.get("user_id", ""))
		var member_role := str(member.get("role", "member"))
		var row := _panel(TEAL if member_role == "leader" else PANEL_ALT)
		content_box.add_child(row)
		var row_box := VBoxContainer.new()
		row_box.add_theme_constant_override("separation", 4)
		row.add_child(row_box)
		var name := _make_button("%s  ·  %s" % [_safe_player_name(player.get("display_name", null)), _group_role_label(member_role)], Color("#294c43"), CREAM)
		name.custom_minimum_size = Vector2(0, 36)
		if member_id == CloudAccount.user_id:
			name.disabled = true
		else:
			name.pressed.connect(func(): _show_public_profile(member_id))
		row_box.add_child(name)
		if member_id != CloudAccount.user_id and (role == "leader" or role == "deputy"):
			var target_roles: Array = ["member", "veteran", "deputy"] if role == "leader" else (["veteran"] if member_role == "member" else ["member"] if member_role == "veteran" else [])
			for target_role in target_roles:
				if target_role == member_role:
					continue
				var selected_role := str(target_role)
				var role_button := _make_button("تعیین مقام: %s" % _group_role_label(selected_role), Color("#385b75"), CREAM)
				role_button.pressed.connect(func(): _change_group_role(group_id, member_id, selected_role))
				row_box.add_child(role_button)
			if role == "leader":
				var transfer := _make_button("واگذاری رهبری", Color("#765a31"), CREAM)
				transfer.pressed.connect(func(): _confirm_group_leadership_transfer(group_id, member_id, _safe_player_name(player.get("display_name", null), "این عضو")))
				row_box.add_child(transfer)
			if role == "leader" or member_role in ["member", "veteran"]:
				var remove := _make_button("حذف از گروه", Color("#713e3b"), CREAM)
				remove.pressed.connect(func(): _remove_group_member_now(group_id, member_id))
				row_box.add_child(remove)

func _group_role_label(role: String) -> String:
	match role:
		"leader": return "رهبر"
		"deputy": return "قائم‌مقام"
		"veteran": return "پیشکسوت"
		_: return "عضو"

func _upgrade_my_group(group_id: String, capacity: int) -> void:
	var result: Dictionary = await CloudAccount.upgrade_group_capacity(group_id, capacity)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "افزایش ظرفیت انجام نشد.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	_show_groups()

func _change_group_role(group_id: String, target_id: String, role: String) -> void:
	var result: Dictionary = await CloudAccount.set_group_role(group_id, target_id, role)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "تغییر مقام انجام نشد.")), RED)
		return
	_show_groups()

func _remove_group_member_now(group_id: String, target_id: String) -> void:
	var result: Dictionary = await CloudAccount.remove_group_member(group_id, target_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "حذف عضو انجام نشد.")), RED)
		return
	_show_groups()

func _confirm_group_leadership_transfer(group_id: String, target_id: String, target_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "انتقال رهبری گروه"
	dialog.dialog_text = "رهبری گروه به %s منتقل شود؟ مقام تو پس از انتقال، قائم‌مقام خواهد شد." % target_name
	dialog.confirmed.connect(func(): _transfer_group_leadership(group_id, target_id))
	add_child(dialog)
	dialog.popup_centered()

func _transfer_group_leadership(group_id: String, target_id: String) -> void:
	var result: Dictionary = await CloudAccount.transfer_group_leadership(group_id, target_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "انتقال رهبری انجام نشد.")), RED)
		return
	_show_groups()

func _leave_my_group(group_id: String) -> void:
	var result: Dictionary = await CloudAccount.leave_group(group_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ترک گروه انجام نشد.")), RED)
		return
	_show_groups()

func _show_group_chat(group_id: String, group_name: String) -> void:
	current_page = "group_chat"
	active_group_chat_id = group_id
	active_group_chat_name = group_name
	_clear_content()
	var heading := Label.new()
	heading.text = "گفت‌وگوی گروه · " + group_name
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var messages_scroll := ScrollContainer.new()
	messages_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	messages_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_box.add_child(messages_scroll)
	chat_messages_box = VBoxContainer.new()
	chat_messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_messages_box.add_theme_constant_override("separation", 7)
	messages_scroll.add_child(chat_messages_box)
	var composer := HBoxContainer.new()
	composer.add_theme_constant_override("separation", 6)
	content_box.add_child(composer)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "پیام گروه را بنویس..."
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.custom_minimum_size.y = 48
	_style_input(chat_input)
	composer.add_child(chat_input)
	var send := _make_button("ارسال", Color("#287c68"), CREAM)
	send.custom_minimum_size = Vector2(76, 48)
	send.pressed.connect(_send_global_chat_message)
	composer.add_child(send)
	var stickers := _make_button("استیکرها", Color("#765a31"), CREAM)
	stickers.pressed.connect(_show_sticker_picker)
	content_box.add_child(stickers)
	chat_status_label = Label.new()
	chat_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_status_label.add_theme_color_override("font_color", MUTED)
	content_box.add_child(chat_status_label)
	await _refresh_global_chat()
	if chat_poll_timer == null:
		chat_poll_timer = Timer.new()
		chat_poll_timer.wait_time = 5.0
		chat_poll_timer.timeout.connect(_refresh_global_chat)
		add_child(chat_poll_timer)
	chat_poll_timer.start()
	var back := _make_button("بازگشت به گروه", PANEL_ALT, CREAM)
	back.pressed.connect(_show_groups)
	content_box.add_child(back)

func _build_avatar_widget(path: String, frame_id: String, widget_size: int) -> Control:
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(widget_size, widget_size)
	stack.size = Vector2(widget_size, widget_size)
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.clip_contents = true
	var picture := TextureRect.new()
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.custom_minimum_size = Vector2.ZERO
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture = load("res://assets/icons/profile.svg")
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(picture)
	if not path.is_empty():
		var request := HTTPRequest.new()
		request.timeout = 15.0
		add_child(request)
		request.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
			if response_code == 200 and is_instance_valid(picture):
				var image := Image.new()
				var image_error := image.load_jpg_from_buffer(body)
				if image_error != OK:
					image_error = image.load_png_from_buffer(body)
				if image_error == OK:
					picture.texture = ImageTexture.create_from_image(image)
			request.queue_free()
		)
		request.request(CloudAccount.avatar_public_url(path))
	var frame_name := frame_id.trim_prefix("frame_")
	var frame_path := "res://assets/frames/%s.svg" % frame_name
	if not ResourceLoader.exists(frame_path):
		frame_path = "res://assets/frames/default.svg"
	var frame := TextureRect.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.custom_minimum_size = Vector2.ZERO
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.texture = load(frame_path)
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(frame)
	return stack

func _pick_avatar_from_gallery() -> void:
	if guest_mode or not avatar_unlocked:
		_set_status("ابتدا باید قابلیت عکس پروفایل را با ۷۰۰۰ سکه فعال کنی.", GOLD)
		return
	var picker = Engine.get_singleton("BaladiMediaPicker")
	if picker == null:
		_set_status("انتخاب عکس از گالری در نسخه اندروید فعال می‌شود.", RED)
		return
	var picked_callback := Callable(self, "_on_avatar_image_picked")
	var cancelled_callback := Callable(self, "_on_avatar_picker_cancelled")
	var error_callback := Callable(self, "_on_avatar_picker_error")
	if not picker.is_connected("image_picked", picked_callback):
		picker.connect("image_picked", picked_callback)
	if not picker.is_connected("picker_cancelled", cancelled_callback):
		picker.connect("picker_cancelled", cancelled_callback)
	if not picker.is_connected("picker_error", error_callback):
		picker.connect("picker_error", error_callback)
	picker.call("pickImage")

func _on_avatar_image_picked(image_path: String) -> void:
	crop_source_image = Image.new()
	var error := crop_source_image.load(image_path)
	if error != OK:
		_set_status("خواندن تصویر انتخاب‌شده ناموفق بود.", RED)
		return
	crop_zoom = 1.0
	crop_offset = Vector2.ZERO
	_show_avatar_crop()

func _on_avatar_picker_cancelled() -> void:
	pass

func _on_avatar_picker_error(message: String) -> void:
	_set_status(message, RED)

func _show_avatar_crop() -> void:
	current_page = "avatar_crop"
	_clear_content()
	var heading := Label.new()
	heading.text = "تنظیم عکس پروفایل"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var note := Label.new()
	note.text = "تصویر را جابه‌جا کن و بزرگ‌نمایی را تنظیم کن. خروجی همیشه مربع ۱:۱ است."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", MUTED)
	content_box.add_child(note)
	crop_viewport = Control.new()
	crop_viewport.custom_minimum_size = Vector2(280, 280)
	crop_viewport.size = Vector2(280, 280)
	crop_viewport.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	crop_viewport.clip_contents = true
	crop_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	crop_viewport.gui_input.connect(_on_avatar_crop_input)
	var crop_backdrop := ColorRect.new()
	crop_backdrop.color = Color("#102b25")
	crop_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crop_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crop_viewport.add_child(crop_backdrop)
	crop_texture_rect = TextureRect.new()
	crop_texture_rect.texture = ImageTexture.create_from_image(crop_source_image)
	crop_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crop_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crop_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crop_viewport.add_child(crop_texture_rect)
	content_box.add_child(crop_viewport)
	crop_zoom_slider = HSlider.new()
	crop_zoom_slider.min_value = 1.0
	crop_zoom_slider.max_value = 3.0
	crop_zoom_slider.step = 0.05
	crop_zoom_slider.value = 1.0
	crop_zoom_slider.value_changed.connect(func(value: float):
		crop_zoom = value
		_update_avatar_crop_preview()
	)
	content_box.add_child(crop_zoom_slider)
	_update_avatar_crop_preview()
	var save := _make_button("تأیید برش و ذخیره عکس", Color("#287c68"), CREAM)
	save.pressed.connect(_confirm_avatar_crop)
	content_box.add_child(save)
	var cancel := _make_button("انصراف", PANEL_ALT, CREAM)
	cancel.pressed.connect(_show_profile)
	content_box.add_child(cancel)

func _update_avatar_crop_preview() -> void:
	if crop_viewport == null or crop_texture_rect == null or crop_source_image == null:
		return
	var view_size := crop_viewport.size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = Vector2(280, 280)
	var image_size := Vector2(crop_source_image.get_width(), crop_source_image.get_height())
	var base_scale := maxf(view_size.x / image_size.x, view_size.y / image_size.y)
	var rendered_size := image_size * base_scale * crop_zoom
	var centered_position := (view_size - rendered_size) * 0.5
	var position := centered_position + crop_offset
	position.x = clampf(position.x, view_size.x - rendered_size.x, 0.0)
	position.y = clampf(position.y, view_size.y - rendered_size.y, 0.0)
	crop_offset = position - centered_position
	crop_texture_rect.size = rendered_size
	crop_texture_rect.position = position

func _on_avatar_crop_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		crop_dragging = event.pressed
	elif event is InputEventScreenDrag and crop_dragging:
		crop_offset += event.relative
		_update_avatar_crop_preview()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		crop_dragging = event.pressed
	elif event is InputEventMouseMotion and crop_dragging:
		crop_offset += event.relative
		_update_avatar_crop_preview()

func _confirm_avatar_crop() -> void:
	if crop_source_image == null or crop_viewport == null or crop_texture_rect == null:
		return
	var source_width := crop_source_image.get_width()
	var source_height := crop_source_image.get_height()
	var view_size := crop_viewport.size
	var scale_factor := maxf(view_size.x / source_width, view_size.y / source_height) * crop_zoom
	var source_side := int(floor(minf(view_size.x, view_size.y) / scale_factor))
	source_side = clampi(source_side, 1, min(source_width, source_height))
	var source_x := clampi(int(round(-crop_texture_rect.position.x / scale_factor)), 0, source_width - source_side)
	var source_y := clampi(int(round(-crop_texture_rect.position.y / scale_factor)), 0, source_height - source_side)
	var cropped := crop_source_image.get_region(Rect2i(source_x, source_y, source_side, source_side))
	cropped.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var result: Dictionary = await CloudAccount.upload_avatar(cropped)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ذخیره عکس پروفایل ناموفق بود.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	avatar_path = str(result.get("avatar_path", avatar_path))
	crop_source_image = null
	_show_profile()

func _show_cosmetic_shop() -> void:
	current_page = "cosmetic_shop"
	_clear_content()
	_add_section_art("assets/backgrounds/chapter-palace.svg", 92)
	var heading := Label.new()
	heading.text = "فروشگاه قاب‌ها و تصویر پروفایل"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	if guest_mode:
		_set_status("خریدهای فروشگاه برای حساب‌های ثبت‌شده فعال است.", GOLD)
		var guest_back := _make_button("بازگشت", PANEL_ALT, CREAM)
		guest_back.pressed.connect(_show_profile)
		content_box.add_child(guest_back)
		return
	var result: Dictionary = await CloudAccount.get_cosmetics_catalog()
	if not result.get("ok", false):
		_set_status(str(result.get("error", "فروشگاه بارگذاری نشد.")), RED)
		return
	var owned_ids: Dictionary = {}
	for owned in result.get("owned", []):
		owned_ids[str(owned.get("cosmetic_id", ""))] = true
	var shop_grid := GridContainer.new()
	shop_grid.columns = 2
	shop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_grid.add_theme_constant_override("h_separation", 9)
	shop_grid.add_theme_constant_override("v_separation", 9)
	content_box.add_child(shop_grid)
	for item in result.get("catalog", []):
		var item_id := str(item.get("id", ""))
		var item_kind := str(item.get("kind", ""))
		var card := _panel(GOLD if item_kind == "avatar_unlock" else (Color("#b18a4d") if item_kind == "sticker" else TEAL))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 220)
		shop_grid.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		card.add_child(body)
		var title := Label.new()
		title.text = str(item.get("display_name", ""))
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", CREAM)
		body.add_child(title)
		var asset_path := str(item.get("asset_path", ""))
		if item_kind == "frame":
			var frame_preview := _build_avatar_widget("", item_id, 74)
			body.add_child(frame_preview)
		elif item_kind == "avatar_unlock":
			var avatar_preview := TextureRect.new()
			avatar_preview.texture = load("res://assets/icons/profile.svg")
			avatar_preview.custom_minimum_size = Vector2(74, 74)
			avatar_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			avatar_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			avatar_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			body.add_child(avatar_preview)
		elif not asset_path.is_empty() and asset_path.begins_with("assets/stickers/"):
			var item_art := TextureRect.new()
			item_art.texture = load("res://" + asset_path)
			item_art.custom_minimum_size = Vector2(74, 74)
			item_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			item_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			item_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			body.add_child(item_art)
		var price := Label.new()
		price.text = "رایگان" if int(item.get("price_coins", 0)) == 0 else "%s سکه" % str(item.get("price_coins", 0))
		price.add_theme_color_override("font_color", GOLD)
		body.add_child(price)
		if owned_ids.has(item_id):
			if item_kind == "frame":
				var equip := _make_button("استفاده از این قاب" if equipped_frame_id != item_id else "قاب فعال", Color("#287c68"), CREAM)
				equip.disabled = equipped_frame_id == item_id
				equip.pressed.connect(func(): _equip_cosmetic_frame(item_id))
				body.add_child(equip)
			elif item_kind == "avatar_unlock":
				var choose_photo := _make_button("انتخاب عکس از گالری", Color("#287c68"), CREAM)
				choose_photo.pressed.connect(_pick_avatar_from_gallery)
				body.add_child(choose_photo)
			else:
				var bought := Label.new()
				bought.text = "خریداری شده"
				bought.add_theme_color_override("font_color", GREEN)
				body.add_child(bought)
		else:
			var buy := _make_button("خرید", Color("#765a31"), CREAM)
			buy.pressed.connect(func(): _purchase_cosmetic(item_id))
			body.add_child(buy)
	var back := _make_button("بازگشت به پروفایل", PANEL_ALT, CREAM)
	back.pressed.connect(_show_profile)
	content_box.add_child(back)

func _purchase_cosmetic(cosmetic_id: String) -> void:
	var result: Dictionary = await CloudAccount.purchase_cosmetic(cosmetic_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "خرید انجام نشد.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	_animate_coin_reward(-int(result.get("item", {}).get("price_coins", 0)))
	_show_cosmetic_shop()

func _equip_cosmetic_frame(frame_id: String) -> void:
	var result: Dictionary = await CloudAccount.equip_frame(frame_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "تغییر قاب انجام نشد.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	equipped_frame_id = frame_id
	_show_cosmetic_shop()

func _show_leaderboard() -> void:
	current_page = "leaderboard"
	_clear_content()
	_add_section_art("assets/backgrounds/chapter-mountains.svg", 92)
	var heading := Label.new()
	heading.text = "جدول قهرمانان"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	if guest_mode:
		_set_status("جدول رتبه‌بندی برای بازیکنان دارای حساب نمایش داده می‌شود.", GOLD)
	else:
		var result: Dictionary = await CloudAccount.get_leaderboard()
		if not result.get("ok", false):
			_set_status(str(result.get("error", "جدول رتبه‌بندی بارگذاری نشد.")), RED)
		else:
			for player in result.get("leaderboard", []):
				var player_id := str(player.get("user_id", ""))
				var rank := int(player.get("rank", 0))
				var player_name := _safe_player_name(player.get("display_name", null))
				var row := _make_button("#%d   %s   ·   مرحله %d   ·   %d سکه" % [rank, player_name, int(player.get("current_level", 1)), int(player.get("coins", 0))], PANEL_ALT, CREAM)
				row.pressed.connect(func(): _show_public_profile(player_id))
				content_box.add_child(row)
	var back := _make_button("بازگشت", PANEL, CREAM)
	back.pressed.connect(_show_profile)
	content_box.add_child(back)

func _show_public_profile(target_user_id: String) -> void:
	current_page = "public_profile"
	if guest_mode:
		return
	_clear_content()
	var result: Dictionary = await CloudAccount.get_public_profile(target_user_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "پروفایل بازیکن بارگذاری نشد.")), RED)
		var back_error := _make_button("بازگشت به رتبه‌بندی", PANEL_ALT, CREAM)
		back_error.pressed.connect(_show_leaderboard)
		content_box.add_child(back_error)
		return
	var player: Dictionary = result.get("profile", {})
	var public_avatar := _build_avatar_widget(str(player.get("avatar_path", "")), str(player.get("equipped_frame_id", "frame_default")), 92)
	content_box.add_child(public_avatar)
	var heading := Label.new()
	heading.text = _safe_player_name(player.get("display_name", null))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 8)
	stats.add_theme_constant_override("v_separation", 8)
	content_box.add_child(stats)
	_add_profile_stat(stats, "مرحله فعلی", str(player.get("current_level", 1)), GOLD)
	_add_profile_stat(stats, "مراحل کامل‌شده", str(player.get("levels_completed", 0)), GREEN)
	_add_profile_stat(stats, "واژه‌های پیدا‌شده", str(player.get("words_found", 0)), TEAL)
	_add_profile_stat(stats, "برد دونفره", str(player.get("wins", 0)), GREEN)
	_add_profile_stat(stats, "باخت دونفره", str(player.get("losses", 0)), RED)
	var challenge := _make_button("دعوت به مسابقهٔ دونفره", Color("#765a31"), CREAM)
	challenge.pressed.connect(func(): _send_duel_invite_to(target_user_id))
	content_box.add_child(challenge)
	var back := _make_button("بازگشت به رتبه‌بندی", PANEL_ALT, CREAM)
	back.pressed.connect(_show_leaderboard)
	content_box.add_child(back)

func _add_profile_stat(parent: GridContainer, caption: String, value: String, accent: Color) -> void:
	var tile := _panel(accent)
	tile.custom_minimum_size = Vector2(0, 82)
	parent.add_child(tile)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 3)
	tile.add_child(stack)
	var number := Label.new()
	number.text = value
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 21)
	number.add_theme_color_override("font_color", accent)
	stack.add_child(number)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", MUTED)
	stack.add_child(label)

func _save_profile_name() -> void:
	var new_name := profile_name_input.text.strip_edges()
	if new_name.length() < 2 or new_name.length() > 24:
		profile_status_label.text = "نام نمایشی باید بین ۲ تا ۲۴ نویسه باشد."
		profile_status_label.add_theme_color_override("font_color", RED)
		return
	if guest_mode:
		if new_name == display_name:
			profile_status_label.text = "این نام از قبل روی پروفایل ثبت شده است."
			profile_status_label.add_theme_color_override("font_color", MUTED)
			return
		if name_change_count >= 1:
			if diamonds < 1:
				profile_status_label.text = "برای تغییر دوباره نام، یک الماس لازم داری."
				profile_status_label.add_theme_color_override("font_color", RED)
				return
			diamonds -= 1
		name_change_count += 1
		if profile_rename_button != null:
			profile_rename_button.text = "تغییر نام · ۱ الماس"
		display_name = new_name
		_save()
		profile_status_label.text = "نام پروفایل ذخیره شد." if name_change_count == 1 else "نام تغییر کرد؛ یک الماس مصرف شد."
		profile_status_label.add_theme_color_override("font_color", GREEN)
		return
	var result: Dictionary = await CloudAccount.update_profile_name(new_name)
	if not result.get("ok", false):
		profile_status_label.text = str(result.get("error", "ذخیره نام انجام نشد."))
		profile_status_label.add_theme_color_override("font_color", RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	if profile_rename_button != null:
		profile_rename_button.text = "تغییر نام · ۱ الماس"
	profile_status_label.text = "نام پروفایل با موفقیت ذخیره شد." if int(result.get("diamonds_spent", 0)) == 0 else "نام تغییر کرد؛ یک الماس مصرف شد."
	profile_status_label.add_theme_color_override("font_color", GREEN)

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
		if guest_mode:
			_complete_guest_level()
		else:
			var completion: Dictionary = await CloudAccount.complete_level(stage_id)
			if completion.get("ok", false):
				_apply_cloud_profile(completion.get("profile", {}))
				_show_stage_complete(int(levels[level_index].get("reward", 0)))
			else:
				_set_status(str(completion.get("error", "ثبت مرحله انجام نشد.")), RED)

func _chapter_title(level_number: int) -> String:
	if level_number <= 20: return "باغ واژه‌ها"
	if level_number <= 40: return "بازار رازآلود"
	if level_number <= 60: return "کاروانسرای کلمات"
	if level_number <= 80: return "قله‌های دانایی"
	if level_number <= 100: return "کاخ گنج واژه‌ها"
	if level_number <= 120: return "دشت رازها"
	if level_number <= 140: return "بندر افق"
	if level_number <= 160: return "جنگل اسرار"
	if level_number <= 180: return "آسمان ستارگان"
	return "قلعه زرین"

func _chapter_background_path(level_number: int) -> String:
	if level_number <= 20:
		return "res://assets/backgrounds/chapter-garden.svg"
	if level_number <= 40:
		return "res://assets/backgrounds/chapter-bazaar.svg"
	if level_number <= 60:
		return "res://assets/backgrounds/chapter-caravanserai.svg"
	if level_number <= 80:
		return "res://assets/backgrounds/chapter-mountains.svg"
	if level_number <= 100:
		return "res://assets/backgrounds/chapter-palace.svg"
	if level_number <= 120:
		return "res://assets/backgrounds/chapter-dasht.svg"
	if level_number <= 140:
		return "res://assets/backgrounds/chapter-bandar.svg"
	if level_number <= 160:
		return "res://assets/backgrounds/chapter-jangal.svg"
	if level_number <= 180:
		return "res://assets/backgrounds/chapter-aseman.svg"
	return "res://assets/backgrounds/chapter-ghale.svg"

func _build_chapter_banner(level_number: int) -> Control:
	var banner := Control.new()
	banner.custom_minimum_size = Vector2(0, 116)
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.clip_contents = true
	var background := TextureRect.new()
	background.texture = load(_chapter_background_path(level_number))
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.08, 0.07, 0.34)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(shade)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	banner.add_child(row)
	var mascot := TextureRect.new()
	mascot.texture = load("res://assets/characters/mascot.svg")
	mascot.custom_minimum_size = Vector2(76, 76)
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mascot)
	mascot.pivot_offset = Vector2(38, 38)
	var mascot_tween := create_tween()
	mascot_tween.set_loops()
	mascot_tween.tween_property(mascot, "scale", Vector2(1.045, 1.045), 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	mascot_tween.tween_property(mascot, "scale", Vector2.ONE, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var text_box := VBoxContainer.new()
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)
	var chapter := Label.new()
	chapter.text = _chapter_title(level_number)
	chapter.add_theme_font_size_override("font_size", 18)
	chapter.add_theme_color_override("font_color", GOLD)
	text_box.add_child(chapter)
	var line := Label.new()
	line.text = "هر واژه، یک قدم نزدیک‌تر به گنج"
	line.add_theme_font_size_override("font_size", 12)
	line.add_theme_color_override("font_color", CREAM)
	text_box.add_child(line)
	return banner

func _show_game() -> void:
	current_page = "game"
	_clear_content()
	if exit_button != null:
		exit_button.visible = true
		exit_button.text = "خروج مهمان" if guest_mode else "خروج از حساب"
	if profile_button != null:
		profile_button.visible = true
	coin_panel.visible = true
	if levels.is_empty():
		var error_label := Label.new()
		error_label.text = "داده مراحل بارگذاری نشد."
		content_box.add_child(error_label)
		return

	var data: Dictionary = levels[level_index]
	if duel_mode:
		data = {"id": duel_round_number, "title": "رقابت دونفره"}
	level_label = Label.new()
	level_label.text = "رقابت %02d از ۱۰" % duel_round_number if duel_mode else "مرحله %02d" % int(data.get("id", level_index + 1))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 25)
	level_label.add_theme_color_override("font_color", GOLD)
	content_box.add_child(level_label)

	subtitle_label = Label.new()
	subtitle_label.text = "اولین بازیکنی که ۱۰ مرحله را کامل کند، برنده است." if duel_mode else str(data.get("title", ""))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 13)
	subtitle_label.add_theme_color_override("font_color", MUTED)
	content_box.add_child(subtitle_label)
	var chapter_level := duel_round_number * 10 if duel_mode else int(data.get("id", level_index + 1))
	var game_banner := _build_chapter_banner(chapter_level)
	game_banner.custom_minimum_size = Vector2(0, 88)
	content_box.add_child(game_banner)

	var board_panel := _panel(Color("#8f7547"))
	board_panel.custom_minimum_size.y = 150
	content_box.add_child(board_panel)
	board_box = GridContainer.new()
	board_box.columns = 1
	board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_box.add_theme_constant_override("h_separation", 9)
	board_box.add_theme_constant_override("v_separation", 9)
	board_panel.add_child(board_box)
	_render_board()

	var selection_panel := _panel(Color("#9a7738"))
	selection_panel.custom_minimum_size.y = 68
	content_box.add_child(selection_panel)
	selection_label = Label.new()
	selection_label.text = "حروف را با کشیدن انگشت به هم وصل کن"
	selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selection_label.add_theme_font_size_override("font_size", 18)
	selection_label.add_theme_color_override("font_color", GOLD)
	selection_panel.add_child(selection_label)

	letters_grid = Control.new()
	letters_grid.custom_minimum_size = Vector2(0, 248)
	letters_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(letters_grid)
	letters_grid.resized.connect(_layout_letters)
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
	hint_button = _make_button("راهنماها", Color("#765a31"), CREAM)
	hint_button.pressed.connect(_show_hint_menu)
	actions.add_child(hint_button)
	submit_button = _make_button("ثبت واژه", GOLD, BG)
	submit_button.pressed.connect(_submit_word)
	actions.add_child(submit_button)

	var map_button := _make_button("خروج از رقابت" if duel_mode else "بازگشت به نقشه مراحل", Color("#203e38"), CREAM)
	map_button.pressed.connect(_leave_duel_to_map if duel_mode else _show_map)
	if duel_mode and profile_button != null:
		profile_button.visible = false
	content_box.add_child(map_button)
	_update_controls()

func _init_audio() -> void:
	sfx_player = AudioStreamPlayer.new()
	sfx_player.volume_db = -7.0
	add_child(sfx_player)

func _play_sfx(kind: String) -> void:
	if sfx_player == null or not sound_enabled:
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

func _style_input(field: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#102e29")
	normal.border_color = Color("#547b6d")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	field.add_theme_stylebox_override("normal", normal)
	var focus := normal.duplicate()
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", CREAM)
	field.add_theme_color_override("font_placeholder_color", MUTED)

func _panel(border_color: Color = Color("#557b6d")) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(17)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
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
	normal.shadow_color = Color(0, 0, 0, 0.2)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 2)
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
	var answers: Array = levels[level_index].get("answers", [])
	var words: Array = _words_for_current_level()
	if duel_mode:
		answers = []
		for _i in range(duel_answer_count):
			answers.append("")

	var journal := VBoxContainer.new()
	journal.add_theme_constant_override("separation", 9)
	board_box.add_child(journal)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	journal.add_child(header)
	var title := Label.new()
	title.text = "واژه‌های رقابت" if duel_mode else "دفتر واژه‌ها"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var progress := Label.new()
	progress.text = "%d از %d واژه" % [words.size(), answers.size()]
	progress.add_theme_font_size_override("font_size", 13)
	progress.add_theme_color_override("font_color", MUTED)
	header.add_child(progress)

	var progress_bar := ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = max(1, answers.size())
	progress_bar.value = words.size()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size.y = 7
	journal.add_child(progress_bar)

	if words.is_empty():
		var empty_state := VBoxContainer.new()
		empty_state.alignment = BoxContainer.ALIGNMENT_CENTER
		empty_state.add_theme_constant_override("separation", 4)
		journal.add_child(empty_state)
		var mark := Label.new()
		mark.text = "✦"
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.add_theme_font_size_override("font_size", 28)
		mark.add_theme_color_override("font_color", GOLD)
		empty_state.add_child(mark)
		var empty_text := Label.new()
		empty_text.text = "اولین واژه‌ات را کشف کن"
		empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_text.add_theme_font_size_override("font_size", 14)
		empty_text.add_theme_color_override("font_color", MUTED)
		empty_state.add_child(empty_text)
		return

	var found_grid := GridContainer.new()
	found_grid.columns = 2
	found_grid.add_theme_constant_override("h_separation", 7)
	found_grid.add_theme_constant_override("v_separation", 7)
	journal.add_child(found_grid)
	for word_value in words:
		var chip := PanelContainer.new()
		var chip_style := StyleBoxFlat.new()
		chip_style.bg_color = Color("#245448")
		chip_style.border_color = GOLD
		chip_style.set_border_width_all(1)
		chip_style.set_corner_radius_all(12)
		chip_style.content_margin_left = 8
		chip_style.content_margin_right = 8
		chip_style.content_margin_top = 7
		chip_style.content_margin_bottom = 7
		chip.add_theme_stylebox_override("panel", chip_style)
		var word_label := Label.new()
		word_label.text = "✦  " + str(word_value)
		word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word_label.add_theme_font_size_override("font_size", 17)
		word_label.add_theme_color_override("font_color", CREAM)
		chip.add_child(word_label)
		found_grid.add_child(chip)

func _render_letters() -> void:
	for child in letters_grid.get_children():
		child.queue_free()
	letter_buttons.clear()
	selected_indices.clear()
	selected_word = ""

	var tray := TextureRect.new()
	tray.texture = load("res://assets/backgrounds/letter-wheel.svg")
	tray.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tray.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letters_grid.add_child(tray)

	var letters: Array = _current_letters()
	for i in range(letters.size()):
		var button := _make_button(str(letters[i]), PANEL_ALT, CREAM)
		button.custom_minimum_size = Vector2(58, 58)
		button.size = Vector2(58, 58)
		button.add_theme_font_size_override("font_size", 25)
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.pivot_offset = Vector2(29, 29)
		var circle_style := StyleBoxFlat.new()
		circle_style.bg_color = Color("#205247")
		circle_style.border_color = Color("#d4b46f")
		circle_style.set_border_width_all(2)
		circle_style.set_corner_radius_all(34)
		circle_style.shadow_color = Color(0, 0, 0, 0.28)
		circle_style.shadow_size = 5
		circle_style.shadow_offset = Vector2(0, 3)
		button.add_theme_stylebox_override("normal", circle_style)
		var hover_style := circle_style.duplicate()
		hover_style.bg_color = Color("#2c6b5b")
		button.add_theme_stylebox_override("hover", hover_style)
		letters_grid.add_child(button)
		letter_buttons.append(button)
	call_deferred("_layout_letters")
	_update_selection_label()

func _layout_letters() -> void:
	if letters_grid == null or not is_instance_valid(letters_grid) or letter_buttons.is_empty():
		return
	var center := letters_grid.size * 0.5
	var count := letter_buttons.size()
	var button_size := clampf(minf(letters_grid.size.x * 0.19, letters_grid.size.y * 0.25), 50.0, 62.0)
	var radius := minf(letters_grid.size.x * 0.34, letters_grid.size.y * 0.34)
	radius = maxf(0.0, radius)
	for i in range(count):
		var angle := -PI * 0.5 + TAU * float(i) / float(count)
		var target := center + Vector2(cos(angle), sin(angle)) * radius
		var button := letter_buttons[i]
		button.size = Vector2(button_size, button_size)
		button.custom_minimum_size = Vector2(button_size, button_size)
		button.pivot_offset = Vector2(button_size * 0.5, button_size * 0.5)
		button.position = target - button.size * 0.5

func _words_for_current_level() -> Array:
	if duel_mode:
		return duel_found_words
	var key := str(int(levels[level_index].get("id", level_index + 1)))
	var value = level_solved.get(key, [])
	return value if value is Array else []

func _bonus_words_for_current_level() -> Array:
	if duel_mode:
		return []
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
	var trace_points: Array[Vector2] = []
	for selected_index in selected_indices:
		var rect := letter_buttons[selected_index].get_global_rect()
		trace_points.append(rect.get_center())
	trace_points.append(point)
	var curve := Curve2D.new()
	for i in range(trace_points.size()):
		var previous := trace_points[max(0, i - 1)]
		var following := trace_points[min(trace_points.size() - 1, i + 1)]
		var tangent := (following - previous) * 0.24
		curve.add_point(trace_points[i], -tangent, tangent)
	trace_line.points = curve.get_baked_points()

func _add_trace_letter(index: int) -> void:
	if index < 0 or index >= letter_buttons.size() or selected_indices.has(index):
		return
	selected_indices.append(index)
	var letters: Array = _current_letters()
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
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK):
		_handle_back_request()
		get_viewport().set_input_as_handled()
		return
	if stage_scroll != null and is_instance_valid(stage_scroll) and stage_scroll.is_visible_in_tree():
		if event is InputEventScreenTouch:
			if event.pressed and stage_scroll.get_global_rect().has_point(event.position):
				stage_touch_active = true
				stage_touch_y = event.position.y
			elif not event.pressed:
				stage_touch_active = false
		elif event is InputEventScreenDrag and stage_touch_active:
			var delta_y: float = stage_touch_y - event.position.y
			stage_scroll.scroll_vertical = clampi(stage_scroll.scroll_vertical + int(delta_y), 0, maxi(0, int(stage_scroll.get_v_scroll_bar().max_value)))
			stage_touch_y = event.position.y
			return
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
		if index < letter_buttons.size() and is_instance_valid(letter_buttons[index]):
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
	if duel_mode:
		var duel_result: Dictionary = await CloudAccount.submit_duel_word(duel_match_id, candidate)
		if not duel_result.get("ok", false):
			_set_status(str(duel_result.get("error", "بررسی واژه در مسابقه انجام نشد.")), RED)
		else:
			var duel_data: Dictionary = duel_result.get("result", {})
			_apply_cloud_profile(duel_result.get("profile", {}))
			if not duel_data.get("correct", false):
				_set_status("این واژه پاسخ این مرحله نیست.", RED)
			elif duel_data.get("already_found", false):
				_set_status("این واژه را قبلاً پیدا کرده‌ای.", GOLD)
			elif duel_data.get("match_complete", false):
				_play_sfx("complete")
				_show_duel_result(str(duel_data.get("winner_id", "")), int(duel_data.get("elapsed_ms", 0)))
			elif duel_data.get("round_complete", false):
				_play_sfx("complete")
				await _refresh_duel_round()
			else:
				duel_found_words = duel_data.get("found_words", duel_found_words)
				_play_sfx("found")
				_set_status("واژه پیدا شد! ادامه بده.", GREEN)
				_render_board()
		_clear_selection()
		_update_controls()
		return
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
	if stage_id % 20 == 0:
		diamonds += 1
		_spawn_floating_text("یک الماس برای عبور از فصل دریافت کردی!", GOLD)
	_save()
	_show_stage_complete(reward)

func _show_bonus_word_feedback(word: String) -> void:
	_set_status("«%s» واژه فارسی معتبری است، اما پاسخ اصلی این مرحله نیست؛ ۷ سکه هدیه گرفتی!" % word, GOLD)

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
	var display_text := "+%d سکه" % amount if amount > 0 else "−%d سکه" % abs(amount)
	var popup := HBoxContainer.new()
	popup.alignment = BoxContainer.ALIGNMENT_CENTER
	popup.add_theme_constant_override("separation", 6)
	popup.custom_minimum_size = Vector2(150, 42)
	popup.size = Vector2(150, 42)
	popup.z_index = 230
	var popup_icon := TextureRect.new()
	popup_icon.texture = load("res://assets/icons/coin.svg")
	popup_icon.custom_minimum_size = Vector2(30, 30)
	popup_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	popup_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	popup.add_child(popup_icon)
	var popup_label := Label.new()
	popup_label.text = display_text
	popup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	popup_label.add_theme_font_size_override("font_size", 20)
	popup_label.add_theme_color_override("font_color", GOLD if amount > 0 else RED)
	popup.add_child(popup_label)
	add_child(popup)
	var center_position := Vector2(size.x * 0.5 - 75, size.y * 0.56)
	var coin_position := center_position
	if coin_label != null and is_instance_valid(coin_label):
		coin_position = coin_label.get_global_rect().get_center() - Vector2(75, 21)
	popup.position = center_position if amount > 0 else coin_position
	popup.scale = Vector2(0.72, 0.72)
	if coin_label != null and is_instance_valid(coin_label):
		coin_label.text = "%d" % coins
		var pulse := create_tween()
		pulse.tween_property(coin_label, "scale", Vector2(1.28, 1.28), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pulse.tween_property(coin_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var target_position := coin_position if amount > 0 else center_position
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position", target_position, 0.68).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(popup, "scale", Vector2(0.48, 0.48), 0.68).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(popup, "modulate:a", 0.0, 0.68).set_delay(0.18)
	tween.chain().tween_callback(popup.queue_free)

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
	var chest_art := TextureRect.new()
	chest_art.texture = load("res://assets/rewards/treasure-chest.svg")
	chest_art.custom_minimum_size = Vector2(118, 78)
	chest_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chest_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chest_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(chest_art)
	chest_art.pivot_offset = Vector2(59, 39)
	chest_art.scale = Vector2(0.72, 0.72)
	var chest_tween := create_tween()
	chest_tween.tween_property(chest_art, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var title := Label.new()
	title.text = "مرحله با موفقیت کامل شد!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", GOLD)
	body.add_child(title)
	var reward_row := HBoxContainer.new()
	reward_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_row.add_theme_constant_override("separation", 8)
	var reward_icon := TextureRect.new()
	reward_icon.texture = load("res://assets/icons/coin.svg")
	reward_icon.custom_minimum_size = Vector2(32, 32)
	reward_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	reward_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reward_row.add_child(reward_icon)
	var reward_label := Label.new()
	reward_label.text = "+%d سکه پاداش" % reward
	reward_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reward_label.add_theme_font_size_override("font_size", 21)
	reward_label.add_theme_color_override("font_color", CREAM)
	reward_row.add_child(reward_label)
	body.add_child(reward_row)
	var completed_stage_id := int(levels[level_index].get("id", level_index + 1)) if not duel_mode else 0
	if not duel_mode and completed_stage_id > 0 and completed_stage_id % 20 == 0:
		var diamond_reward_row := HBoxContainer.new()
		diamond_reward_row.alignment = BoxContainer.ALIGNMENT_CENTER
		diamond_reward_row.add_theme_constant_override("separation", 7)
		var diamond_art := TextureRect.new()
		diamond_art.texture = load("res://assets/icons/diamond.svg")
		diamond_art.custom_minimum_size = Vector2(30, 30)
		diamond_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		diamond_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		diamond_reward_row.add_child(diamond_art)
		var diamond_reward_label := Label.new()
		diamond_reward_label.text = "+۱ الماس · پاداش تکمیل فصل"
		diamond_reward_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		diamond_reward_label.add_theme_font_size_override("font_size", 17)
		diamond_reward_label.add_theme_color_override("font_color", TEAL)
		diamond_reward_row.add_child(diamond_reward_label)
		body.add_child(diamond_reward_row)
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
	if duel_mode:
		return duel_answer_count > 0 and duel_found_words.size() >= duel_answer_count
	if levels.is_empty():
		return false
	var answers: Array = levels[level_index].get("answers", [])
	var words := _words_for_current_level()
	for answer in answers:
		if not words.has(str(answer)):
			return false
	return true

func _show_hint_menu() -> void:
	if hint_button == null or not is_instance_valid(hint_button):
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0.01, 0.04, 0.035, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 180
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 18
	center.offset_right = -18
	overlay.add_child(center)
	var card := _panel(GOLD)
	card.custom_minimum_size = Vector2(300, 0)
	center.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	card.add_child(stack)
	var heading := Label.new()
	heading.text = "راهنمای ماجراجویی"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", GOLD)
	stack.add_child(heading)
	var note := Label.new()
	note.text = "راهنمایی را انتخاب کن؛ فقط در صورت امکان اجرا، سکه کم می‌شود."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", MUTED)
	stack.add_child(note)
	var reveal_cost := 60 if duel_mode else 20
	var first_cost := 24 if duel_mode else 8
	var highlight_cost := 36 if duel_mode else 12
	var options := [
		{"id": 0, "icon": "res://assets/icons/hint-word.svg", "title": "آشکار کردن یک واژه", "detail": "%d سکه · پاسخ کامل ثبت می‌شود" % reveal_cost, "color": Color("#765a31")},
		{"id": 1, "icon": "res://assets/icons/hint-first.svg", "title": "نمایش حرف اول", "detail": "%d سکه · برای یک پاسخ حل‌نشده" % first_cost, "color": Color("#287c68")},
		{"id": 3, "icon": "res://assets/icons/hint-highlight.svg", "title": "برجسته‌سازی یک حرف", "detail": "%d سکه · روی صفحه حروف" % highlight_cost, "color": Color("#245448")}
	]
	for item in options:
		var option_button := Button.new()
		option_button.custom_minimum_size.y = 64
		option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		option_button.text = "%s  ·  %s" % [str(item.title), str(item.detail)]
		option_button.icon = load(str(item.icon))
		option_button.expand_icon = false
		option_button.add_theme_constant_override("icon_max_width", 34)
		option_button.add_theme_font_size_override("font_size", 15)
		option_button.add_theme_color_override("font_color", CREAM)
		var option_style := StyleBoxFlat.new()
		option_style.bg_color = item.color
		option_style.set_corner_radius_all(13)
		option_style.content_margin_left = 12
		option_style.content_margin_right = 12
		option_button.add_theme_stylebox_override("normal", option_style)
		var option_hover := option_style.duplicate()
		option_hover.bg_color = item.color.lightened(0.1)
		option_button.add_theme_stylebox_override("hover", option_hover)
		var option_id: int = int(item.id)
		option_button.pressed.connect(func():
			overlay.queue_free()
			_on_hint_menu_selected(option_id)
		)
		stack.add_child(option_button)
	var close := _make_button("بستن", PANEL_ALT, CREAM)
	close.pressed.connect(overlay.queue_free)
	stack.add_child(close)

func _on_hint_menu_selected(option: int) -> void:
	if option == 0:
		await _use_hint()
	elif option == 1:
		await _use_hint_clue("first_letter")
	elif option == 3:
		await _use_hint_clue("highlight_letter")

func _use_hint_clue(hint_type: String) -> void:
	if duel_mode:
		var duel_hint: Dictionary = await CloudAccount.spend_duel_hint(duel_match_id, hint_type)
		if not duel_hint.get("ok", false):
			_set_status(str(duel_hint.get("error", "راهنمای مسابقه انجام نشد.")), RED)
			return
		var hint_data: Dictionary = duel_hint.get("result", {})
		_apply_cloud_profile(duel_hint.get("profile", {}))
		var clue := str(hint_data.get("clue", ""))
		_animate_coin_reward(-int(hint_data.get("cost", 0)))
		if hint_type == "first_letter":
			_set_status("حرف اول یکی از پاسخ‌های حل‌نشده: «%s»" % clue, GOLD)
		else:
			for button in letter_buttons:
				if button.text == clue:
					button.modulate = Color("#ffe08a")
					var pulse := create_tween()
					pulse.tween_property(button, "scale", Vector2(1.28, 1.28), 0.18)
					pulse.tween_property(button, "scale", Vector2.ONE, 0.24)
					pulse.tween_property(button, "modulate", Color.WHITE, 0.35)
					break
			_set_status("یک حرف موردنیاز در صفحه مشخص شد.", GOLD)
		if hint_data.get("result", {}).get("match_complete", false):
			_show_duel_result(str(hint_data.get("result", {}).get("winner_id", "")), int(hint_data.get("result", {}).get("elapsed_ms", 0)))
		elif hint_data.get("result", {}).get("round_complete", false):
			await _refresh_duel_round()
		_update_controls()
		return
	var costs := {"first_letter": 8, "highlight_letter": 12}
	var cost := int(costs.get(hint_type, 0))
	if cost <= 0:
		return
	var stage_id := int(levels[level_index].get("id", level_index + 1))
	var solved := _words_for_current_level()
	var remaining: Array[String] = []
	for answer in levels[level_index].get("answers", []):
		var word := str(answer)
		if not solved.has(word):
			remaining.append(word)
	if remaining.is_empty():
		_set_status("همه واژه‌های این مرحله کشف شده‌اند.", GOLD)
		return

	var target := ""
	var target_letter_index := -1
	if hint_type == "first_letter":
		var save_key := "first_letter_%d" % stage_id
		var used_words: Array = hint_history.get(save_key, [])
		var used_initials: Dictionary = {}
		for used_word in used_words:
			if not str(used_word).is_empty():
				used_initials[str(used_word).substr(0, 1)] = true
		for candidate in remaining:
			var initial := candidate.substr(0, 1)
			if not used_initials.has(initial):
				target = candidate
				break
		if target.is_empty():
			_set_status("حرف اول همه پاسخ‌های باقی‌مانده را قبلاً دیده‌ای.", GOLD)
			return
	else:
		var letters: Array = levels[level_index].get("letters", [])
		var save_key := "highlight_%d" % stage_id
		var used_indices: Array = hint_history.get(save_key, [])
		for candidate in remaining:
			for character in candidate:
				for i in range(letters.size()):
					if str(letters[i]) == str(character) and not used_indices.has(i):
						target = candidate
						target_letter_index = i
						break
				if target_letter_index >= 0:
					break
			if target_letter_index >= 0:
				break
		if target_letter_index < 0:
			_set_status("همه حروف قابل استفاده قبلاً برجسته شده‌اند.", GOLD)
			return

	var clue_key := target.substr(0, 1) if hint_type == "first_letter" else ""
	if hint_type == "highlight_letter":
		var hint_letters: Array = levels[level_index].get("letters", [])
		if target_letter_index >= 0 and target_letter_index < hint_letters.size():
			clue_key = str(hint_letters[target_letter_index])
	if coins < cost:
		_set_status("برای این راهنما سکه کافی نداری.", RED)
		return
	if guest_mode:
		coins -= cost
	else:
		var result: Dictionary = await CloudAccount.use_hint_clue(hint_type, stage_id, clue_key)
		if not result.get("ok", false):
			_set_status(str(result.get("error", "استفاده از راهنما انجام نشد.")), RED)
			return
		_apply_cloud_profile(result.get("profile", {}))

	if hint_type == "first_letter":
		var first_key := "first_letter_%d" % stage_id
		var first_used: Array = hint_history.get(first_key, [])
		var revealed_initial := target.substr(0, 1)
		for candidate in remaining:
			if candidate.substr(0, 1) == revealed_initial and not first_used.has(candidate):
				first_used.append(candidate)
		hint_history[first_key] = first_used
		_set_status("حرف اول واژه‌ای که هنوز پیدا نکرده‌ای: «%s»" % target.substr(0, 1), GOLD)
	else:
		var highlight_key := "highlight_%d" % stage_id
		var highlighted: Array = hint_history.get(highlight_key, [])
		var stage_letters: Array = levels[level_index].get("letters", [])
		var chosen_letter := str(stage_letters[target_letter_index])
		for i in range(stage_letters.size()):
			if str(stage_letters[i]) == chosen_letter and not highlighted.has(i):
				highlighted.append(i)
		hint_history[highlight_key] = highlighted
		if target_letter_index >= 0 and target_letter_index < letter_buttons.size():
			var button: Button = letter_buttons[target_letter_index]
			button.modulate = Color("#ffe08a")
			var pulse := create_tween()
			pulse.tween_property(button, "scale", Vector2(1.28, 1.28), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pulse.tween_property(button, "scale", Vector2.ONE, 0.24)
			pulse.tween_property(button, "modulate", Color.WHITE, 0.35)
		_set_status("این حرف در یکی از واژه‌های کشف‌نشده وجود دارد.", GOLD)
	_animate_coin_reward(-cost)
	_save()
	_update_controls()

func _use_hint() -> void:
	if duel_mode:
		var duel_hint: Dictionary = await CloudAccount.spend_duel_hint(duel_match_id, "reveal_word")
		if not duel_hint.get("ok", false):
			_set_status(str(duel_hint.get("error", "راهنمای مسابقه انجام نشد.")), RED)
			return
		var hint_data: Dictionary = duel_hint.get("result", {})
		_apply_cloud_profile(duel_hint.get("profile", {}))
		_animate_coin_reward(-int(hint_data.get("cost", 0)))
		_set_status("یک واژه با راهنمای مسابقه آشکار شد.", GOLD)
		if hint_data.get("result", {}).get("match_complete", false):
			_show_duel_result(str(hint_data.get("result", {}).get("winner_id", "")), int(hint_data.get("result", {}).get("elapsed_ms", 0)))
		else:
			await _refresh_duel_round()
		return
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
		coin_label.text = "%d" % coins
	if hint_button != null and is_instance_valid(hint_button):
		hint_button.disabled = _is_level_complete() or coins < (24 if duel_mode else 5)
	if submit_button != null and is_instance_valid(submit_button):
		submit_button.disabled = _is_level_complete() or selected_word.is_empty()

func _handle_back_request() -> void:
	if back_confirm != null and back_confirm.visible:
		return
	if current_page == "map" or current_page == "auth":
		if back_confirm != null:
			back_confirm.popup_centered()
		return
	match current_page:
		"game":
			_show_map()
		"duel_game":
			_show_duel_invites()
		"duel_result":
			_show_duel_invites()
		"public_profile":
			_show_leaderboard()
		"sticker_picker":
			if not active_group_chat_id.is_empty():
				_show_group_chat(active_group_chat_id, active_group_chat_name)
			else:
				_show_global_chat()
		"avatar_crop":
			_show_profile()
		_:
			var parent_page := str(back_navigation.get(current_page, "map"))
			_navigate_back_to(parent_page)

func _navigate_back_to(page: String) -> void:
	match page:
		"profile": _show_profile()
		"global_chat": _show_global_chat()
		"groups": _show_groups()
		"leaderboard": _show_leaderboard()
		"duel_invites": _show_duel_invites()
		"map": _show_map()
		_: _show_map()

func _confirm_app_exit() -> void:
	_save()
	if not guest_mode and CloudAccount.is_authenticated():
		await CloudAccount.end_session()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_save()
		if not guest_mode and CloudAccount.is_authenticated():
			await CloudAccount.touch_session()
