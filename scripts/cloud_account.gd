extends Node

const SUPABASE_URL := "https://srfldjfrzmtnlabusssq.supabase.co"
const SUPABASE_KEY := "sb_publishable_UW2Wzzp8Y-KKd82nZHQUKA_RGl876RB"
const AUTH_PATH := SUPABASE_URL + "/auth/v1"
const GAME_API := SUPABASE_URL + "/functions/v1/baladi-game"
const AUTH_SAVE_PATH := "user://baladi_auth.cfg"

var access_token := ""
var refresh_token := ""
var user_id := ""
var user_email := ""
var display_name := ""
var expires_at := 0
var game_session_id := ""

func is_authenticated() -> bool:
	return not access_token.is_empty() and not user_id.is_empty()

func _headers(with_auth: bool = false) -> PackedStringArray:
	var result := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + SUPABASE_KEY
	])
	if with_auth and not access_token.is_empty():
		result.append("Authorization: Bearer " + access_token)
	return result

func _request_json(url: String, method: int, headers: PackedStringArray, payload: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 25.0
	add_child(request)
	var request_error := request.request(url, headers, method, JSON.stringify(payload))
	if request_error != OK:
		request.queue_free()
		return {"ok": false, "error": "اتصال اینترنت برقرار نشد."}
	var response: Array = await request.request_completed
	request.queue_free()
	var request_result := int(response[0])
	var response_code := int(response[1])
	var raw_body: PackedByteArray = response[3]
	var response_text := raw_body.get_string_from_utf8()
	var parsed = JSON.parse_string(response_text)
	if request_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "ارتباط با سرور برقرار نشد. اتصال اینترنت یا دسترسی شبکه را بررسی کن.", "request_result": request_result, "status": response_code}
	if response_code < 200 or response_code >= 300:
		var message := "سرور درخواست را نپذیرفت (کد %d)." % response_code
		if parsed is Dictionary:
			for key in ["msg", "message", "error_description", "error", "error_code", "code"]:
				if parsed.has(key) and not str(parsed[key]).strip_edges().is_empty():
					message = str(parsed[key])
					break
		return {"ok": false, "error": message, "status": response_code, "response": response_text}
	if parsed is Dictionary:
		return {"ok": true, "data": parsed}
	return {"ok": false, "error": "پاسخ سرور قابل خواندن نیست."}

func _accept_session(data: Dictionary) -> void:
	access_token = str(data.get("access_token", ""))
	refresh_token = str(data.get("refresh_token", ""))
	expires_at = int(data.get("expires_at", Time.get_unix_time_from_system() + int(data.get("expires_in", 3600))))
	var user: Dictionary = data.get("user", {})
	user_id = str(user.get("id", ""))
	user_email = str(user.get("email", ""))
	var metadata: Dictionary = user.get("user_metadata", {})
	display_name = str(metadata.get("full_name", metadata.get("name", "")))
	_save_auth()

func _save_auth() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "refresh_token", refresh_token)
	cfg.set_value("auth", "access_token", access_token)
	cfg.set_value("auth", "expires_at", expires_at)
	cfg.set_value("auth", "user_id", user_id)
	cfg.set_value("auth", "email", user_email)
	cfg.save(AUTH_SAVE_PATH)

func _clear_auth() -> void:
	access_token = ""
	refresh_token = ""
	user_id = ""
	user_email = ""
	display_name = ""
	expires_at = 0
	game_session_id = ""
	var cfg := ConfigFile.new()
	cfg.save(AUTH_SAVE_PATH)

func sign_in(email: String, password: String) -> Dictionary:
	var result := await _request_json(AUTH_PATH + "/token?grant_type=password", HTTPClient.METHOD_POST, _headers(), {
		"email": email.strip_edges().to_lower(),
		"password": password
	})
	if not result.ok:
		return result
	_accept_session(result.data)
	return {"ok": true, "email": user_email}

func sign_up(email: String, password: String, full_name: String) -> Dictionary:
	var result := await _request_json(AUTH_PATH + "/signup", HTTPClient.METHOD_POST, _headers(), {
		"email": email.strip_edges().to_lower(),
		"password": password,
		"data": {"full_name": full_name.strip_edges()}
	})
	if not result.ok:
		return result
	var data: Dictionary = result.data
	if data.has("access_token") and data.has("refresh_token"):
		_accept_session(data)
		return {"ok": true, "confirmed": true}
	return {"ok": true, "confirmed": false}

