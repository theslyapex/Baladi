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
var experience_total := 0
var experience_level := 1
var experience_initialized := false
var coins := 100
var level_solved: Dictionary = {}
var completed_levels: Array = []
var levels_completed_count := 0
var bonus_word_set: Dictionary = {}
var level_bonus_found: Dictionary = {}
var hint_history: Dictionary = {}
var guest_mode := false
var sfx_player: AudioStreamPlayer
var selected_indices: Array[int] = []
var selected_word := ""
var is_dragging := false
var active_pointer := -1
var pending_word_syncs := 0

var page_box: VBoxContainer
var content_box: VBoxContainer
var bottom_nav_panel: PanelContainer
var bottom_nav_buttons: Dictionary = {}
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
var notification_poll_timer: Timer
var notifications_poll_busy := false
var push_notifications_plugin: Object
var exit_button: Button
var profile_button: Button
var profile_name_input: LineEdit
var profile_rename_button: Button
var profile_status_label: Label
var display_name := "بازیکن"
var account_player_tag := ""
var is_verified := false
var diamonds := 0
var name_change_count := 0
var sound_enabled := true
var daily_streak := 0
var last_checkin_date := ""
var avatar_path := ""
var avatar_unlocked := false
var equipped_frame_id := "frame_default"
var equipped_avatar_id := ""
var wins := 0
var losses := 0
var chat_unlocked := true
var chat_poll_timer: Timer
var chat_messages_box: VBoxContainer
var chat_scroll_container: ScrollContainer
var chat_scroll_to_bottom := true
var chat_long_press_timer: Timer
var pending_chat_message_id := 0
var pending_chat_player_id := ""
var chat_input: LineEdit
var chat_status_label: Label
var chat_poll_busy := false
var active_group_chat_id := ""
var active_group_chat_name := ""
var active_group_role := ""
var public_profile_return_page := "leaderboard"
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
var stage_touch_start_y := 0.0
var stage_touch_scroll_start := 0
var stage_touch_scrolling := false
var page_touch_scroll: ScrollContainer
var page_touch_active := false
var page_touch_scrolling := false
var page_touch_start := Vector2.ZERO
var page_touch_scroll_start := 0

var startup_action_taken := false
var startup_restore_in_progress := false
var current_page := "auth"
var back_confirm: ConfirmationDialog
var back_navigation := {
	"profile": "map", "global_chat": "map", "groups": "map", "settings": "map", "privacy": "settings", "faq": "settings",
	"group_chat": "groups", "sticker_picker": "global_chat",
	"cosmetic_shop": "profile", "leaderboard": "map",
	"duel_invites": "duel_hub", "duel_hub": "profile", "duel_game": "duel_hub",
	"matchmaking": "map", "matchmaking_tag": "matchmaking", "matchmaking_wait": "matchmaking",
	"duel_result": "duel_invites", "public_profile": "leaderboard",
	"avatar_crop": "profile", "game": "map", "map": "exit"
}

func _ready() -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("BaladiPushNotifications"):
		push_notifications_plugin = Engine.get_singleton("BaladiPushNotifications")
		if not push_notifications_plugin.notification_token_received.is_connected(_on_push_notification_token_received):
			push_notifications_plugin.notification_token_received.connect(_on_push_notification_token_received)
		if not push_notifications_plugin.notification_error.is_connected(_on_push_notification_error):
			push_notifications_plugin.notification_error.connect(_on_push_notification_error)
		if not push_notifications_plugin.notification_opened.is_connected(_on_push_notification_opened):
			push_notifications_plugin.notification_opened.connect(_on_push_notification_opened)
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

func _on_push_notification_token_received(token: String) -> void:
	if not CloudAccount.is_authenticated():
		return
	var result: Dictionary = await CloudAccount.register_push_token(token, OS.get_model_name())
	if not result.get("ok", false):
		push_warning("Baladi push token registration failed: " + str(result.get("error", "")))

func _on_push_notification_error(message: String) -> void:
	push_warning("Baladi push notifications: " + message)

func _on_push_notification_opened(_payload: String) -> void:
	if CloudAccount.is_authenticated():
		await _check_admin_notifications()

func _request_push_notifications() -> void:
	if push_notifications_plugin == null or not CloudAccount.is_authenticated():
		return
	if push_notifications_plugin.hasPermission():
		push_notifications_plugin.getToken()
		return
	var cfg := ConfigFile.new()
	var asked_before := cfg.load("user://baladi_push_permission.cfg") == OK and bool(cfg.get_value("push", "permission_requested", false))
	if asked_before:
		return
	cfg.set_value("push", "permission_requested", true)
	cfg.save("user://baladi_push_permission.cfg")
	push_notifications_plugin.requestPermission()

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
	is_verified = bool(profile.get("is_verified", false))
	_load_save()
	coins = int(profile.get("coins", 100))
	diamonds = int(profile.get("diamonds", 0))
	name_change_count = int(profile.get("name_change_count", 0))
	var profile_name = profile.get("display_name", null)
	display_name = _safe_player_name(profile_name, CloudAccount.display_name)
	account_player_tag = str(profile.get("player_tag", ""))
	if display_name.is_empty():
		display_name = CloudAccount.display_name if not CloudAccount.display_name.is_empty() else "بازیکن"
	daily_streak = int(profile.get("daily_streak", 0))
	last_checkin_date = str(profile.get("last_checkin_date", ""))
	avatar_path = str(profile.get("avatar_path", ""))
	avatar_unlocked = bool(profile.get("avatar_unlocked", false))
	equipped_frame_id = str(profile.get("equipped_frame_id", "frame_default"))
	equipped_avatar_id = str(profile.get("equipped_avatar_id", ""))
	wins = int(profile.get("wins", 0))
	losses = int(profile.get("losses", 0))
	# Public chat is available to every signed-in player; no coin unlock flag is required.
	chat_unlocked = true
	cloud_current_level = int(profile.get("current_level", 1))
	experience_total = int(profile.get("xp_total", 0))
	experience_level = clampi(int(profile.get("experience_level", min(500, floori(float(experience_total) / 1000.0) + 1))), 1, 500)
	experience_initialized = true
	level_index = clampi(cloud_current_level - 1, 0, max(0, levels.size() - 1))
	var remote_completed = profile.get("completed_levels", [])
	if remote_completed is Array:
		completed_levels = remote_completed.duplicate()
	levels_completed_count = maxi(levels_completed_count, int(profile.get("levels_completed", completed_levels.size())))
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
	if notification_poll_timer == null:
		notification_poll_timer = Timer.new()
		notification_poll_timer.wait_time = 30.0
		notification_poll_timer.timeout.connect(_check_admin_notifications)
		add_child(notification_poll_timer)
	notification_poll_timer.start()
	_show_map()
	_request_push_notifications()
	await _check_admin_notifications()

func _enter_guest() -> void:
	startup_action_taken = true
	guest_mode = true
	_load_save()
	experience_initialized = true
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
		await _check_admin_notifications()

func _check_admin_notifications() -> void:
	if notifications_poll_busy or guest_mode or not CloudAccount.is_authenticated():
		return
	notifications_poll_busy = true
	var response: Dictionary = await CloudAccount.fetch_admin_notifications()
	notifications_poll_busy = false
	if not response.get("ok", false):
		return
	var notifications = response.get("notifications", [])
	if not notifications is Array or notifications.is_empty():
		return
	var lines := PackedStringArray()
	for item in notifications:
		if item is Dictionary:
			var title := str(item.get("title", "اعلان جدید"))
			var body := str(item.get("body", ""))
			lines.append("◆ " + title + "\\n" + body)
	if lines.is_empty():
		return
	var dialog := AcceptDialog.new()
	dialog.title = "اعلان‌های جدید بلدی؟"
	dialog.dialog_text = "\\n\\n".join(lines)
	dialog.ok_button_text = "متوجه شدم"
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(560, 420))

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
	experience_total = int(cfg.get_value("player", "xp_total", 0))
	experience_level = clampi(int(cfg.get_value("player", "experience_level", min(500, floori(float(experience_total) / 1000.0) + 1))), 1, 500)
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
	if value == null:
		return fallback
	var candidate := str(value).strip_edges()
	if candidate.is_empty() or candidate.to_lower() in ["null", "none", "<null>", "nil"]:
		return fallback
	return candidate

func _format_coin_price(value: Variant) -> String:
	return str(maxi(0, int(value)))

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
	cfg.set_value("player", "xp_total", experience_total)
	cfg.set_value("player", "experience_level", experience_level)
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
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	page_box = VBoxContainer.new()
	page_box.name = "PageBox"
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_box.add_theme_constant_override("separation", 11)
	margin.add_child(page_box)

	var header_panel := _panel(Color("#416b59"))
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.add_child(header_panel)
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 9)
	header_panel.add_child(header)

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
	exit_button.custom_minimum_size = Vector2(156, 44)
	exit_button.add_theme_font_size_override("font_size", 13)
	exit_button.clip_text = false
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

	bottom_nav_panel = PanelContainer.new()
	bottom_nav_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_nav_panel.visible = false
	var nav_style := StyleBoxFlat.new()
	nav_style.bg_color = Color("#102b26")
	nav_style.border_color = Color("#345b4d")
	nav_style.set_border_width_all(1)
	nav_style.set_corner_radius_all(18)
	nav_style.content_margin_left = 6
	nav_style.content_margin_right = 6
	nav_style.content_margin_top = 6
	nav_style.content_margin_bottom = 6
	bottom_nav_panel.add_theme_stylebox_override("panel", nav_style)
	page_box.add_child(bottom_nav_panel)
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 5)
	bottom_nav_panel.add_child(nav_row)
	var nav_specs := [
		["map", "مراحل", _show_map],
		["groups", "گروه‌ها", _show_groups],
		["global_chat", "گفت‌وگو", _show_global_chat],
		["leaderboard", "رتبه‌بندی", _show_leaderboard]
	]
	for spec in nav_specs:
		var nav_button := _make_button(str(spec[1]), Color("#173a32"), MUTED)
		nav_button.custom_minimum_size = Vector2(0, 44)
		nav_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_button.add_theme_font_size_override("font_size", 11)
		nav_button.pressed.connect(spec[2])
		nav_row.add_child(nav_button)
		bottom_nav_buttons[str(spec[0])] = nav_button

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

func _refresh_bottom_nav() -> void:
	if bottom_nav_buttons.is_empty():
		return
	var active_page := current_page
	if current_page == "group_chat":
		active_page = "groups"
	elif current_page == "game":
		active_page = "map"
	for page_key in bottom_nav_buttons.keys():
		var nav_button: Button = bottom_nav_buttons[page_key]
		if not is_instance_valid(nav_button):
			continue
		var active := str(page_key) == active_page
		var base := StyleBoxFlat.new()
		base.bg_color = Color("#745c31") if active else Color("#173a32")
		base.border_color = GOLD if active else Color("#2d5146")
		base.set_border_width_all(1)
		base.set_corner_radius_all(12)
		base.content_margin_left = 4
		base.content_margin_right = 4
		base.content_margin_top = 6
		base.content_margin_bottom = 6
		nav_button.add_theme_stylebox_override("normal", base)
		var hover := base.duplicate()
		hover.bg_color = base.bg_color.lightened(0.10)
		nav_button.add_theme_stylebox_override("hover", hover)
		var pressed := base.duplicate()
		pressed.bg_color = base.bg_color.darkened(0.12)
		nav_button.add_theme_stylebox_override("pressed", pressed)
		nav_button.add_theme_color_override("font_color", GOLD if active else MUTED)
		nav_button.add_theme_color_override("font_hover_color", CREAM)

func _add_page_heading(title_text: String, subtitle_text: String = "") -> void:
	var heading_panel := _panel(Color("#9a7b42"))
	heading_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(heading_panel)
	var heading_body := VBoxContainer.new()
	heading_body.add_theme_constant_override("separation", 4)
	heading_panel.add_child(heading_body)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	heading_body.add_child(title)
	if not subtitle_text.is_empty():
		var subtitle := Label.new()
		subtitle.text = subtitle_text
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle.add_theme_font_size_override("font_size", 12)
		subtitle.add_theme_color_override("font_color", MUTED)
		heading_body.add_child(subtitle)

func _play_page_entry() -> void:
	if content_box == null or not is_instance_valid(content_box):
		return
	content_box.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(content_box, "modulate:a", 1.0, 0.22)

func _clear_content() -> void:
	if bottom_nav_panel != null and is_instance_valid(bottom_nav_panel):
		bottom_nav_panel.visible = current_page != "auth"
		_refresh_bottom_nav()
	stage_scroll = null
	stage_touch_active = false
	is_dragging = false
	active_pointer = -1
	if chat_poll_timer != null:
		chat_poll_timer.stop()
	chat_messages_box = null
	chat_scroll_container = null
	chat_input = null
	chat_status_label = null
	trace_line.clear_points()
	trace_line.visible = false
	for child in content_box.get_children():
		child.queue_free()
	call_deferred("_play_page_entry")

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
	is_verified = bool(profile.get("is_verified", is_verified))
	diamonds = int(profile.get("diamonds", diamonds))
	name_change_count = int(profile.get("name_change_count", name_change_count))
	var profile_name = profile.get("display_name", null)
	account_player_tag = str(profile.get("player_tag", account_player_tag))
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
	equipped_avatar_id = str(profile.get("equipped_avatar_id", equipped_avatar_id))
	wins = int(profile.get("wins", wins))
	losses = int(profile.get("losses", losses))
	# Keep legacy profile flags from re-locking the public chat.
	chat_unlocked = true
	cloud_current_level = int(profile.get("current_level", cloud_current_level))
	var previous_experience_level := experience_level
	experience_total = int(profile.get("xp_total", experience_total))
	experience_level = clampi(int(profile.get("experience_level", min(500, floori(float(experience_total) / 1000.0) + 1))), 1, 500)
	if experience_initialized and experience_level > previous_experience_level:
		_show_experience_level_up(experience_level)
	var remote_completed = profile.get("completed_levels", completed_levels)
	if remote_completed is Array:
		completed_levels = remote_completed.duplicate()
	levels_completed_count = maxi(levels_completed_count, int(profile.get("levels_completed", completed_levels.size())))
	_save()
	_update_controls()

