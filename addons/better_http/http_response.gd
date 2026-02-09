extends RefCounted
class_name BetterHttpResponse

# --- 公开属性 (只读建议) ---
var status: int
var headers: Dictionary
var _body_raw: PackedByteArray
var _error: int # Godot 的 Error 枚举
var length: int

# --- 初始化 ---
func _init(p_code: int = 0, p_headers: Dictionary = {}, p_body: PackedByteArray = PackedByteArray(), p_error: int = OK, p_length:int = 0):
	status = p_code
	headers = p_headers
	_body_raw = p_body
	_error = p_error
	length = p_length

# --- 核心功能：获取文本 ---
func text() -> String:
	return _body_raw.get_string_from_utf8()

# --- 核心功能：获取 JSON ---
# 如果解析失败，返回 null，方便调用者判断
func json() -> Variant:
	var txt = text()
	if txt.is_empty():
		return null
		
	var json_parser = JSON.new()
	var err = json_parser.parse(txt)
	
	if err == OK:
		return json_parser.data
	else:
		push_warning("BetterHttp: JSON Parse Error on line %s: %s" % [json_parser.get_error_line(), json_parser.get_error_message()])
		return null

# --- 辅助功能：是否成功 ---
func is_success() -> bool:
	return _error == OK and status >= 200 and status < 300
