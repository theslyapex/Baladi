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
	var response_code := int(response[1])
	var raw_body: PackedByteArray = response[3]
	var parsed = JSON.parse_string(raw_body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		var message := "درخواست ناموفق بود."
		if parsed is Dictionary:
			message = str(parsed.get("msg", parsed.get("message", parsed.get("error_description", parsed.get("error", message)))))
		return {"ok": false, "error": message, "status": response_code}
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
		_clear_auth()
		return false
	_accept_session(result.data)
	return true

func api(action: String, extra: Dictionary = {}) -> Dictionary:
	if not await _refresh_if_needed():
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

func record_word_found(word: String, level: int) -> Dictionary:
	return await api("word_found", {"word": word, "level": level, "session_id": game_session_id})

func sign_out() -> void:
	await end_session()
	_clear_auth()