func _show_map() -> void:
	current_page = "map"
	if chat_poll_timer != null:
		chat_poll_timer.stop()
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

	_add_page_heading("نقشه مراحل", "۲۰۰ مرحله برای کشف واژه‌ها و سرزمین‌های تازه")
	var greeting_panel := _panel(Color("#9a8050"))
	greeting_panel.add_theme_constant_override("separation", 0)
	content_box.add_child(greeting_panel)
	var greeting := Label.new()
	greeting.text = "سلام، %s! آماده‌ای؟" % display_name
	greeting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	greeting.add_theme_font_size_override("font_size", 17)
	greeting.add_theme_color_override("font_color", GOLD)
	greeting_panel.add_child(greeting)

	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 10)
	content_box.add_child(action_row)
	var incoming_duels := _make_button("◈  درخواست‌های مسابقه\nدعوت‌های دریافتی", Color("#173d43"), CREAM)
	incoming_duels.custom_minimum_size = Vector2(0, 76)
	incoming_duels.add_theme_font_size_override("font_size", 14)
	_style_home_action_button(incoming_duels, Color("#6ca9b4"))
	incoming_duels.pressed.connect(_show_duel_invites)
	action_row.add_child(incoming_duels)
	_update_duel_invite_badge(incoming_duels)
	var matchmaking_home := _make_button("✦  حریف‌یابی آنلاین\nپیدا کردن رقیب", Color("#51402a"), CREAM)
	matchmaking_home.custom_minimum_size = Vector2(0, 76)
	matchmaking_home.add_theme_font_size_override("font_size", 14)
	_style_home_action_button(matchmaking_home, GOLD)
	matchmaking_home.pressed.connect(_show_matchmaking)
	action_row.add_child(matchmaking_home)

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

	var guide_panel := _panel(Color("#927a48"))
	guide_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(guide_panel)
	var guide_box := VBoxContainer.new()
	guide_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_box.add_theme_constant_override("separation", 5)
	guide_panel.add_child(guide_box)
	var guide_title := Label.new()
	guide_title.text = "سفر تو ادامه دارد"
	guide_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide_title.add_theme_font_size_override("font_size", 17)
	guide_title.add_theme_color_override("font_color", GOLD)
	guide_box.add_child(guide_title)
	var guide_text := Label.new()
	guide_text.text = "هر ۲۰ مرحله، سرزمینی تازه با رازها و واژه‌های جدید پیش روی توست."
	guide_text.custom_minimum_size = Vector2(0, 34)
	guide_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	guide_text.add_theme_font_size_override("font_size", 13)
	guide_text.add_theme_color_override("font_color", CREAM)
	guide_box.add_child(guide_text)

	var map_frame := _panel(Color("#9a8050"))
	map_frame.add_theme_constant_override("separation", 0)
	content_box.add_child(map_frame)
	var map_art := TextureRect.new()
	map_art.texture = load("res://assets/backgrounds/wordlands-cinematic.jpg")
	map_art.custom_minimum_size = Vector2(0, 154)
	map_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(map_art)

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

	var experience_panel := _panel(Color("#a77a35"))
	content_box.add_child(experience_panel)
	var experience_box := VBoxContainer.new()
	experience_box.add_theme_constant_override("separation", 6)
	experience_panel.add_child(experience_box)
	var experience_title := Label.new()
	experience_title.text = "سطح تجربه  ·  سطح %d" % experience_level
	experience_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	experience_title.add_theme_font_size_override("font_size", 17)
	experience_title.add_theme_color_override("font_color", GOLD)
	experience_box.add_child(experience_title)
	var experience_detail := Label.new()
	if experience_level >= 500:
		experience_detail.text = "به بالاترین سطح تجربه رسیدی!  ·  %s XP" % _format_coin_price(experience_total)
	else:
		experience_detail.text = "%s از ۱٬۰۰۰ XP تا سطح بعدی" % _format_coin_price(experience_total % 1000)
	experience_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	experience_detail.add_theme_font_size_override("font_size", 12)
	experience_detail.add_theme_color_override("font_color", CREAM)
	experience_box.add_child(experience_detail)
	var experience_progress := ProgressBar.new()
	experience_progress.min_value = 0
	experience_progress.max_value = 1000
	experience_progress.value = 1000 if experience_level >= 500 else experience_total % 1000
	experience_progress.show_percentage = false
	experience_progress.custom_minimum_size.y = 9
	experience_box.add_child(experience_progress)

	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 9)
	content_box.add_child(utility_row)
	var shop_nav := _make_button("فروشگاه شخصی‌سازی", Color("#765a31"), CREAM)
	shop_nav.custom_minimum_size = Vector2(0, 48)
	shop_nav.pressed.connect(_show_cosmetic_shop)
	utility_row.add_child(shop_nav)
	var settings_nav := _make_button("تنظیمات", Color("#245448"), CREAM)
	settings_nav.custom_minimum_size = Vector2(0, 48)
	settings_nav.pressed.connect(_show_settings)
	utility_row.add_child(settings_nav)


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
		chapter_banner.custom_minimum_size = Vector2(0, 128)
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
		var chapter_status := Label.new()
		var chapter_is_active := cloud_current_level >= first_level and cloud_current_level <= last_level
		var chapter_is_finished := chapter_done >= last_index - first_index
		chapter_status.text = "✦ فصل جاری تو" if chapter_is_active else ("✓ این سرزمین کامل شده" if chapter_is_finished else "برای رسیدن به این سرزمین، مسیرت را ادامه بده")
		chapter_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chapter_status.add_theme_font_size_override("font_size", 11)
		chapter_status.add_theme_color_override("font_color", GOLD if chapter_is_active or chapter_is_finished else MUTED)
		chapter_box.add_child(chapter_status)

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
			var previous_stage_id := int(levels[stage_index - 1].get("id", stage_index)) if stage_index > 0 else 0
			# Progress may arrive with the completed list or current_level updated first.
			# Either authoritative signal must unlock the immediate next stage.
			var is_open := stage_id <= cloud_current_level or completed_levels.has(stage_id) or (stage_index > 0 and completed_levels.has(previous_stage_id))
			var is_current := stage_id == cloud_current_level
			var stage_button := Button.new()
			stage_button.custom_minimum_size = Vector2(0, 68)
			stage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stage_button.text = "✓" if is_done else ("▶\n%02d" % stage_id if is_current else ("قفل" if not is_open else "%02d" % stage_id))
			stage_button.tooltip_text = "مرحله %d · %s" % [stage_id, ("تکمیل‌شده" if is_done else ("مرحله فعلی" if is_current else ("باز" if is_open else "قفل‌شده")))]
			stage_button.disabled = not is_open
			stage_button.add_theme_font_size_override("font_size", 16 if is_current else 17)
			stage_button.add_theme_color_override("font_color", Color("#fff4d0") if is_current else (GOLD if is_done else (CREAM if is_open else Color("#71837d"))))
			stage_button.add_theme_color_override("font_disabled_color", Color("#71837d"))
			var node_style := StyleBoxFlat.new()
			node_style.bg_color = Color("#246d59") if is_current else (Color("#315f4f") if is_done else (Color("#183b34") if is_open else Color("#142d29")))
			node_style.border_color = GOLD if is_current or is_done else (TEAL if is_open else Color("#29443d"))
			node_style.set_border_width_all(2 if is_current or is_done else 1)
			node_style.set_corner_radius_all(21)
			node_style.shadow_color = Color(0, 0, 0, 0.24)
			node_style.shadow_size = 7 if is_current else (3 if is_done else 1)
			node_style.shadow_offset = Vector2(0, 3)
			node_style.content_margin_left = 2
			node_style.content_margin_right = 2
			stage_button.add_theme_stylebox_override("normal", node_style)
			var node_hover := node_style.duplicate()
			node_hover.bg_color = node_style.bg_color.lightened(0.12)
			node_hover.shadow_size = 8
			stage_button.add_theme_stylebox_override("hover", node_hover)
			var node_pressed := node_style.duplicate()
			node_pressed.bg_color = node_style.bg_color.darkened(0.12)
			node_pressed.shadow_size = 1
			stage_button.add_theme_stylebox_override("pressed", node_pressed)
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
			levels_completed_count = 0
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
				levels_completed_count = 0
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

	_add_page_heading("پروفایل بازیکن", "پیشرفت، آمار و تنظیمات هویت بازی تو")

	var xp_panel := _panel(Color("#d2a84d"))
	xp_panel.custom_minimum_size.y = 112
	content_box.add_child(xp_panel)
	var xp_box := VBoxContainer.new()
	xp_box.add_theme_constant_override("separation", 7)
	xp_panel.add_child(xp_box)
	var xp_header := HBoxContainer.new()
	xp_header.add_theme_constant_override("separation", 8)
	xp_box.add_child(xp_header)
	var xp_level_label := Label.new()
	xp_level_label.text = "سطح تجربه  %d / ۵۰۰" % experience_level
	xp_level_label.add_theme_font_size_override("font_size", 18)
	xp_level_label.add_theme_color_override("font_color", GOLD)
	xp_header.add_child(xp_level_label)
	var xp_total_label := Label.new()
	xp_total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xp_total_label.text = "%s XP" % _format_number(experience_total)
	xp_total_label.add_theme_font_size_override("font_size", 15)
	xp_total_label.add_theme_color_override("font_color", CREAM)
	xp_header.add_child(xp_total_label)
	var xp_bar := ProgressBar.new()
	xp_bar.custom_minimum_size.y = 17
	xp_bar.show_percentage = false
	var xp_into_level := experience_total - ((experience_level - 1) * 1000)
	if experience_level >= 500:
		xp_into_level = 1000
	xp_bar.max_value = 1000
	var xp_target_value := clampi(xp_into_level, 0, 1000)
	xp_bar.value = 0
	var xp_bg := StyleBoxFlat.new()
	xp_bg.bg_color = Color("#09201d")
	xp_bg.set_corner_radius_all(9)
	xp_bar.add_theme_stylebox_override("background", xp_bg)
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = Color("#edc879")
	xp_fill.set_corner_radius_all(9)
	xp_bar.add_theme_stylebox_override("fill", xp_fill)
	xp_box.add_child(xp_bar)
	var xp_tween := create_tween()
	xp_tween.tween_property(xp_bar, "value", xp_target_value, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var xp_hint := Label.new()
	xp_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_hint.add_theme_font_size_override("font_size", 12)
	xp_hint.add_theme_color_override("font_color", MUTED)
	xp_hint.text = "بالاترین سطح را به دست آورده‌ای!" if experience_level >= 500 else "%s از ۱٬۰۰۰ XP تا سطح بعدی" % _format_number(xp_into_level)
	xp_box.add_child(xp_hint)

	var identity := _panel(Color("#a77a35"))
	identity.custom_minimum_size.y = 132
	content_box.add_child(identity)
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 14)
	identity.add_child(identity_row)
	var avatar := _build_avatar_widget(avatar_path, equipped_frame_id, 104, equipped_avatar_id)
	identity_row.add_child(avatar)
	identity.custom_minimum_size.y = 132
	var identity_info := VBoxContainer.new()
	identity_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_info.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_info.add_theme_constant_override("separation", 4)
	identity_row.add_child(identity_info)
	var player_name := Label.new()
	player_name.text = display_name + ("  ✓" if is_verified else "")
	player_name.add_theme_font_size_override("font_size", 22)
	player_name.add_theme_color_override("font_color", CREAM)
	identity_info.add_child(player_name)
	if is_verified:
		var verified_note := Label.new()
		verified_note.text = "حساب رسمی و تأییدشده"
		verified_note.add_theme_font_size_override("font_size", 12)
		verified_note.add_theme_color_override("font_color", Color("#35a9ff"))
		identity_info.add_child(verified_note)
	var player_tag := Label.new()
	player_tag.text = "ماجراجوی واژه‌ها  ·  سطح تجربه %d" % experience_level
	player_tag.add_theme_font_size_override("font_size", 13)
	player_tag.add_theme_color_override("font_color", GOLD)
	identity_info.add_child(player_tag)
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	identity_info.add_child(tag_row)
	var tag_value := Label.new()
	tag_value.text = "تگ بازیکن: " + (account_player_tag if not account_player_tag.is_empty() else "در حال دریافت")
	tag_value.add_theme_font_size_override("font_size", 14)
	tag_value.add_theme_color_override("font_color", GOLD)
	tag_row.add_child(tag_value)
	if not account_player_tag.is_empty():
		var copy_tag := _make_button("کپی", Color("#287c68"), CREAM)
		copy_tag.custom_minimum_size = Vector2(68, 34)
		copy_tag.pressed.connect(func():
			DisplayServer.clipboard_set(account_player_tag)
			_set_status("تگ بازیکن کپی شد.", GREEN)
		)
		tag_row.add_child(copy_tag)

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
	stats_grid.layout_direction = Control.LAYOUT_DIRECTION_RTL
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("h_separation", 9)
	stats_grid.add_theme_constant_override("v_separation", 9)
	content_box.add_child(stats_grid)
	# Two right-to-left columns create four compact rows for the seven profile metrics.
	_add_profile_stat(stats_grid, "مرحله فعلی", "%d / %d" % [cloud_current_level, levels.size()], GOLD)
	_add_profile_stat(stats_grid, "مراحل کامل‌شده", str(maxi(levels_completed_count, completed_levels.size())), GREEN)
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
	var duel_hub_button := _make_button("ورود به میدان رقابت آنلاین", Color("#765a31"), CREAM)
	duel_hub_button.custom_minimum_size.y = 60
	duel_hub_button.add_theme_font_size_override("font_size", 17)
	duel_hub_button.pressed.connect(_show_duel_hub)
	content_box.add_child(duel_hub_button)

	profile_status_label = Label.new()
	profile_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	profile_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_status_label.add_theme_color_override("font_color", MUTED)
	content_box.add_child(profile_status_label)
	var back := _make_button("بازگشت به نقشه مراحل", Color("#294c43"), CREAM)
	back.pressed.connect(_show_map)
	content_box.add_child(back)


func _format_number(value: int) -> String:
	return str(maxi(0, value))

func _add_local_experience(amount: int) -> void:
	if amount <= 0 or experience_level >= 500:
		return
	var previous_level := experience_level
	experience_total = mini(499000, experience_total + amount)
	experience_level = clampi(min(500, floori(float(experience_total) / 1000.0) + 1), 1, 500)
	_save()
	if experience_level > previous_level:
		_show_experience_level_up(experience_level)