func restore_session() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(AUTH_SAVE_PATH) != OK:
		return false
	refresh_token = str(cfg.get_value("auth", "refresh_token", ""))
	if refresh_token.is_empty():
		return false
	var result := await _request_json(AUTH_PATH + "/token?grant_type=refresh_token", HTTPClient.METHOD_POST, _headers(), {
		"refresh_token": refresh_token
	})
	if not result.ok:
		# Keep credentials on transient network failures; clear only rejected refresh credentials.
		var status := int(result.get("status", 0))
		var message := str(result.get("error", "")).to_lower()
		if status in [400, 401, 403] and (message.contains("refresh") or message.contains("token") or message.contains("invalid")):
			_clear_auth()
		return false
	_accept_session(result.data)
	return is_authenticated()

func _refresh_if_needed() -> bool:
	if access_token.is_empty():
		return false
	if expires_at > Time.get_unix_time_from_system() + 90:
		return true
	if refresh_token.is_empty():
		return false
	var result := await _request_json(AUTH_PATH + "/token?grant_type=refresh_token", HTTPClient.METHOD_POST, _headers(), {
		"refresh_token": refresh_token
	})
	if not result.ok:
		# Do not discard a valid refresh credential because of a temporary offline/5xx response.
		var status := int(result.get("status", 0))
		var message := str(result.get("error", "")).to_lower()
		if status in [400, 401, 403] and (message.contains("refresh") or message.contains("token") or message.contains("invalid")):
			_clear_auth()
		return false
	_accept_session(result.data)
	return true

func api(action: String, extra: Dictionary = {}) -> Dictionary:
	var session_valid: bool = await _refresh_if_needed()
	if not session_valid:
		return {"ok": false, "error": "نشست حساب کاربری منقضی شده است. دوباره وارد شو."}
	var payload := {"action": action}
	for key in extra:
		payload[key] = extra[key]
	var result := await _request_json(GAME_API, HTTPClient.METHOD_POST, _headers(true), payload)
	if not result.ok:
		return result
	var data: Dictionary = result.data
	if not data.get("ok", false):
		return {"ok": false, "error": str(data.get("error", "عملیات انجام نشد."))}
	return data

func start_game_session() -> Dictionary:
	var result := await api("start_session")
	if result.ok:
		game_session_id = str(result.get("session", {}).get("id", ""))
	return result

func touch_session() -> Dictionary:
	if game_session_id.is_empty():
		return {"ok": false, "error": "نشست بازی فعال نیست."}
	return await api("touch_session", {"session_id": game_session_id})

func end_session() -> Dictionary:
	if game_session_id.is_empty():
		return {"ok": true}
	var result := await api("end_session", {"session_id": game_session_id})
	game_session_id = ""
	return result

func complete_level(level: int) -> Dictionary:
	return await api("complete_level", {"level": level, "session_id": game_session_id})

func use_hint(word: String, level: int) -> Dictionary:
	return await api("use_hint", {"word": word, "level": level, "session_id": game_session_id})

func update_profile_name(new_name: String) -> Dictionary:
	var result: Dictionary = await api("update_profile", {"display_name": new_name.strip_edges()})
	if result.get("ok", false):
		display_name = new_name.strip_edges()
	return result

func delete_account() -> Dictionary:
	var result: Dictionary = await api("delete_account", {"confirm": true})
	if result.get("ok", false):
		_clear_auth()
	return result

func daily_checkin() -> Dictionary:
	return await api("daily_checkin")

func use_hint_clue(hint_type: String, level: int, clue_key: String) -> Dictionary:
	return await api("hint_clue", {
		"hint_type": hint_type,
		"level": level,
		"session_id": game_session_id,
		"clue_key": clue_key
	})

func record_word_found(word: String, level: int) -> Dictionary:
	return await api("word_found", {"word": word, "level": level, "session_id": game_session_id})

func get_active_duel() -> Dictionary:
	return await api("active_duel")

func get_duel_invites() -> Dictionary:
	return await api("duel_invites_list")

func send_duel_invite(recipient_id: String) -> Dictionary:
	return await api("send_duel_invite", {"recipient_id": recipient_id})

func accept_duel_invite(invite_id: String) -> Dictionary:
	return await api("accept_duel_invite", {"invite_id": invite_id})

func decline_duel_invite(invite_id: String) -> Dictionary:
	return await api("decline_duel_invite", {"invite_id": invite_id})

func get_duel_state(match_id: String) -> Dictionary:
	return await api("duel_state", {"match_id": match_id})

func submit_duel_word(match_id: String, word: String) -> Dictionary:
	return await api("duel_submit_word", {"match_id": match_id, "word": word})

func spend_duel_hint(match_id: String, hint_type: String) -> Dictionary:
	return await api("duel_spend_hint", {"match_id": match_id, "hint_type": hint_type})

func fetch_groups() -> Dictionary:
	return await api("groups_list")

func get_my_group() -> Dictionary:
	return await api("my_group")

func create_group(group_name: String, description: String = "") -> Dictionary:
	return await api("create_group", {"name": group_name, "description": description})

func join_group(group_id: String) -> Dictionary:
	return await api("join_group", {"group_id": group_id})