func _show_experience_level_up(new_level: int) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "ارتقای سطح!"
	dialog.dialog_text = "تبریک! به سطح %d رسیدی.\nماجراجویی واژه‌ها ادامه دارد!" % new_level
	dialog.ok_button_text = "ادامه می‌دهم"
	add_child(dialog)
	dialog.popup_centered(Vector2i(360, 220))
	dialog.pivot_offset = dialog.size / 2.0
	dialog.scale = Vector2(0.72, 0.72)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(dialog, "scale", Vector2.ONE, 0.38)
	dialog.confirmed.connect(dialog.queue_free)
	_spawn_floating_text("ارتقای سطح تجربه  +%d" % new_level, GOLD)


func _style_home_action_button(button: Button, accent: Color) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color("#fff3d0"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#142f2b")
	normal.border_color = accent.darkened(0.12)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(19)
	normal.shadow_color = Color(0, 0, 0, 0.34)
	normal.shadow_size = 9
	normal.shadow_offset = Vector2(0, 4)
	normal.content_margin_left = 7
	normal.content_margin_right = 7
	normal.content_margin_top = 9
	normal.content_margin_bottom = 9
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("#1c4039")
	hover.border_color = accent.lightened(0.12)
	hover.shadow_size = 12
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("#0d2622")
	pressed.shadow_size = 2
	pressed.shadow_offset = Vector2(0, 1)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)

func _update_duel_invite_badge(button: Button) -> void:
	if guest_mode:
		return
	var result: Dictionary = await CloudAccount.get_duel_invites()
	if not is_instance_valid(button) or current_page != "map":
		return
	if result.get("ok", false):
		var count := (result.get("invites", []) as Array).size()
		button.text = "◈  درخواست‌های مسابقه\n%d دعوت تازه" % count if count > 0 else "◈  درخواست‌های مسابقه\nدعوت‌های دریافتی"
func _show_matchmaking() -> void:
	current_page = "matchmaking"
	_clear_content()
	_add_section_art("assets/backgrounds/letter-wheel.svg", 110)
	_add_page_heading("حریف‌یابی", "رقیب دلخواهت را پیدا کن و وارد مسابقه شو")
	var intro := _panel(GOLD)
	content_box.add_child(intro)
	var intro_label := Label.new()
	intro_label.text = "دو راه برای شروع رقابت داری؛ با یک بازیکن آنلاین به‌صورت تصادفی جفت شو یا دوستت را با تگ اختصاصی به مسابقه دعوت کن."
	intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_label.add_theme_color_override("font_color", CREAM)
	intro_label.add_theme_font_size_override("font_size", 14)
	intro.add_child(intro_label)
	var random_card := _panel(TEAL)
	content_box.add_child(random_card)
	var random_body := VBoxContainer.new()
	random_body.add_theme_constant_override("separation", 7)
	random_card.add_child(random_body)
	var random_title := Label.new()
	random_title.text = "حریف‌یابی تصادفی"
	random_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	random_title.add_theme_font_size_override("font_size", 21)
	random_title.add_theme_color_override("font_color", GOLD)
	random_body.add_child(random_title)
	var random_desc := Label.new()
	random_desc.text = "به صف بازیکنان منتظر بپیوند. با پیدا شدن حریف، مسابقه ۱۰ مرحله‌ای آغاز می‌شود."
	random_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	random_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	random_desc.add_theme_color_override("font_color", CREAM)
	random_body.add_child(random_desc)
	var random_button := _make_button("پیدا کردن حریف تصادفی", Color("#287c68"), CREAM)
	random_button.custom_minimum_size.y = 52
	random_button.pressed.connect(_start_random_matchmaking)
	random_body.add_child(random_button)
	var tag_card := _panel(GOLD)
	content_box.add_child(tag_card)
	var tag_body := VBoxContainer.new()
	tag_body.add_theme_constant_override("separation", 8)
	tag_card.add_child(tag_body)
	var tag_title := Label.new()
	tag_title.text = "حریف با تگ بازیکن"
	tag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_title.add_theme_font_size_override("font_size", 20)
	tag_title.add_theme_color_override("font_color", GOLD)
	tag_body.add_child(tag_title)
	var tag_desc := Label.new()
	tag_desc.text = "تگ اختصاصی دوستت را وارد کن تا دعوت مسابقه برایش ارسال شود."
	tag_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_desc.add_theme_color_override("font_color", MUTED)
	tag_body.add_child(tag_desc)
	var tag_input := LineEdit.new()
	tag_input.placeholder_text = "مثلاً BLD-12345678"
	tag_input.max_length = 12
	tag_input.custom_minimum_size.y = 50
	tag_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_input(tag_input)
	tag_body.add_child(tag_input)
	var send_button := _make_button("ارسال درخواست مسابقه", Color("#765a31"), CREAM)
	send_button.custom_minimum_size.y = 50
	send_button.pressed.connect(func(): _send_duel_invite_by_tag(tag_input.text))
	tag_body.add_child(send_button)
	var invites_button := _make_button("درخواست‌های دریافتی", Color("#385b75"), CREAM)
	invites_button.pressed.connect(_show_duel_invites)
	content_box.add_child(invites_button)
	var back := _make_button("بازگشت به نقشه", Color("#203e38"), CREAM)
	back.pressed.connect(_show_map)
	content_box.add_child(back)

func _send_duel_invite_by_tag(raw_tag: String) -> void:
	var normalized_tag := raw_tag.strip_edges().to_upper().replace(" ", "")
	if not normalized_tag.begins_with("BLD-") or normalized_tag.length() != 12:
		_set_status("تگ را با قالب BLD-12345678 وارد کن.", RED)
		return
	var result: Dictionary = await CloudAccount.send_duel_invite_by_tag(normalized_tag)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ارسال دعوت ناموفق بود.")), RED)
		return
	_set_status("دعوت مسابقه برای صاحب این تگ ارسال شد.", GREEN)

func _start_random_matchmaking() -> void:
	if guest_mode:
		_set_status("برای حریف‌یابی باید وارد حساب کاربری شوی.", GOLD)
		return
	var result: Dictionary = await CloudAccount.matchmaking_join()
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ورود به صف حریف‌یابی ناموفق بود.")), RED)
		return
	if str(result.get("status", "")) == "matched":
		_show_duel_game(str(result.get("match_id", "")))
		return
	current_page = "matchmaking_wait"
	_clear_content()
	_add_page_heading("در جست‌وجوی حریف...", "در حال بررسی بازیکنان آماده مسابقه")
	var wait_panel := _panel(GOLD)
	content_box.add_child(wait_panel)
	var wait_label := Label.new()
	wait_label.text = "در صف حریف‌یابی هستی. این صفحه را باز نگه دار.\nبه‌محض پیدا شدن بازیکن، مسابقه شروع می‌شود."
	wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wait_label.add_theme_font_size_override("font_size", 17)
	wait_label.add_theme_color_override("font_color", CREAM)
	wait_panel.add_child(wait_label)
	var cancel := _make_button("لغو جست‌وجو", Color("#713e3b"), CREAM)
	cancel.pressed.connect(_cancel_random_matchmaking)
	content_box.add_child(cancel)
	while is_inside_tree() and current_page == "matchmaking_wait":
		await get_tree().create_timer(2.0).timeout
		if current_page != "matchmaking_wait":
			return
		var state: Dictionary = await CloudAccount.matchmaking_status()
		if not state.get("ok", false):
			_set_status(str(state.get("error", "بررسی وضعیت حریف‌یابی ناموفق بود.")), RED)
			return
		var status := str(state.get("status", "idle"))
		if status == "matched":
			_show_duel_game(str(state.get("match_id", "")))
			return
		if status == "expired" or status == "idle":
			_set_status("زمان انتظار تمام شد. دوباره حریف‌یابی را شروع کن.", GOLD)
			_show_matchmaking()
			return

func _cancel_random_matchmaking() -> void:
	await CloudAccount.matchmaking_cancel()
	_show_matchmaking()
func _show_duel_hub() -> void:
	current_page = "duel_hub"
	_clear_content()
	_add_section_art("assets/backgrounds/letter-wheel.svg", 118)
	_add_page_heading("میدان رقابت آنلاین", "رو‌در‌رو با بازیکنان واقعی رقابت کن")
	var hero := _panel(GOLD)
	content_box.add_child(hero)
	var hero_stack := VBoxContainer.new()
	hero_stack.add_theme_constant_override("separation", 7)
	hero.add_child(hero_stack)
	var hero_title := Label.new()
	hero_title.text = "آماده‌ای قهرمان؟"
	hero_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_title.add_theme_font_size_override("font_size", 23)
	hero_title.add_theme_color_override("font_color", GOLD)
	hero_stack.add_child(hero_title)
	var hero_subtitle := Label.new()
	hero_subtitle.text = "۱۰ مرحله واژه‌یابی؛ سرعت و دقتت را به حریف ثابت کن."
	hero_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_subtitle.add_theme_color_override("font_color", CREAM)
	hero_stack.add_child(hero_subtitle)
	var stats := GridContainer.new()
	stats.columns = 3
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("h_separation", 7)
	stats.add_theme_constant_override("v_separation", 7)
	content_box.add_child(stats)
	_add_profile_stat(stats, "برد", str(wins), GREEN)
	_add_profile_stat(stats, "باخت", str(losses), RED)
	var total := wins + losses
	_add_profile_stat(stats, "نرخ برد", "%d٪" % int(round(float(wins) * 100.0 / float(total))) if total > 0 else "۰٪", GOLD)
	var active_result: Dictionary = await CloudAccount.get_active_duel()
	if not is_inside_tree() or current_page != "duel_hub":
		return
	var active_match_id := str(active_result.get("match_id", "")) if active_result.get("ok", false) else ""
	var active_card := _panel(TEAL if not active_match_id.is_empty() else PANEL_ALT)
	content_box.add_child(active_card)
	var active_stack := VBoxContainer.new()
	active_stack.add_theme_constant_override("separation", 7)
	active_card.add_child(active_stack)
	var active_title := Label.new()
	active_title.text = "مسابقه در جریان" if not active_match_id.is_empty() else "مسابقه فعالی نداری"
	active_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	active_title.add_theme_font_size_override("font_size", 18)
	active_title.add_theme_color_override("font_color", TEAL if not active_match_id.is_empty() else CREAM)
	active_stack.add_child(active_title)
	var active_button := _make_button("ادامه مسابقه" if not active_match_id.is_empty() else "بررسی مسابقه فعال", Color("#287c68"), CREAM)
	active_button.pressed.connect(_resume_active_duel)
	active_stack.add_child(active_button)
	var invites_button := _make_button("درخواست‌های دریافتی", Color("#385b75"), CREAM)
	invites_button.pressed.connect(_show_duel_invites)
	content_box.add_child(invites_button)
	var leaderboard_button := _make_button("پیدا کردن حریف از جدول بازیکنان", Color("#765a31"), CREAM)
	leaderboard_button.pressed.connect(_show_leaderboard)
	content_box.add_child(leaderboard_button)
	var refresh_button := _make_button("به‌روزرسانی وضعیت رقابت", PANEL_ALT, CREAM)
	refresh_button.pressed.connect(_show_duel_hub)
	content_box.add_child(refresh_button)
	var back := _make_button("بازگشت به پروفایل", Color("#203e38"), CREAM)
	back.pressed.connect(_show_profile)
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
		_show_duel_result(_duel_winner_id(state), int(state.get("winner_elapsed_ms", 0)))
		return
	if bool(state.get("waiting_for_opponent", false)):
		_show_duel_waiting()
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
			_show_duel_result(_duel_winner_id(state), int(state.get("winner_elapsed_ms", 0)))
	duel_poll_busy = false

func _show_duel_waiting() -> void:
	current_page = "duel_waiting"
	_clear_content()
	var waiting_card := _panel(GOLD)
	content_box.add_child(waiting_card)
	var waiting_stack := VBoxContainer.new()
	waiting_stack.add_theme_constant_override("separation", 12)
	waiting_card.add_child(waiting_stack)
	var title := Label.new()
	title.text = "نوبت حریف است"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", GOLD)
	waiting_stack.add_child(title)
	var message := Label.new()
	message.text = "تو هر ۱۰ مرحله را کامل کردی. تا یک ثانیه فرصت داریم نتیجه نهایی و احتمال مساوی را مشخص کنیم."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_color_override("font_color", CREAM)
	waiting_stack.add_child(message)
	var back := _make_button("بازگشت به نقشه", Color("#203e38"), CREAM)
	back.pressed.connect(_leave_duel_to_map)
	content_box.add_child(back)

func _duel_winner_id(result: Dictionary) -> String:
	if bool(result.get("is_draw", false)):
		return ""
	var value = result.get("winner_id", "")
	return "" if value == null else str(value)

func _show_duel_result(winner_id: String, elapsed_ms: int) -> void:
	current_page = "duel_result"
	if duel_poll_timer != null:
		duel_poll_timer.stop()
	duel_mode = false
	_clear_content()
	var is_draw := winner_id.is_empty()
	var won := not is_draw and winner_id == CloudAccount.user_id
	var reward_xp := 20 if is_draw else (50 if won else 5)
	var result_card := _panel(GOLD if won or is_draw else RED)
	content_box.add_child(result_card)
	var result_stack := VBoxContainer.new()
	result_stack.add_theme_constant_override("separation", 10)
	result_card.add_child(result_stack)
	var result_art := TextureRect.new()
	result_art.texture = load("res://assets/rewards/treasure-chest.svg") if won else load("res://assets/characters/mascot.svg")
	result_art.custom_minimum_size = Vector2(150, 126)
	result_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_stack.add_child(result_art)
	var heading := Label.new()
	heading.text = "رقابت پایاپای، مساوی!" if is_draw else ("پیروزی در میدان!" if won else "رقابت به پایان رسید")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", GOLD if won else CREAM)
	result_stack.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "هر دو بازیکن تقریباً هم‌زمان به پایان رسیدند." if is_draw else ("تبریک! این مسابقه را با موفقیت پشت سر گذاشتی." if won else "این بار حریف سریع‌تر بود؛ برای مسابقه بعدی آماده شو.")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", MUTED)
	result_stack.add_child(subtitle)
	var xp_label := Label.new()
	xp_label.text = "+%d XP" % reward_xp
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.add_theme_font_size_override("font_size", 24)
	xp_label.add_theme_color_override("font_color", GOLD)
	result_stack.add_child(xp_label)
	var time_label := Label.new()
	time_label.text = "اختلاف زمان کمتر از یک ثانیه بود." if is_draw else ("زمان ثبت‌شده برنده: %.1f ثانیه" % (float(elapsed_ms) / 1000.0))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 18)
	time_label.add_theme_color_override("font_color", CREAM)
	result_stack.add_child(time_label)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("h_separation", 8)
	result_stack.add_child(stats)
	_add_profile_stat(stats, "بردهای ثبت‌شده", str(wins), GREEN)
	_add_profile_stat(stats, "باخت‌های ثبت‌شده", str(losses), RED)
	var arena := _make_button("بازگشت به میدان رقابت", Color("#765a31"), CREAM)
	arena.pressed.connect(_show_duel_hub)
	content_box.add_child(arena)
	var back := _make_button("بازگشت به نقشه", Color("#203e38"), CREAM)
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
	_add_page_heading("درخواست‌های مسابقه", "دعوت بازیکنان را بررسی کن و وارد رقابت شو")
	var result: Dictionary = await CloudAccount.get_duel_invites()
	if not is_inside_tree() or current_page != "duel_invites":
		return
	if not result.get("ok", false):
		_set_status(str(result.get("error", "درخواست‌ها بارگذاری نشدند.")), RED)
	else:
		var invites: Array = result.get("invites", [])
		var count_label := Label.new()
		count_label.text = "%d درخواست در انتظار پاسخ" % invites.size()
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_color_override("font_color", GOLD)
		content_box.add_child(count_label)
		if invites.is_empty():
			var empty_card := _panel(PANEL_ALT)
			content_box.add_child(empty_card)
			var empty := Label.new()
			empty.text = "فعلاً دعوتی نداری. از جدول بازیکنان می‌توانی دوستانت را به مسابقه دعوت کنی."
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty.add_theme_color_override("font_color", MUTED)
			empty_card.add_child(empty)
		for invite in invites:
			var invite_id := str(invite.get("id", ""))
			var sender: Dictionary = invite.get("sender", {})
			var card := _panel(GOLD)
			content_box.add_child(card)
			var body := VBoxContainer.new()
			body.add_theme_constant_override("separation", 8)
			card.add_child(body)
			var identity := HBoxContainer.new()
			identity.add_theme_constant_override("separation", 10)
			body.add_child(identity)
			var avatar := _build_avatar_widget(str(sender.get("avatar_path", "")), str(sender.get("equipped_frame_id", "")), 62, str(sender.get("equipped_avatar_id", "")))
			identity.add_child(avatar)
			var identity_text := VBoxContainer.new()
			identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			identity_text.alignment = BoxContainer.ALIGNMENT_CENTER
			identity.add_child(identity_text)
			var name := Label.new()
			name.text = _safe_player_name(sender.get("display_name", null)) + ("  ✓" if bool(sender.get("is_verified", false)) else "")
			name.add_theme_font_size_override("font_size", 17)
			name.add_theme_color_override("font_color", CREAM)
			identity_text.add_child(name)
			var level := Label.new()
			level.text = "سطح %d · دعوت به رقابت ۱۰ مرحله‌ای" % maxi(1, int(ceil(float(sender.get("current_level", 1)) / 20.0)))
			level.add_theme_font_size_override("font_size", 12)
			level.add_theme_color_override("font_color", GOLD)
			identity_text.add_child(level)
			var actions := HBoxContainer.new()
			actions.add_theme_constant_override("separation", 8)
			body.add_child(actions)
			var accept := _make_button("پذیرش و شروع", Color("#287c68"), CREAM)
			accept.pressed.connect(func(): _accept_duel_invite(invite_id))
			actions.add_child(accept)
			var decline := _make_button("رد دعوت", Color("#713e3b"), CREAM)
			decline.pressed.connect(func(): _decline_duel_invite(invite_id))
			actions.add_child(decline)
	var refresh := _make_button("به‌روزرسانی درخواست‌ها", PANEL_ALT, CREAM)
	refresh.pressed.connect(_show_duel_invites)
	content_box.add_child(refresh)
	var back := _make_button("بازگشت به میدان رقابت", Color("#203e38"), CREAM)
	back.pressed.connect(_show_duel_hub)
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
	if chat_poll_timer != null:
		chat_poll_timer.stop()
	active_group_chat_id = ""
	active_group_chat_name = ""
	_clear_content()
	_add_page_heading("گفت‌وگوی عمومی Alishams", "انجمن زنده کاربران، با امکانات کامل پیام‌رسانی")
	var intro_panel := _panel(Color("#8d7548"))
	content_box.add_child(intro_panel)
	var intro := Label.new()
	intro.text = "گفت‌وگوی عمومی بازی اکنون از انجمن رسمی Alishams استفاده می‌کند. پیام متنی، تصویر، فایل، پیام صوتی، واکنش، پاسخ و جست‌وجوی پیام‌ها در همان محیط در دسترس است."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", CREAM)
	intro_panel.add_child(intro)
	var open_chat := _make_button("ورود به انجمن گفت‌وگو", Color("#a8d84b"), Color("#10200e"))
	open_chat.custom_minimum_size = Vector2(0, 58)
	open_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_chat.add_theme_font_size_override("font_size", 17)
	open_chat.pressed.connect(_launch_community_chat)
	content_box.add_child(open_chat)
	chat_status_label = Label.new()
	chat_status_label.text = "برای استفاده از انجمن، با حساب بازی وارد شو." if guest_mode or not CloudAccount.is_authenticated() else "ورود با نشست فعلی بازی انجام می‌شود؛ نیازی به ورود دوباره نیست."
	chat_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_status_label.add_theme_color_override("font_color", MUTED)
	content_box.add_child(chat_status_label)
	open_chat.disabled = guest_mode or not CloudAccount.is_authenticated()
	var game_actions := HBoxContainer.new()
	game_actions.add_theme_constant_override("separation", 8)
	content_box.add_child(game_actions)
	var invites := _make_button("دعوت‌های بازی", Color("#294c43"), GOLD)
	invites.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invites.pressed.connect(_show_duel_invites)
	game_actions.add_child(invites)
	var stickers := _make_button("استیکرهای بلدی؟", Color("#765a31"), CREAM)
	stickers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stickers.pressed.connect(_show_sticker_picker)
	game_actions.add_child(stickers)
	var back := _make_button("بازگشت به نقشه مراحل", PANEL_ALT, CREAM)
	back.pressed.connect(_show_map)
	content_box.add_child(back)

func _launch_community_chat() -> void:
	if guest_mode or not CloudAccount.is_authenticated():
		if chat_status_label != null and is_instance_valid(chat_status_label):
			chat_status_label.text = "برای ورود به انجمن، ابتدا وارد حساب بازی شو."
		return
	var session_valid: bool = await CloudAccount._refresh_if_needed()
	if not session_valid:
		_set_status("نشست بازی منقضی شده است. دوباره وارد حساب شو.", RED)
		return
	var webview = Engine.get_singleton("BaladiCommunityWebView")
	if webview == null:
		_set_status("ماژول انجمن در این نسخه نصب نشده است. نسخه جدید بازی را دریافت کن.", RED)
		return
	var session_callback := Callable(self, "_on_community_session_updated")
	if webview.has_signal("session_updated") and not webview.is_connected("session_updated", session_callback):
		webview.connect("session_updated", session_callback)
	var user_payload := {
		"id": CloudAccount.user_id,
		"email": CloudAccount.user_email,
		"aud": "authenticated",
		"role": "authenticated",
		"app_metadata": {"provider": "email", "providers": ["email"]},
		"user_metadata": {"full_name": CloudAccount.display_name}
	}
	webview.call(
		"openCommunityChat",
		CloudAccount.access_token,
		CloudAccount.refresh_token,
		float(CloudAccount.expires_at),
		JSON.stringify(user_payload)
	)

func _on_community_session_updated(session_json: String) -> void:
	CloudAccount.accept_external_session(session_json)

func _unlock_global_chat() -> void:
	# Legacy entry point retained for older UI references; public chat has no purchase gate.
	chat_unlocked = true
	_show_global_chat()

func _refresh_global_chat() -> void:
	if current_page not in ["global_chat", "group_chat"]:
		return
	if chat_poll_busy or chat_messages_box == null or not is_instance_valid(chat_messages_box):
		return
	chat_poll_busy = true
	var requested_page := current_page
	var requested_group_id := active_group_chat_id
	var should_keep_bottom := chat_scroll_to_bottom
	if chat_scroll_container != null and is_instance_valid(chat_scroll_container):
		var scroll_bar := chat_scroll_container.get_v_scroll_bar()
		should_keep_bottom = should_keep_bottom or scroll_bar.value >= scroll_bar.max_value - 48
	var result: Dictionary
	if requested_page == "group_chat" and not requested_group_id.is_empty():
		result = await CloudAccount.get_group_chat_messages(requested_group_id)
	else:
		result = await CloudAccount.get_global_chat_messages()
	var still_same_chat := current_page == requested_page and active_group_chat_id == requested_group_id
	if result.get("ok", false) and still_same_chat and chat_messages_box != null and is_instance_valid(chat_messages_box):
		if requested_page == "group_chat":
			active_group_role = str(result.get("role", "")).strip_edges().to_lower()
		for child in chat_messages_box.get_children():
			child.queue_free()
		var visible_messages: Array = result.get("messages", [])
		print("[Baladi][Chat] page=", requested_page, " messages=", visible_messages.size())
		if visible_messages.is_empty():
			var empty_panel := _panel(Color("#547c6b"))
			chat_messages_box.add_child(empty_panel)
			var empty_label := Label.new()
			empty_label.text = "هنوز پیامی در این گفت‌وگو نیست. اولین پیام را تو بفرست!"
			empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty_label.add_theme_color_override("font_color", MUTED)
			empty_panel.add_child(empty_label)
		for message in visible_messages:
			var player: Dictionary = message.get("player", {})
			var player_id := str(message.get("user_id", ""))
			var is_own_message := player_id == CloudAccount.user_id
			var card := _panel(Color("#c5a35e") if is_own_message else Color("#31594d"))
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var bubble_style := StyleBoxFlat.new()
			bubble_style.bg_color = Color("#245747") if is_own_message else Color("#173a33")
			bubble_style.border_color = Color("#b99755") if is_own_message else Color("#31594d")
			bubble_style.set_border_width_all(1)
			bubble_style.set_corner_radius_all(18)
			bubble_style.set_corner_radius(CORNER_BOTTOM_RIGHT, 5 if is_own_message else 18)
			bubble_style.set_corner_radius(CORNER_BOTTOM_LEFT, 18 if is_own_message else 5)
			bubble_style.shadow_color = Color(0, 0, 0, 0.24)
			bubble_style.shadow_size = 6
			bubble_style.shadow_offset = Vector2(0, 3)
			bubble_style.content_margin_left = 13
			bubble_style.content_margin_right = 13
			bubble_style.content_margin_top = 11
			bubble_style.content_margin_bottom = 11
			card.add_theme_stylebox_override("panel", bubble_style)
			chat_messages_box.add_child(card)
			var body := VBoxContainer.new()
			body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_theme_constant_override("separation", 9)
			card.add_child(body)
			if not requested_group_id.is_empty() and not is_own_message:
				_ensure_chat_long_press_timer()
				var long_press_message_id := int(message.get("id", 0))
				card.gui_input.connect(_on_chat_message_gui_input.bind(long_press_message_id, player_id))

			var sender_row := HBoxContainer.new()
			sender_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sender_row.add_theme_constant_override("separation", 8)
			body.add_child(sender_row)
			var avatar_button := Button.new()
			avatar_button.flat = true
			avatar_button.custom_minimum_size = Vector2(48, 48)
			avatar_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			avatar_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			avatar_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			avatar_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
			avatar_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
			var message_avatar := _build_avatar_widget(str(player.get("avatar_path", "")), str(player.get("equipped_frame_id", "frame_default")), 42, str(player.get("equipped_avatar_id", "")))
			message_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			avatar_button.add_child(message_avatar)
			avatar_button.pressed.connect(_open_chat_public_profile.bind(player_id))
			sender_row.add_child(avatar_button)
			var sender_info := VBoxContainer.new()
			sender_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sender_row.add_child(sender_info)
			var name_label := _make_button(_safe_player_name(player.get("display_name", null)) + ("  ✓" if bool(player.get("is_verified", false)) else ""), Color("#294c43"), GOLD)
			name_label.custom_minimum_size = Vector2(0, 30)
			name_label.add_theme_font_size_override("font_size", 13)
			if player_id == CloudAccount.user_id:
				name_label.disabled = true
			else:
				name_label.pressed.connect(_open_chat_public_profile.bind(player_id))
			sender_info.add_child(name_label)
			var created_at := str(message.get("created_at", ""))
			var time_label := Label.new()
			time_label.text = created_at.substr(11, 5) if created_at.length() >= 16 else ""
			time_label.add_theme_font_size_override("font_size", 10)
			time_label.add_theme_color_override("font_color", MUTED)
			sender_info.add_child(time_label)

			var sticker_value: Variant = message.get("sticker_id", null)
			var sticker_id := "" if sticker_value == null else str(sticker_value).strip_edges()
			if not sticker_id.is_empty():
				var sticker_panel := PanelContainer.new()
				sticker_panel.custom_minimum_size = Vector2(0, 166)
				sticker_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				var sticker_style := StyleBoxFlat.new()
				sticker_style.bg_color = Color("#102f29")
				sticker_style.border_color = Color("#b99755", 0.72)
				sticker_style.set_border_width_all(1)
				sticker_style.set_corner_radius_all(18)
				sticker_style.content_margin_left = 8
				sticker_style.content_margin_right = 8
				sticker_style.content_margin_top = 8
				sticker_style.content_margin_bottom = 8
				sticker_panel.add_theme_stylebox_override("panel", sticker_style)
				var sticker_art := TextureRect.new()
				var sticker_file := sticker_id.trim_prefix("sticker_")
				var sticker_path := "res://assets/stickers/%s.svg" % sticker_file
				if ResourceLoader.exists(sticker_path):
					sticker_art.texture = load(sticker_path)
				sticker_art.custom_minimum_size = Vector2(148, 148)
				sticker_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				sticker_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				sticker_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
				sticker_panel.add_child(sticker_art)
				body.add_child(sticker_panel)
			else:
				var message_text := ""
				for text_key in ["body", "content", "message", "text"]:
					var message_value = message.get(text_key, null)
					if message_value != null and not str(message_value).strip_edges().is_empty():
						message_text = str(message_value).strip_edges()
						break
				var message_label := RichTextLabel.new()
				message_label.bbcode_enabled = false
				message_label.fit_content = true
				message_label.scroll_active = false
				message_label.selection_enabled = false
				message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				message_label.layout_direction = Control.LAYOUT_DIRECTION_RTL
				message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				message_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
				message_label.custom_minimum_size = Vector2(0, 44)
				message_label.add_theme_font_size_override("normal_font_size", 16)
				message_label.add_theme_color_override("default_color", CREAM)
				message_label.text = message_text if not message_text.is_empty() else "پیام متنی خالی است"
				body.add_child(message_label)
				print("[Baladi][Chat] message_id=", message.get("id", 0), " body_chars=", message_text.length(), " keys=", message.keys())

			if not requested_group_id.is_empty():
				var actions := HBoxContainer.new()
				actions.add_theme_constant_override("separation", 6)
				body.add_child(actions)
				if not is_own_message:
					var invite_button := _make_button("دعوت به بازی دونفره", Color("#287c68"), CREAM)
					invite_button.custom_minimum_size = Vector2(0, 34)
					invite_button.pressed.connect(_send_duel_invite_to.bind(player_id))
					actions.add_child(invite_button)
					var more := _make_button("عملیات پیام  ⋮", Color("#294c43"), GOLD)
					more.custom_minimum_size = Vector2(0, 34)
					var group_message_id := int(message.get("id", 0))
					more.pressed.connect(_show_group_message_menu.bind(group_message_id, player_id))
					actions.add_child(more)
				if active_group_role == "leader":
					var delete_button := _make_button("حذف پیام", Color("#713e3b"), CREAM)
					delete_button.custom_minimum_size = Vector2(0, 34)
					var delete_message_id := int(message.get("id", 0))
					delete_button.pressed.connect(_delete_group_chat_message.bind(requested_group_id, delete_message_id))
					actions.add_child(delete_button)
				if bool(message.get("is_pinned", false)):
					var pinned_label := Label.new()
					pinned_label.text = "سنجاق‌شده"
					pinned_label.add_theme_color_override("font_color", GOLD)
					actions.add_child(pinned_label)
				if active_group_role in ["veteran", "deputy", "leader"]:
					var pin_button := _make_button("برداشتن سنجاق" if bool(message.get("is_pinned", false)) else "سنجاق پیام", Color("#765a31"), CREAM)
					var pin_message_id := int(message.get("id", 0))
					var should_pin := not bool(message.get("is_pinned", false))
					pin_button.pressed.connect(_toggle_group_message_pin.bind(requested_group_id, pin_message_id, should_pin))
					actions.add_child(pin_button)
			elif not is_own_message:
				var report_button := _make_button("گزارش پیام", Color("#713e3b"), CREAM)
				report_button.custom_minimum_size = Vector2(0, 34)
				var report_message_id := int(message.get("id", 0))
				report_button.pressed.connect(_show_chat_report_menu.bind(report_message_id))
				body.add_child(report_button)
	if not result.get("ok", false) and still_same_chat and chat_status_label != null and is_instance_valid(chat_status_label):
		chat_status_label.text = str(result.get("error", "دریافت پیام‌ها انجام نشد."))
	if still_same_chat and should_keep_bottom:
		chat_scroll_to_bottom = true
		call_deferred("_scroll_chat_to_bottom")
	else:
		chat_scroll_to_bottom = false
	chat_poll_busy = false