func upgrade_group_capacity(group_id: String, new_capacity: int) -> Dictionary:
	return await api("upgrade_group_capacity", {"group_id": group_id, "new_capacity": new_capacity})

func set_group_role(group_id: String, target_user_id: String, role: String) -> Dictionary:
	return await api("set_group_role", {"group_id": group_id, "target_user_id": target_user_id, "role": role})

func remove_group_member(group_id: String, target_user_id: String) -> Dictionary:
	return await api("remove_group_member", {"group_id": group_id, "target_user_id": target_user_id})

func transfer_group_leadership(group_id: String, target_user_id: String) -> Dictionary:
	return await api("transfer_group_leadership", {"group_id": group_id, "target_user_id": target_user_id})

func leave_group(group_id: String) -> Dictionary:
	return await api("leave_group", {"group_id": group_id})

func get_group_chat_messages(group_id: String) -> Dictionary:
	return await api("group_chat_list", {"group_id": group_id})

func send_group_chat_message(group_id: String, message_body: String) -> Dictionary:
	return await api("group_chat_send", {"group_id": group_id, "body": message_body})

func send_group_chat_sticker(group_id: String, sticker_id: String) -> Dictionary:
	return await api("group_chat_send", {"group_id": group_id, "sticker_id": sticker_id})

func pin_group_chat_message(group_id: String, message_id: int, pinned: bool) -> Dictionary:
	return await api("pin_group_message", {"group_id": group_id, "message_id": message_id, "pinned": pinned})

func unlock_global_chat() -> Dictionary:
	return await api("unlock_global_chat")

func get_global_chat_messages() -> Dictionary:
	return await api("global_chat_list")

func send_global_chat_message(message_body: String) -> Dictionary:
	return await api("global_chat_send", {"body": message_body})

func send_global_chat_sticker(sticker_id: String) -> Dictionary:
	return await api("global_chat_send", {"sticker_id": sticker_id})

func get_cosmetics_catalog() -> Dictionary:
	return await api("cosmetics_catalog")

func purchase_cosmetic(cosmetic_id: String) -> Dictionary:
	return await api("purchase_cosmetic", {"cosmetic_id": cosmetic_id})

func equip_frame(frame_id: String) -> Dictionary:
	return await api("equip_frame", {"frame_id": frame_id})

func set_avatar_path(avatar_path: String) -> Dictionary:
	return await api("set_avatar_path", {"avatar_path": avatar_path})

func avatar_public_url(avatar_path: String) -> String:
	return SUPABASE_URL + "/storage/v1/object/public/baladi-avatars/" + avatar_path

func upload_avatar(image: Image) -> Dictionary:
	if not is_authenticated():
		return {"ok": false, "error": "برای بارگذاری تصویر باید وارد حساب شوی."}
	var session_valid: bool = await _refresh_if_needed()
	if not session_valid:
		return {"ok": false, "error": "نشست حساب کاربری منقضی شده است. دوباره وارد شو."}
	var bytes := image.save_jpg_to_buffer(0.9)
	if bytes.is_empty():
		return {"ok": false, "error": "تبدیل تصویر پروفایل ناموفق بود."}
	var file_name := "avatar_%d_%d.jpg" % [int(Time.get_unix_time_from_system()), randi()]
	var avatar_path := user_id + "/" + file_name
	var request := HTTPRequest.new()
	request.timeout = 30.0
	add_child(request)
	var headers := PackedStringArray([
		"Authorization: Bearer " + access_token,
		"apikey: " + SUPABASE_KEY,
		"Content-Type: image/jpeg",
		"x-upsert: false"
	])
	var request_error := request.request_raw(
		SUPABASE_URL + "/storage/v1/object/baladi-avatars/" + avatar_path,
		headers,
		HTTPClient.METHOD_POST,
		bytes
	)
	if request_error != OK:
		request.queue_free()
		return {"ok": false, "error": "بارگذاری تصویر شروع نشد."}
	var response: Array = await request.request_completed
	request.queue_free()
	var response_code := int(response[1])
	if response_code < 200 or response_code >= 300:
		var raw: PackedByteArray = response[3]
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		var message := "بارگذاری تصویر ناموفق بود."
		if parsed is Dictionary:
			message = str(parsed.get("message", parsed.get("error", message)))
		return {"ok": false, "error": message, "status": response_code}
	var saved: Dictionary = await set_avatar_path(avatar_path)
	if not saved.get("ok", false):
		return saved
	saved["avatar_path"] = avatar_path
	return saved

func get_leaderboard() -> Dictionary:
	return await api("leaderboard")

func get_public_profile(target_user_id: String) -> Dictionary:
	return await api("public_profile", {"user_id": target_user_id})

func sign_out() -> void:
	await end_session()
	_clear_auth()