func _scroll_chat_to_bottom() -> void:
	if chat_scroll_container == null or not is_instance_valid(chat_scroll_container):
		return
	await get_tree().process_frame
	var scroll_bar := chat_scroll_container.get_v_scroll_bar()
	scroll_bar.value = scroll_bar.max_value
	chat_scroll_to_bottom = false

func _ensure_chat_long_press_timer() -> void:
	if chat_long_press_timer != null and is_instance_valid(chat_long_press_timer):
		return
	chat_long_press_timer = Timer.new()
	chat_long_press_timer.one_shot = true
	chat_long_press_timer.wait_time = 0.55
	chat_long_press_timer.timeout.connect(_open_pending_chat_message_menu)
	add_child(chat_long_press_timer)

func _on_chat_message_gui_input(event: InputEvent, message_id: int, player_id: String) -> void:
	if chat_long_press_timer == null or not is_instance_valid(chat_long_press_timer):
		return
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed
	if pressed:
		pending_chat_message_id = message_id
		pending_chat_player_id = player_id
		chat_long_press_timer.start()
	elif released:
		chat_long_press_timer.stop()

func _open_pending_chat_message_menu() -> void:
	if current_page != "group_chat" or pending_chat_message_id <= 0 or pending_chat_player_id.is_empty():
		return
	_show_group_message_menu(pending_chat_message_id, pending_chat_player_id)

func _show_group_message_menu(message_id: int, player_id: String) -> void:
	if message_id <= 0 or player_id.is_empty():
		return
	var popup := PopupMenu.new()
	popup.add_item("مشاهده پروفایل", 0)
	popup.add_item("دعوت به بازی دونفره", 1)
	popup.add_separator()
	popup.add_item("گزارش این پیام", 2)
	add_child(popup)
	popup.id_pressed.connect(_on_group_message_action.bind(message_id, player_id, popup))
	popup.popup_centered(Vector2i(300, 190))

func _on_group_message_action(action_id: int, message_id: int, player_id: String, popup: PopupMenu) -> void:
	if is_instance_valid(popup):
		popup.queue_free()
	match action_id:
		0:
			_show_public_profile(player_id)
		1:
			_send_duel_invite_to(player_id)
		2:
			_show_group_chat_report_menu(message_id)

func _show_group_chat_report_menu(message_id: int) -> void:
	if message_id <= 0:
		return
	var popup := PopupMenu.new()
	popup.add_item("تبلیغات و هرزنامه", 0)
	popup.add_item("توهین و آزار", 1)
	popup.add_item("محتوای نامناسب", 2)
	popup.add_item("تهدید یا کلاهبرداری", 3)
	popup.add_item("سایر موارد", 4)
	add_child(popup)
	popup.id_pressed.connect(_on_group_report_reason_selected.bind(message_id, active_group_chat_id, popup))
	popup.popup_centered(Vector2i(300, 250))

func _on_group_report_reason_selected(reason_index: int, message_id: int, group_id: String, popup: PopupMenu) -> void:
	if is_instance_valid(popup):
		popup.queue_free()
	var reasons := ["تبلیغات و هرزنامه", "توهین و آزار", "محتوای نامناسب", "تهدید یا کلاهبرداری", "سایر موارد"]
	if reason_index < 0 or reason_index >= reasons.size():
		return
	var result: Dictionary = await CloudAccount.report_group_chat_message(group_id, message_id, reasons[reason_index])
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ثبت گزارش پیام گروه انجام نشد.")), RED)
	else:
		_set_status("گزارش پیام گروه برای بررسی ثبت شد.", GREEN)


func _show_chat_report_menu(message_id: int) -> void:
	if message_id <= 0:
		return
	var popup := PopupMenu.new()
	popup.add_item("تبلیغات و هرزنامه", 0)
	popup.add_item("توهین و آزار", 1)
	popup.add_item("محتوای نامناسب", 2)
	popup.add_item("تهدید یا کلاهبرداری", 3)
	popup.add_item("سایر موارد", 4)
	add_child(popup)
	popup.id_pressed.connect(_on_chat_report_reason_selected.bind(message_id, popup))
	popup.popup_centered(Vector2i(300, 250))

func _on_chat_report_reason_selected(reason_index: int, message_id: int, popup: PopupMenu) -> void:
	if is_instance_valid(popup):
		popup.queue_free()
	await _submit_chat_report(reason_index, message_id)

func _submit_chat_report(reason_index: int, message_id: int) -> void:
	var reasons := ["تبلیغات و هرزنامه", "توهین و آزار", "محتوای نامناسب", "تهدید یا کلاهبرداری", "سایر موارد"]
	if reason_index < 0 or reason_index >= reasons.size():
		return
	var result: Dictionary = await CloudAccount.report_global_chat_message(message_id, reasons[reason_index])
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ثبت گزارش انجام نشد.")), RED)
	else:
		_set_status("گزارش پیام برای بررسی ثبت شد.", GREEN)

func _delete_group_chat_message(group_id: String, message_id: int) -> void:
	if group_id.is_empty() or message_id <= 0:
		return
	if active_group_role.strip_edges().to_lower() != "leader":
		if chat_status_label != null and is_instance_valid(chat_status_label):
			chat_status_label.text = "حذف پیام فقط برای رهبر گروه فعال است. نقش فعلی: " + active_group_role
		return
	var confirm := ConfirmationDialog.new()
	confirm.title = "حذف پیام گروه"
	confirm.dialog_text = "این پیام برای همه اعضای گروه حذف شود؟"
	confirm.ok_button_text = "حذف پیام"
	confirm.cancel_button_text = "انصراف"
	add_child(confirm)
	confirm.confirmed.connect(_confirm_group_message_delete.bind(confirm, group_id, message_id))
	confirm.canceled.connect(func():
		if is_instance_valid(confirm):
			confirm.queue_free()
	)
	confirm.popup_centered(Vector2i(360, 180))

func _confirm_group_message_delete(confirm: ConfirmationDialog, group_id: String, message_id: int) -> void:
	if chat_status_label != null and is_instance_valid(chat_status_label):
		chat_status_label.text = "در حال حذف پیام..."
	var result: Dictionary = await CloudAccount.delete_group_chat_message(group_id, message_id)
	if not result.get("ok", false):
		var error_text := str(result.get("error", "حذف پیام انجام نشد."))
		if chat_status_label != null and is_instance_valid(chat_status_label):
			chat_status_label.text = error_text
		_set_status(error_text, RED)
	else:
		if chat_status_label != null and is_instance_valid(chat_status_label):
			chat_status_label.text = "پیام از گفت‌وگوی گروه حذف شد."
		_set_status("پیام از گفت‌وگوی گروه حذف شد.", GREEN)
		while chat_poll_busy:
			await get_tree().process_frame
		if current_page == "group_chat" and active_group_chat_id == group_id:
			await _refresh_global_chat()
	if is_instance_valid(confirm):
		confirm.queue_free()

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
	if current_page == "group_chat":
		await _send_group_chat_message(active_group_chat_id, message)
		return
	var result: Dictionary = await CloudAccount.send_global_chat_message(message)
	if not result.get("ok", false):
		if chat_status_label != null and is_instance_valid(chat_status_label):
			chat_status_label.text = str(result.get("error", "ارسال پیام انجام نشد."))
		return
	chat_input.clear()
	await _refresh_global_chat()

func _reveal_group_chat_composer() -> void:
	if chat_input == null or not is_instance_valid(chat_input):
		return
	var node: Node = chat_input
	while node != null:
		if node is ScrollContainer:
			var scroll := node as ScrollContainer
			var bar := scroll.get_v_scroll_bar()
			if bar != null:
				scroll.scroll_vertical = int(bar.max_value)
				bar.value = bar.max_value
			return
		node = node.get_parent()

func _send_group_chat_message(group_id: String, message: String) -> void:
	if group_id.is_empty() or message.is_empty():
		return
	if chat_status_label != null and is_instance_valid(chat_status_label):
		chat_status_label.text = "در حال ارسال پیام..."
	var result: Dictionary = await CloudAccount.send_group_chat_message(group_id, message)
	if not result.get("ok", false):
		if chat_status_label != null and is_instance_valid(chat_status_label):
			chat_status_label.text = str(result.get("error", "ارسال پیام گروه انجام نشد."))
		return
	if chat_input != null and is_instance_valid(chat_input):
		chat_input.clear()
	if chat_status_label != null and is_instance_valid(chat_status_label):
		chat_status_label.text = "پیامت با موفقیت ارسال شد."
	chat_scroll_to_bottom = true
	await _refresh_global_chat()

func _show_sticker_picker() -> void:
	if active_group_chat_id.is_empty():
		_show_global_sticker_picker()
		return
	if guest_mode:
		_set_status("برای ارسال استیکر باید وارد حساب کاربری شوی.", GOLD)
		return
	var popup := PopupPanel.new()
	popup.name = "GroupOwnedStickerPicker"
	popup.size = Vector2i(340, 460)
	var shell := VBoxContainer.new()
	shell.custom_minimum_size = Vector2(320, 430)
	shell.add_theme_constant_override("separation", 10)
	popup.add_child(shell)
	var title := Label.new()
	title.text = "استیکرهای خریداری‌شده من"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", GOLD)
	shell.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "برای ارسال، استیکر دلخواهت را انتخاب کن."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", MUTED)
	shell.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 9)
	scroll.add_child(grid)
	var loading := Label.new()
	loading.text = "در حال دریافت استیکرها..."
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_theme_color_override("font_color", MUTED)
	shell.add_child(loading)
	var close := _make_button("بستن", PANEL_ALT, CREAM)
	close.pressed.connect(popup.hide)
	shell.add_child(close)
	add_child(popup)
	popup.popup_centered()
	var result: Dictionary = await CloudAccount.get_cosmetics_catalog()
	if not is_instance_valid(popup):
		return
	loading.queue_free()
	if not result.get("ok", false):
		var error_label := Label.new()
		error_label.text = str(result.get("error", "دریافت استیکرها ناموفق بود."))
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(error_label)
		return
	var owned: Dictionary = {}
	for entry in result.get("owned", []):
		owned[str(entry.get("cosmetic_id", ""))] = true
	var count := 0
	for item in result.get("catalog", []):
		if str(item.get("kind", "")) != "sticker":
			continue
		var sticker_id := str(item.get("id", ""))
		if not owned.has(sticker_id):
			continue
		count += 1
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(142, 158)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.focus_mode = Control.FOCUS_NONE
		var tile_style := StyleBoxFlat.new()
		tile_style.bg_color = Color("#183b34")
		tile_style.border_color = Color("#b99755")
		tile_style.set_border_width_all(1)
		tile_style.set_corner_radius_all(14)
		tile.add_theme_stylebox_override("normal", tile_style)
		var hover_style := tile_style.duplicate()
		hover_style.bg_color = Color("#245747")
		tile.add_theme_stylebox_override("hover", hover_style)
		var tile_body := VBoxContainer.new()
		tile_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile_body.add_theme_constant_override("separation", 4)
		tile.add_child(tile_body)
		var art := TextureRect.new()
		var asset_path := "res://" + str(item.get("asset_path", ""))
		if ResourceLoader.exists(asset_path):
			art.texture = load(asset_path)
		art.custom_minimum_size = Vector2(0, 112)
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_body.add_child(art)
		var name_label := Label.new()
		name_label.text = str(item.get("display_name", "استیکر"))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", CREAM)
		tile_body.add_child(name_label)
		tile.pressed.connect(_on_group_sticker_selected.bind(sticker_id, popup))
		grid.add_child(tile)
	if count == 0:
		var empty := Label.new()
		empty.text = "هنوز استیکری خریداری نکرده‌ای."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", MUTED)
		grid.add_child(empty)

func _on_group_sticker_selected(sticker_id: String, popup: PopupPanel) -> void:
	if is_instance_valid(popup):
		popup.hide()
		popup.queue_free()
	if active_group_chat_id.is_empty() or sticker_id.is_empty():
		return
	var target_group := active_group_chat_id
	var result: Dictionary = await CloudAccount.send_group_chat_sticker(target_group, sticker_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "ارسال استیکر انجام نشد.")), RED)
		return
	_set_status("استیکر با موفقیت ارسال شد.", GREEN)
	chat_scroll_to_bottom = true
	await _refresh_global_chat()

func _show_global_sticker_picker() -> void:
	current_page = "sticker_picker"
	_clear_content()
	var heading := Label.new()
	heading.text = "گالری استیکرهای بلدی؟"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var coin_topup := _make_button("خرید سکه · هر ۱٬۰۰۰ سکه ۸٬۹۰۰ تومان", Color("#765a31"), CREAM)
	coin_topup.custom_minimum_size = Vector2(0, 52)
	coin_topup.pressed.connect(func(): OS.shell_open("https://alishams.ir/game-coins.html"))
	content_box.add_child(coin_topup)
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
				var card_body := VBoxContainer.new()
				card_body.add_theme_constant_override("separation", 8)
				card.add_child(card_body)
				var title := Label.new()
				title.text = str(item.get("display_name", "استیکر"))
				title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				title.add_theme_font_size_override("font_size", 17)
				title.add_theme_color_override("font_color", CREAM)
				card_body.add_child(title)
				var preview_panel := PanelContainer.new()
				preview_panel.custom_minimum_size = Vector2(0, 142)
				var preview_style := StyleBoxFlat.new()
				preview_style.bg_color = Color("#183b34")
				preview_style.set_corner_radius_all(14)
				preview_panel.add_theme_stylebox_override("panel", preview_style)
				card_body.add_child(preview_panel)
				var sticker_art := TextureRect.new()
				var sticker_asset_path := "res://" + str(item.get("asset_path", ""))
				if ResourceLoader.exists(sticker_asset_path):
					sticker_art.texture = load(sticker_asset_path)
				sticker_art.custom_minimum_size = Vector2(0, 128)
				sticker_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sticker_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				sticker_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				sticker_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
				preview_panel.add_child(sticker_art)
				var price_label := Label.new()
				price_label.text = "خریداری شده" if owned.has(sticker_id) else "%s سکه" % _format_coin_price(item.get("price_coins", 0))
				price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				price_label.add_theme_color_override("font_color", GOLD)
				card_body.add_child(price_label)
				var action_text := "ارسال استیکر" if owned.has(sticker_id) else "خرید · %s سکه" % _format_coin_price(item.get("price_coins", 0))
				var action := _make_button(action_text, Color("#765a31"), CREAM)
				action.pressed.connect(func():
					if owned.has(sticker_id):
						_send_global_chat_sticker(sticker_id)
					else:
						_purchase_sticker(sticker_id)
				)
				card_body.add_child(action)
		else:
			_set_status(str(result.get("error", "فروشگاه استیکر بارگذاری نشد.")), RED)
	var back := _make_button("بازگشت به چت", PANEL_ALT, CREAM)
	back.pressed.connect(_show_global_chat)
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
	if chat_poll_timer != null:
		chat_poll_timer.stop()
	active_group_chat_id = ""
	active_group_chat_name = ""
	active_group_role = ""
	_clear_content()
	_add_section_art("assets/backgrounds/chapter-caravanserai.svg", 92)
	_add_page_heading("باشگاه گروه‌ها", "گروه بساز، عضو شو و با هم پیشرفت کن")
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
		title.text = _safe_player_name(group.get("name", null), "گروه")
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", CREAM)
		body.add_child(title)
		var info := Label.new()
		info.text = "رهبر: %s%s  ·  اعضا: %d / %d  ·  سطح %d" % [_safe_player_name(group.get("leader_name", null)), ("  ✓" if bool(group.get("leader_is_verified", false)) else ""), int(group.get("member_count", 0)), int(group.get("capacity", 20)), int(group.get("group_level", 1))]
		info.add_theme_color_override("font_color", MUTED)
		body.add_child(info)
		var group_reward := 120 if int(group.get("group_level", 1)) == 2 else (500 if int(group.get("group_level", 1)) == 3 else 0)
		var reward_note := Label.new()
		reward_note.text = "پاداش روزانه هر عضو: %s سکه" % ("بدون پاداش" if group_reward == 0 else _format_coin_price(group_reward))
		reward_note.add_theme_color_override("font_color", GOLD)
		body.add_child(reward_note)
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
	var safe_group_name := _safe_player_name(group.get("name", null), "گروه من")
	var role := str(group.get("my_role", "member"))
	active_group_role = role
	var card := _panel(GOLD)
	content_box.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(body)
	var title := Label.new()
	title.text = safe_group_name
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GOLD)
	body.add_child(title)
	var capacity := int(group.get("capacity", 20))
	var count := members.size()
	var summary := Label.new()
	summary.text = "مقام تو: %s  ·  اعضا: %d / %d" % [_group_role_label(role), count, capacity]
	summary.add_theme_color_override("font_color", CREAM)
	body.add_child(summary)
	var group_level := int(group.get("group_level", 1))
	var upgrade_progress := int(group.get("upgrade_progress", 0))
	var target_cost := 40000 if group_level == 1 else 200000
	var reward_per_day := 120 if group_level == 2 else (500 if group_level == 3 else 0)
	var level_panel := _panel(Color("#8d7548"))
	content_box.add_child(level_panel)
	var level_box := VBoxContainer.new()
	level_box.add_theme_constant_override("separation", 7)
	level_panel.add_child(level_box)
	var level_title := Label.new()
	level_title.text = "سطح باشگاه: %d از ۳" % group_level
	level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_title.add_theme_font_size_override("font_size", 20)
	level_title.add_theme_color_override("font_color", GOLD)
	level_box.add_child(level_title)
	var benefit := Label.new()
	benefit.text = "پاداش روزانه هر عضو: %s سکه" % ("بدون پاداش" if reward_per_day == 0 else _format_coin_price(reward_per_day))
	benefit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	benefit.add_theme_color_override("font_color", CREAM)
	level_box.add_child(benefit)
	if group_level < 3:
		var progress_label := Label.new()
		progress_label.text = "پیشرفت ارتقا: %s از %s سکه" % [_format_coin_price(upgrade_progress), _format_coin_price(target_cost)]
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_label.add_theme_color_override("font_color", MUTED)
		level_box.add_child(progress_label)
		var progress := ProgressBar.new()
		progress.min_value = 0
		progress.max_value = target_cost
		progress.value = upgrade_progress
		progress.show_percentage = false
		progress.custom_minimum_size.y = 16
		level_box.add_child(progress)
		var contribution_row := HBoxContainer.new()
		contribution_row.add_theme_constant_override("separation", 6)
		level_box.add_child(contribution_row)
		var amount_input := LineEdit.new()
		amount_input.placeholder_text = "مقدار مشارکت به سکه"
		amount_input.custom_minimum_size.y = 44
		amount_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_input(amount_input)
		contribution_row.add_child(amount_input)
		var contribute := _make_button("مشارکت", Color("#765a31"), CREAM)
		contribute.custom_minimum_size = Vector2(95, 44)
		contribute.pressed.connect(func(): _contribute_to_group(group_id, amount_input.text))
		contribution_row.add_child(contribute)
	else:
		var max_level := Label.new()
		max_level.text = "باشگاه به بالاترین سطح رسیده است."
		max_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		max_level.add_theme_color_override("font_color", GOLD)
		level_box.add_child(max_level)
	if group_level >= 2:
		var already_claimed := bool(group.get("daily_reward_claimed", false))
		var claim_label := "پاداش امروز دریافت شد" if already_claimed else "برداشت پاداش امروز · %s سکه" % _format_coin_price(reward_per_day)
		var claim_reward := _make_button(claim_label, Color("#287c68"), CREAM)
		claim_reward.disabled = already_claimed
		claim_reward.pressed.connect(func(): _claim_group_daily_reward(group_id))
		level_box.add_child(claim_reward)
	else:
		var locked_reward := Label.new()
		locked_reward.text = "با ارتقا به سطح ۲، هر عضو روزانه ۱۲۰ سکه قابل برداشت می‌گیرد."
		locked_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		locked_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		locked_reward.add_theme_color_override("font_color", MUTED)
		level_box.add_child(locked_reward)

	var chat := _make_button("ورود به گفت‌وگوی گروه", Color("#287c68"), CREAM)
	chat.pressed.connect(func(): _show_group_chat(group_id, safe_group_name))
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
		var member_top := HBoxContainer.new()
		member_top.add_theme_constant_override("separation", 8)
		row_box.add_child(member_top)
		var member_avatar := _build_avatar_widget(str(player.get("avatar_path", "")), str(player.get("equipped_frame_id", "frame_default")), 48, str(player.get("equipped_avatar_id", "")))
		member_top.add_child(member_avatar)
		var name := _make_button("%s%s  ·  %s" % [_safe_player_name(player.get("display_name", null)), ("  ✓" if bool(player.get("is_verified", false)) else ""), _group_role_label(member_role)], Color("#294c43"), CREAM)
		name.custom_minimum_size = Vector2(0, 42)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if member_id == CloudAccount.user_id:
			name.disabled = true
		else:
			name.pressed.connect(func(): _show_public_profile(member_id))
		member_top.add_child(name)
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

func _contribute_to_group(group_id: String, amount_text: String) -> void:
	var amount := int(amount_text.strip_edges())
	if amount <= 0:
		_set_status("مقدار مشارکت را به‌صورت عدد مثبت وارد کن.", RED)
		return
	var result: Dictionary = await CloudAccount.contribute_to_group(group_id, amount)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "مشارکت در ارتقای گروه انجام نشد.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	_set_status("مشارکت ثبت شد. سطح جدید گروه: %d" % int(result.get("group", {}).get("group_level", 1)), GREEN)
	_show_groups()

func _claim_group_daily_reward(group_id: String) -> void:
	var result: Dictionary = await CloudAccount.claim_group_daily_reward(group_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "برداشت پاداش روزانه انجام نشد.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	var reward := int(result.get("reward_coins", 0))
	_animate_coin_reward(reward)
	_set_status("پاداش روزانه گروه: %s سکه به حسابت اضافه شد." % _format_coin_price(reward), GREEN)
	_show_groups()

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
	if chat_poll_timer != null:
		chat_poll_timer.stop()
	active_group_chat_id = group_id
	active_group_chat_name = group_name
	chat_scroll_to_bottom = true
	_clear_content()
	var header := _panel(GOLD)
	content_box.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	header.add_child(header_row)
	var group_icon := Label.new()
	group_icon.text = "✦"
	group_icon.add_theme_font_size_override("font_size", 26)
	group_icon.add_theme_color_override("font_color", GOLD)
	header_row.add_child(group_icon)
	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_text)
	var heading := Label.new()
	heading.text = group_name
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", GOLD)
	header_text.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "گفت‌وگوی اعضای باشگاه · پیام‌ها هر چند ثانیه به‌روزرسانی می‌شوند"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", MUTED)
	header_text.add_child(subtitle)

	var hint := Label.new()
	hint.text = "برای دیدن گزینه‌های هر پیام، چند لحظه روی آن نگه دار یا دکمه عملیات پیام را بزن."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", MUTED)
	content_box.add_child(hint)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 7)
	content_box.add_child(toolbar)
	var sticker_button := _make_button("استیکرهای من", Color("#765a31"), CREAM)
	sticker_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sticker_button.pressed.connect(_show_sticker_picker)
	toolbar.add_child(sticker_button)
	var invites_button := _make_button("دعوت‌های بازی", Color("#294c43"), GOLD)
	invites_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invites_button.pressed.connect(_show_duel_invites)
	toolbar.add_child(invites_button)

	chat_scroll_container = ScrollContainer.new()
	chat_scroll_container.custom_minimum_size = Vector2(0, 300)
	chat_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_box.add_child(chat_scroll_container)
	chat_messages_box = VBoxContainer.new()
	chat_messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_messages_box.add_theme_constant_override("separation", 9)
	chat_scroll_container.add_child(chat_messages_box)

	chat_status_label = Label.new()
	chat_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_status_label.add_theme_color_override("font_color", MUTED)
	content_box.add_child(chat_status_label)

	var composer_panel := _panel(Color("#547c6b"))
	content_box.add_child(composer_panel)
	var composer := HBoxContainer.new()
	composer.add_theme_constant_override("separation", 6)
	composer_panel.add_child(composer)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "پیامت را برای اعضای گروه بنویس..."
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.custom_minimum_size.y = 48
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(chat_input)
	chat_input.text_submitted.connect(func(_submitted: String): _send_group_chat_message(group_id, chat_input.text.strip_edges()))
	chat_input.focus_entered.connect(_reveal_group_chat_composer)
	chat_input.text_changed.connect(func(_text: String): call_deferred("_reveal_group_chat_composer"))
	composer.add_child(chat_input)
	var send := _make_button("ارسال", Color("#287c68"), CREAM)
	send.custom_minimum_size = Vector2(76, 48)
	send.pressed.connect(func(): _send_group_chat_message(group_id, chat_input.text.strip_edges()))
	composer.add_child(send)

	var back := _make_button("بازگشت به گروه", PANEL_ALT, CREAM)
	back.pressed.connect(_show_groups)
	content_box.add_child(back)
	await _refresh_global_chat()
	if chat_poll_timer == null:
		chat_poll_timer = Timer.new()
		chat_poll_timer.wait_time = 5.0
		chat_poll_timer.timeout.connect(_refresh_global_chat)
		add_child(chat_poll_timer)
	chat_poll_timer.start()

func _load_avatar_texture(avatar_file: String) -> Texture2D:
	var clean_name := avatar_file.trim_prefix("avatar_").get_basename()
	var image_path := "res://assets/avatars/%s.jpg" % clean_name
	# PNGs are imported by Godot into the PCK. Load the imported Texture2D
	# through ResourceLoader instead of reading the source bytes with FileAccess.
	var avatar_texture := ResourceLoader.load(image_path) as Texture2D
	if avatar_texture == null:
		push_warning("Baladi avatar texture could not be loaded from PCK: " + image_path)
	return avatar_texture

func _build_avatar_widget(path: String, frame_id: String, widget_size: int, avatar_id: String = "") -> Control:
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
	if not avatar_id.is_empty():
		var avatar_texture := _load_avatar_texture(avatar_id)
		if avatar_texture != null:
			picture.texture = avatar_texture
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(picture)
	if not path.is_empty() and avatar_id.is_empty():
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
	_add_page_heading("فروشگاه شخصی‌سازی", "قاب‌ها، آواتارها و آیتم‌های ویژه برای پروفایلت")
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
		card.custom_minimum_size = Vector2(0, 268)
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
			var frame_preview := _build_avatar_widget("", item_id, 108)
			body.add_child(frame_preview)
		elif item_kind == "avatar":
			var avatar_preview := TextureRect.new()
			var avatar_file := item_id.trim_prefix("avatar_")
			var avatar_texture := _load_avatar_texture(avatar_file)
			avatar_preview.texture = avatar_texture if avatar_texture != null else load("res://assets/icons/profile.svg")
			avatar_preview.custom_minimum_size = Vector2(108, 108)
			avatar_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			avatar_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			avatar_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			body.add_child(avatar_preview)
		elif item_kind == "avatar_unlock":
			var avatar_preview := TextureRect.new()
			avatar_preview.texture = load("res://assets/icons/profile.svg")
			avatar_preview.custom_minimum_size = Vector2(108, 108)
			avatar_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			avatar_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			avatar_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			body.add_child(avatar_preview)
		elif not asset_path.is_empty() and asset_path.begins_with("assets/stickers/"):
			var item_art := TextureRect.new()
			item_art.texture = load("res://" + asset_path)
			item_art.custom_minimum_size = Vector2(104, 104)
			item_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			item_art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			item_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			body.add_child(item_art)
		var price := Label.new()
		price.text = "رایگان" if int(item.get("price_coins", 0)) == 0 else "%s سکه" % _format_coin_price(item.get("price_coins", 0))
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.add_theme_font_size_override("font_size", 15)
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
			elif item_kind == "avatar":
				var equip_avatar := _make_button("انتخاب این تصویر" if equipped_avatar_id != item_id else "تصویر فعال", Color("#287c68"), CREAM)
				equip_avatar.disabled = equipped_avatar_id == item_id
				equip_avatar.pressed.connect(func(): _equip_cosmetic_avatar(item_id))
				body.add_child(equip_avatar)
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

func _equip_cosmetic_avatar(avatar_id: String) -> void:
	var result: Dictionary = await CloudAccount.equip_avatar(avatar_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "انتخاب تصویر پروفایل انجام نشد.")), RED)
		return
	_apply_cloud_profile(result.get("profile", {}))
	equipped_avatar_id = avatar_id
	_show_profile()

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
	_add_page_heading("رقابت ماهانه", "با بهترین بازیکنان رقابت کن و جایزه بگیر")
	if guest_mode:
		_set_status("برای شرکت در رقابت ماهانه و دریافت جایزه، وارد حساب کاربری شو.", GOLD)
	else:
		var result: Dictionary = await CloudAccount.get_leaderboard()
		if not result.get("ok", false):
			_set_status(str(result.get("error", "جدول رتبه‌بندی بارگذاری نشد.")), RED)
		else:
			var month_key := str(result.get("monthly_month_key", ""))
			var month_parts := month_key.split("-")
			var month_names := ["", "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور", "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"]
			var month_label := month_key
			if month_parts.size() == 2:
				var month_number := int(month_parts[1])
				if month_number >= 1 and month_number <= 12:
					month_label = "%s %s" % [month_names[month_number], month_parts[0]]
			var period_label := Label.new()
			period_label.text = "جدول امتیازات %s" % month_label
			period_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			period_label.add_theme_font_size_override("font_size", 17)
			period_label.add_theme_color_override("font_color", TEAL)
			content_box.add_child(period_label)
			var criteria := Label.new()
			criteria.text = "اولویت رتبه: واژه معتبر ← مرحله ← سکه کسب‌شده ← برد دونفره"
			criteria.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			criteria.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			criteria.add_theme_font_size_override("font_size", 12)
			criteria.add_theme_color_override("font_color", MUTED)
			content_box.add_child(criteria)

			var prize_panel := _panel(GOLD)
			content_box.add_child(prize_panel)
			var prize_stack := VBoxContainer.new()
			prize_stack.add_theme_constant_override("separation", 5)
			prize_panel.add_child(prize_stack)
			var prize_title := Label.new()
			prize_title.text = "جوایز پایان ماه"
			prize_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			prize_title.add_theme_color_override("font_color", GOLD)
			prize_title.add_theme_font_size_override("font_size", 17)
			prize_stack.add_child(prize_title)
			for prize in ["🥇 نفر اول: ۷٬۵۰۰ سکه", "🥈 نفر دوم: ۴٬۸۰۰ سکه", "🥉 نفر سوم: ۳٬۰۰۰ سکه"]:
				var prize_label := Label.new()
				prize_label.text = prize
				prize_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				prize_label.add_theme_font_size_override("font_size", 15)
				prize_label.add_theme_color_override("font_color", CREAM)
				prize_stack.add_child(prize_label)

			var monthly_players: Array = result.get("monthly_leaderboard", [])
			if monthly_players.is_empty():
				_set_status("هنوز امتیازی برای این ماه ثبت نشده است. اولین نفری باش که وارد رقابت می‌شود!", TEAL)
			else:
				for player in monthly_players:
					var player_id := str(player.get("user_id", ""))
					var rank := int(player.get("rank", 0))
					var medal := "🥇" if rank == 1 else ("🥈" if rank == 2 else ("🥉" if rank == 3 else "#%d" % rank))
					var player_name := _safe_player_name(player.get("display_name", null)) + ("  ✓" if bool(player.get("is_verified", false)) else "")
					var player_experience_level := int(player.get("experience_level", 1))
					var row_text := "%s  %s  ·  سطح %d\nواژه: %s  ·  مرحله: %s\nسکه: %s  ·  برد: %s" % [
						medal, player_name, player_experience_level,
						_format_coin_price(int(player.get("valid_words", 0))),
						_format_coin_price(int(player.get("highest_level", 0))),
						_format_coin_price(int(player.get("coins_earned", 0))),
						_format_coin_price(int(player.get("duel_wins", 0)))
					]
					var row_color := Color("#5A4828") if rank == 1 else (Color("#39434C") if rank == 2 else (Color("#59402F") if rank == 3 else PANEL_ALT))
					var row := _make_button(row_text, row_color, CREAM)
					row.custom_minimum_size = Vector2(0, 82)
					row.pressed.connect(func(): _show_public_profile(player_id))
					content_box.add_child(row)

			var previous_heading := Label.new()
			previous_heading.text = "برندگان ماه گذشته"
			previous_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			previous_heading.add_theme_font_size_override("font_size", 18)
			previous_heading.add_theme_color_override("font_color", GOLD)
			content_box.add_child(previous_heading)
			var previous_key := str(result.get("previous_month_key", ""))
			var previous_winners: Array = result.get("previous_month_winners", [])
			if previous_winners.is_empty():
				_set_status("هنوز سابقه جایزه ماهانه‌ای ثبت نشده است.", MUTED)
			else:
				for winner in previous_winners:
					var winner_rank := int(winner.get("rank", 0))
					var winner_name := _safe_player_name(winner.get("display_name", null))
					var winner_label := Label.new()
					winner_label.text = "%s  %s  ·  %s سکه" % [
						"🥇" if winner_rank == 1 else ("🥈" if winner_rank == 2 else "🥉"),
						winner_name, _format_coin_price(int(winner.get("reward_coins", 0)))
					]
					winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					winner_label.add_theme_font_size_override("font_size", 14)
					winner_label.add_theme_color_override("font_color", CREAM)
					content_box.add_child(winner_label)

			var alltime_heading := Label.new()
			alltime_heading.text = "رتبه‌بندی کلی بازیکنان"
			alltime_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			alltime_heading.add_theme_font_size_override("font_size", 19)
			alltime_heading.add_theme_color_override("font_color", GOLD)
			content_box.add_child(alltime_heading)
			for player in result.get("leaderboard", []):
				var player_id := str(player.get("user_id", ""))
				var rank := int(player.get("rank", 0))
				var player_name := _safe_player_name(player.get("display_name", null)) + ("  ✓" if bool(player.get("is_verified", false)) else "")
				var player_experience_level := int(player.get("experience_level", 1))
				var row := _make_button("#%d   %s   ·   سطح %d   ·   مرحله %d   ·   %s سکه" % [
					rank, player_name, player_experience_level, int(player.get("current_level", 1)),
					_format_coin_price(int(player.get("coins", 0)))
				], PANEL_ALT, CREAM)
				row.pressed.connect(func(): _show_public_profile(player_id))
				content_box.add_child(row)
	var back := _make_button("بازگشت", PANEL, CREAM)
	back.pressed.connect(_show_profile)
	content_box.add_child(back)

func _open_chat_public_profile(target_user_id: String) -> void:
	public_profile_return_page = current_page if current_page in ["global_chat", "group_chat"] else "leaderboard"
	_show_public_profile(target_user_id)

func _show_public_profile(target_user_id: String) -> void:
	current_page = "public_profile"
	if guest_mode:
		return
	_clear_content()
	var result: Dictionary = await CloudAccount.get_public_profile(target_user_id)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "پروفایل بازیکن بارگذاری نشد.")), RED)
		var back_error := _make_button("بازگشت به رتبه‌بندی", PANEL_ALT, CREAM)
		back_error.pressed.connect(_return_from_public_profile)
		content_box.add_child(back_error)
		return
	var player: Dictionary = result.get("profile", {})
	var public_avatar := _build_avatar_widget(str(player.get("avatar_path", "")), str(player.get("equipped_frame_id", "frame_default")), 92, str(player.get("equipped_avatar_id", "")))
	content_box.add_child(public_avatar)
	var heading := Label.new()
	heading.text = _safe_player_name(player.get("display_name", null)) + ("  ✓" if bool(player.get("is_verified", false)) else "")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", GOLD)
	content_box.add_child(heading)
	var public_tag := Label.new()
	public_tag.text = "تگ بازیکن: " + str(player.get("player_tag", "نامشخص"))
	public_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	public_tag.add_theme_color_override("font_color", GOLD)
	public_tag.add_theme_font_size_override("font_size", 15)
	content_box.add_child(public_tag)
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
	back.pressed.connect(_return_from_public_profile)
	content_box.add_child(back)

func _return_from_public_profile() -> void:
	_navigate_back_to(public_profile_return_page)

func _add_profile_stat(parent: GridContainer, caption: String, value: String, accent: Color) -> void:
	var tile := _panel(accent)
	tile.custom_minimum_size = Vector2(0, 82)
	parent.add_child(tile)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.layout_direction = Control.LAYOUT_DIRECTION_RTL
	stack.add_theme_constant_override("separation", 3)
	tile.add_child(stack)
	var number := Label.new()
	number.text = value
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	number.add_theme_font_size_override("font_size", 21)
	number.add_theme_color_override("font_color", accent)
	stack.add_child(number)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	var stage_id := int(levels[index].get("id", index + 1))
	var previous_stage_id := int(levels[index - 1].get("id", index)) if index > 0 else 0
	var is_unlocked := stage_id <= cloud_current_level or completed_levels.has(stage_id) or (index > 0 and completed_levels.has(previous_stage_id))
	if not is_unlocked:
		return
	level_index = index
	_save()
	_show_game()
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
	board_panel.custom_minimum_size.y = 168
	content_box.add_child(board_panel)
	board_box = GridContainer.new()
	board_box.columns = 1
	board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_box.add_theme_constant_override("h_separation", 9)
	board_box.add_theme_constant_override("v_separation", 9)
	board_panel.add_child(board_box)
	_render_board()

	var selection_panel := _panel(Color("#9a7738"))
	selection_panel.custom_minimum_size.y = 76
	content_box.add_child(selection_panel)
	selection_label = Label.new()
	selection_label.text = "حروف را با کشیدن انگشت به هم وصل کن"
	selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selection_label.add_theme_font_size_override("font_size", 19)
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
	hint_button = _make_button("راهنماها", Color("#765a31"), CREAM)
	hint_button.pressed.connect(_show_hint_menu)
	actions.add_child(hint_button)

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
	field.custom_minimum_size.y = maxf(field.custom_minimum_size.y, 52.0)
	field.add_theme_font_size_override("font_size", 15)
	field.add_theme_color_override("font_color", CREAM)
	field.add_theme_color_override("font_placeholder_color", Color("#8ca99d"))
	field.add_theme_color_override("caret_color", GOLD)
	field.add_theme_color_override("selection_color", Color("#4b8876", 0.55))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#0d2925")
	normal.border_color = Color("#345d50")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(15)
	normal.content_margin_left = 15
	normal.content_margin_right = 15
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	field.add_theme_stylebox_override("normal", normal)
	var focus := normal.duplicate()
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	focus.shadow_color = Color(0.93, 0.78, 0.47, 0.16)
	focus.shadow_size = 5
	field.add_theme_stylebox_override("focus", focus)

func _panel(border_color: Color = Color("#31594d")) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#112f2a")
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(0, 0, 0, 0.30)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_button(label_text: String, color: Color, text_color: Color) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("icon_normal_color", text_color)
	button.add_theme_color_override("icon_hover_color", text_color)
	button.add_theme_color_override("icon_pressed_color", text_color)
	button.add_theme_constant_override("outline_size", 0)
	button.clip_text = true
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.border_color = color.lightened(0.16)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(15)
	normal.shadow_color = Color(0, 0, 0, 0.22)
	normal.shadow_size = 5
	normal.shadow_offset = Vector2(0, 3)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.10)
	hover.border_color = color.lightened(0.24)
	hover.shadow_size = 7
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.10)
	pressed.shadow_size = 1
	pressed.shadow_offset = Vector2(0, 1)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate()
	disabled.bg_color = Color("#263d37")
	disabled.border_color = Color("#344e45")
	button.add_theme_stylebox_override("disabled", disabled)
	var focus := normal.duplicate()
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
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
	var progress_percent := int(round(float(words.size()) / float(maxi(1, answers.size())) * 100.0))
	var progress := Label.new()
	progress.text = "%d از %d واژه  ·  %d٪" % [words.size(), answers.size(), progress_percent]
	progress.add_theme_font_size_override("font_size", 13)
	progress.add_theme_color_override("font_color", GOLD if progress_percent >= 100 else MUTED)
	header.add_child(progress)

	var progress_bar := ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = max(1, answers.size())
	progress_bar.value = 0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size.y = 10
	var progress_track := StyleBoxFlat.new()
	progress_track.bg_color = Color("#0b211f")
	progress_track.set_corner_radius_all(6)
	progress_bar.add_theme_stylebox_override("background", progress_track)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color("#d2ad62") if progress_percent >= 100 else Color("#55b99b")
	progress_fill.set_corner_radius_all(6)
	progress_bar.add_theme_stylebox_override("fill", progress_fill)
	journal.add_child(progress_bar)
	if words.size() > 0:
		var progress_tween := create_tween()
		progress_tween.tween_property(progress_bar, "value", words.size(), 0.48).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

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
	# Three compact word chips fit across the board on the 480px game viewport.
	# This prevents the third discovered word from wrapping while visible space remains.
	found_grid.columns = 3
	found_grid.add_theme_constant_override("h_separation", 7)
	found_grid.add_theme_constant_override("v_separation", 7)
	journal.add_child(found_grid)
	var chip_index := 0
	for word_value in words:
		var chip := PanelContainer.new()
		var chip_style := StyleBoxFlat.new()
		chip_style.bg_color = Color("#1d5145")
		chip_style.border_color = Color("#c5a35e")
		chip_style.set_border_width_all(1)
		chip_style.set_corner_radius_all(15)
		chip_style.shadow_color = Color(0, 0, 0, 0.18)
		chip_style.shadow_size = 3
		chip_style.shadow_offset = Vector2(0, 2)
		chip_style.content_margin_left = 8
		chip_style.content_margin_right = 8
		chip_style.content_margin_top = 7
		chip_style.content_margin_bottom = 7
		chip.add_theme_stylebox_override("panel", chip_style)
		var word_label := Label.new()
		word_label.text = "✦  " + str(word_value)
		word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		word_label.add_theme_font_size_override("font_size", 18)
		word_label.add_theme_color_override("font_color", CREAM)
		chip.add_child(word_label)
		found_grid.add_child(chip)
		chip.scale = Vector2(0.86, 0.86)
		chip.modulate.a = 0.0
		var chip_tween := create_tween()
		chip_tween.set_parallel(true)
		chip_tween.tween_property(chip, "scale", Vector2.ONE, 0.24).set_delay(float(chip_index) * 0.035).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		chip_tween.tween_property(chip, "modulate:a", 1.0, 0.18).set_delay(float(chip_index) * 0.035)
		chip_index += 1

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
		hover_style.border_color = Color("#f0d99d")
		button.add_theme_stylebox_override("hover", hover_style)
		var pressed_style := circle_style.duplicate()
		pressed_style.bg_color = Color("#94743d")
		pressed_style.border_color = Color("#ffe4a5")
		button.add_theme_stylebox_override("pressed", pressed_style)
		var focus_style := circle_style.duplicate()
		focus_style.border_color = GOLD
		focus_style.set_border_width_all(3)
		button.add_theme_stylebox_override("focus", focus_style)
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
	_style_letter_state(button, true)
	_play_sfx("select")
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.16, 1.16), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_update_selection_label()
	_update_controls()

func _style_letter_state(button: Button, selected: bool) -> void:
	if button == null or not is_instance_valid(button):
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#94743d") if selected else Color("#205247")
	style.border_color = Color("#ffe3a0") if selected else Color("#d4b46f")
	style.set_border_width_all(3 if selected else 2)
	style.set_corner_radius_all(34)
	style.shadow_color = Color(0.88, 0.68, 0.30, 0.34) if selected else Color(0, 0, 0, 0.28)
	style.shadow_size = 9 if selected else 5
	style.shadow_offset = Vector2(0, 4 if selected else 3)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_color_override("font_color", Color("#fff1c8") if selected else CREAM)
	button.add_theme_color_override("font_hover_color", Color("#fff1c8"))
	button.scale = Vector2(1.08, 1.08) if selected else Vector2.ONE

func _finish_trace() -> void:
	if not is_dragging:
		return
	is_dragging = false
	active_pointer = -1
	trace_line.visible = false
	trace_line.clear_points()
	if not selected_word.is_empty():
		_submit_word()

func _find_scroll_container_at(node: Node, point: Vector2) -> ScrollContainer:
	var best: ScrollContainer = null
	if node is ScrollContainer:
		var candidate := node as ScrollContainer
		if candidate.is_visible_in_tree() and candidate.get_global_rect().has_point(point):
			best = candidate
	for child in node.get_children():
		var found := _find_scroll_container_at(child, point)
		if found != null:
			if best == null or found.get_global_rect().get_area() < best.get_global_rect().get_area():
				best = found
	return best

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK):
		_handle_back_request()
		get_viewport().set_input_as_handled()
		return

	# Allow vertical touch-drag scrolling from every child control, not only empty background.
	# Keep custom drag interactions (letter tracing and avatar cropping) in control.
	if current_page != "avatar_crop":
		if event is InputEventScreenTouch:
			if event.pressed:
				page_touch_scroll = _find_scroll_container_at(get_tree().root, event.position)
				page_touch_active = page_touch_scroll != null
				page_touch_scrolling = false
				page_touch_start = event.position
				page_touch_scroll_start = page_touch_scroll.scroll_vertical if page_touch_active else 0
				if page_touch_active and letters_grid != null and is_instance_valid(letters_grid) and _letter_at(event.position) >= 0:
					page_touch_active = false
					page_touch_scroll = null
			else:
				if page_touch_scrolling:
					get_viewport().set_input_as_handled()
				page_touch_active = false
				page_touch_scrolling = false
				page_touch_scroll = null
		elif event is InputEventScreenDrag and page_touch_active and page_touch_scroll != null and is_instance_valid(page_touch_scroll):
			var drag: Vector2 = event.position - page_touch_start
			if not page_touch_scrolling and absf(drag.y) >= 8.0 and absf(drag.y) > absf(drag.x) * 1.15:
				page_touch_scrolling = true
			if page_touch_scrolling:
				var scroll_bar := page_touch_scroll.get_v_scroll_bar()
				var max_scroll := maxi(0, int(scroll_bar.max_value))
				page_touch_scroll.scroll_vertical = clampi(page_touch_scroll_start - int(drag.y), 0, max_scroll)
				get_viewport().set_input_as_handled()
				return

	if letters_grid == null or not is_instance_valid(letters_grid):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_trace(event.position)
		else:
			_finish_trace()
	elif event is InputEventMouseMotion and is_dragging:
		_continue_trace(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_begin_trace(event.position)
	elif event is InputEventScreenDrag and is_dragging:
		_continue_trace(event.position)
	elif event is InputEventScreenTouch and not event.pressed:
		_finish_trace()

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
			_style_letter_state(letter_buttons[index], false)
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
				_show_duel_result(_duel_winner_id(duel_data), int(duel_data.get("elapsed_ms", 0)))
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
			_add_local_experience(5)
			_spawn_floating_text("+5 XP", GOLD)
			_play_sfx("found")
			_animate_coin_reward(3)
			if _is_level_complete():
				_complete_guest_level()
			else:
				_set_status("آفرین! واژه پیدا شد و ۳ سکه گرفتی.", GREEN)
				_render_board()
		else:
			# Show the found word immediately. Cloud persistence runs in the background.
			var member_words := _words_for_current_level()
			member_words.append(matched)
			level_solved[str(stage_id)] = member_words
			pending_word_syncs += 1
			_play_sfx("found")
			_clear_selection()
			_render_board()
			_save()
			_set_status("آفرین! واژه پیدا شد.", GREEN)
			_sync_found_word(matched, stage_id)
			return
	else:
		# Give immediate feedback for a non-answer. Bonus-word validation must never
		# keep the selected letters on screen while waiting for the network.
		_set_status("این واژه پاسخ این مرحله نیست.", RED)
		_clear_selection()
		_update_controls()
		_check_bonus_word(candidate, stage_id)
		return
	_clear_selection()
	_update_controls()

func _check_bonus_word(candidate: String, stage_id: int) -> void:
	if guest_mode:
		if not bonus_word_set.has(candidate):
			_set_status("این واژه در واژه‌نامهٔ جایزه‌ای ثبت نشده است.", RED)
			return
		var guest_bonus_words := _bonus_words_for_current_level()
		if guest_bonus_words.has(candidate):
			_set_status("این واژه را قبلاً پیدا کرده‌ای؛ پاداش آن قبلاً پرداخت شده است.", GOLD)
			return
		guest_bonus_words.append(candidate)
		level_bonus_found[str(stage_id)] = guest_bonus_words
		coins += 7
		_add_local_experience(5)
		_animate_coin_reward(7)
		_spawn_floating_text("+5 XP", GOLD)
		_show_bonus_word_feedback(candidate)
		_save()
		return
	var bonus_result: Dictionary = await CloudAccount.record_word_found(candidate, stage_id)
	if not bonus_result.get("ok", false):
		# The immediate invalid-word feedback has already been shown. Only surface
		# a server error if it is a real connection/validation failure.
		_set_status(str(bonus_result.get("error", "بررسی واژه جایزه‌ای انجام نشد.")), RED)
		return
	if bonus_result.get("already_found", false):
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
		var bonus_xp := int(bonus_result.get("xp_awarded", 0))
		if bonus_xp > 0 and current_page == "game":
			_spawn_floating_text("+%d XP" % bonus_xp, GOLD)
		_show_bonus_word_feedback(candidate)
		_save()

func _sync_found_word(word: String, stage_id: int) -> void:
	var word_result: Dictionary = await CloudAccount.record_word_found(word, stage_id)
	pending_word_syncs = maxi(0, pending_word_syncs - 1)
	if not word_result.get("ok", false):
		var words = level_solved.get(str(stage_id), [])
		if words is Array and words.has(word):
			words.erase(word)
			level_solved[str(stage_id)] = words
			if current_page == "game" and not levels.is_empty() and int(levels[level_index].get("id", level_index + 1)) == stage_id:
				_render_board()
		_save()
		_set_status(str(word_result.get("error", "ثبت واژه در حساب انجام نشد؛ دوباره تلاش کن.")), RED)
		return
	if word_result.get("already_found", false):
		_set_status("این واژه قبلاً در حسابت ثبت شده است.", GOLD)
	else:
		_apply_cloud_profile(word_result.get("profile", {}))
		var awarded := int(word_result.get("coins_awarded", 3))
		if awarded > 0:
			_animate_coin_reward(awarded)
		var awarded_xp := int(word_result.get("xp_awarded", 0))
		if awarded_xp > 0 and current_page == "game":
			_spawn_floating_text("+%d XP" % awarded_xp, GOLD)
	_save()
	if pending_word_syncs == 0 and current_page == "game" and not duel_mode and not levels.is_empty() and int(levels[level_index].get("id", level_index + 1)) == stage_id and _is_level_complete():
		var completion: Dictionary = await CloudAccount.complete_level(stage_id)
		if completion.get("ok", false):
			_apply_cloud_profile(completion.get("profile", {}))
			var completion_xp := int(completion.get("xp_awarded", 0))
			if completion_xp > 0:
				_spawn_floating_text("+%d XP برای تکمیل مرحله" % completion_xp, GOLD)
			_show_stage_complete(int(levels[level_index].get("reward", 0)))
		else:
			_set_status(str(completion.get("error", "ثبت تکمیل مرحله انجام نشد.")), RED)
			_render_board()

func _complete_guest_level() -> void:
	var stage_id := int(levels[level_index].get("id", level_index + 1))
	if completed_levels.has(stage_id):
		return
	completed_levels.append(stage_id)
	levels_completed_count = maxi(levels_completed_count, completed_levels.size())
	var reward := int(levels[level_index].get("reward", 0))
	coins += reward
	_add_local_experience(20)
	_spawn_floating_text("+20 XP برای تکمیل مرحله", GOLD)
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
		status_label.pivot_offset = status_label.size * 0.5
		var feedback := create_tween()
		if color == RED:
			var base_position := status_label.position
			feedback.tween_property(status_label, "position:x", base_position.x - 7.0, 0.045)
			feedback.tween_property(status_label, "position:x", base_position.x + 7.0, 0.045)
			feedback.tween_property(status_label, "position:x", base_position.x - 4.0, 0.04)
			feedback.tween_property(status_label, "position:x", base_position.x, 0.05)
			feedback.parallel().tween_property(status_label, "scale", Vector2(1.025, 1.025), 0.10)
			feedback.tween_property(status_label, "scale", Vector2.ONE, 0.12)
		elif color == GREEN:
			feedback.tween_property(status_label, "scale", Vector2(1.06, 1.06), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			feedback.tween_property(status_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
			_show_duel_result(_duel_winner_id(hint_data.get("result", {})), int(hint_data.get("result", {}).get("elapsed_ms", 0)))
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
			_show_duel_result(_duel_winner_id(hint_data.get("result", {})), int(hint_data.get("result", {}).get("elapsed_ms", 0)))
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
			_return_from_public_profile()
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
		get_viewport().set_input_as_handled()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_save()
		if not guest_mode and CloudAccount.is_authenticated():
			await CloudAccount.touch_session()
