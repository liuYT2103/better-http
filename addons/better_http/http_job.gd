# addons/better_http/http_job.gd
extends RefCounted
class_name HttpJob

# 注意：为了线程安全传递数据，通常建议信号传 Dictionary，
# 由主线程的 Manager 包装成 BetterHttpResponse 对象。
# 如果你确定要在线程内实例化资源对象，请确保该类是线程安全的。
signal finished(result: Dictionary)

var _client: HTTPClient
var _url: String
var _method: int
var _headers: PackedStringArray
var _body: String

func _init(client: HTTPClient, url: String, method: int, headers: PackedStringArray, body: String):
	_client = client
	_url = url
	_method = method
	_headers = headers
	_body = body

# --- 主执行流程 ---
func execute():
	# 准备一个空的返回结构
	var response_data = {
		"code": 0,
		"headers": {},
		"body": PackedByteArray(),
		"length": 0,
		"error": OK
	}
	
	# Step 1: 解析 URL
	var url_info = _parse_url(_url)
	if not url_info.valid:
		_finish(response_data, ERR_INVALID_PARAMETER)
		return

	# Step 2: 连接服务器
	var conn_err = _connect_client(url_info)
	if conn_err != OK:
		_finish(response_data, conn_err)
		return

	# Step 3: 发送请求
	var req_err = _send_request(url_info)
	if req_err != OK:
		_finish(response_data, req_err)
		return

	# Step 4: 读取响应 (填充 response_data)
	var read_err = _read_response(response_data)
	
	# Step 5: 完成
	_finish(response_data, read_err)


# --- 辅助函数：URL 解析 ---
func _parse_url(input_url: String) -> Dictionary:
	var result = {
		"valid": false,
		"domain": "",
		"port": 80,
		"path": "/",
		"is_ssl": false
	}
	
	# A. 确定协议
	var is_ssl = input_url.begins_with("https://")
	var scheme = "https://" if is_ssl else "http://"
	
	# B. 剥离协议头
	var url_no_scheme = input_url
	if input_url.begins_with(scheme):
		url_no_scheme = input_url.substr(scheme.length())
	elif input_url.begins_with("http://"): 
		# 修正：用户输入 http:// 但原本判定逻辑可能是 https 的情况
		is_ssl = false
		scheme = "http://"
		url_no_scheme = input_url.substr(7)
	
	# C. 分离 域名部分(Authority) 和 路径部分(Path)
	var slash_pos = url_no_scheme.find("/")
	var authority = ""
	
	if slash_pos == -1:
		authority = url_no_scheme
		result.path = "/"
	else:
		authority = url_no_scheme.left(slash_pos)
		result.path = url_no_scheme.substr(slash_pos)
		
	# D. 从 Authority 中分离 端口
	var domain = authority
	var port = 443 if is_ssl else 80
	
	var colon_pos = authority.find(":")
	if colon_pos != -1:
		domain = authority.left(colon_pos)
		var p_str = authority.substr(colon_pos + 1)
		if p_str.is_valid_int():
			port = p_str.to_int()
	
	# 填充结果
	result.domain = domain
	result.port = port
	result.is_ssl = is_ssl
	result.valid = true
	
	# 简单校验
	if domain.is_empty():
		result.valid = false
	
	return result


# --- 辅助函数：建立连接 ---
func _connect_client(url_info: Dictionary) -> int:
	# 确保重置旧状态
	_client.close()
	
	var opts = TLSOptions.client() if url_info.is_ssl else null
	var err = _client.connect_to_host(url_info.domain, url_info.port, opts)
	
	if err != OK:
		return err
		
	# 轮询直到连接成功或失败
	while _client.get_status() == HTTPClient.STATUS_CONNECTING or _client.get_status() == HTTPClient.STATUS_RESOLVING:
		_client.poll()
		OS.delay_msec(2)
		
	if _client.get_status() != HTTPClient.STATUS_CONNECTED:
		return FAILED
		
	return OK


# --- 辅助函数：发送请求 ---
func _send_request(url_info: Dictionary) -> int:
	# 等待上一个请求状态结束（如果是复用连接）
	while _client.get_status() == HTTPClient.STATUS_REQUESTING:
		_client.poll()
		OS.delay_msec(1)
		
	var err = _client.request(_method, url_info.path, _headers, _body)
	return err


# --- 辅助函数：读取响应 ---
func _read_response(out_data: Dictionary) -> int:
	# 等待请求发送完成并开始接收响应
	while _client.get_status() == HTTPClient.STATUS_REQUESTING:
		_client.poll()
		OS.delay_msec(1)
	
	# 检查是否有响应
	if not _client.has_response():
		return FAILED
		
	# 读取元数据
	out_data["code"] = _client.get_response_code()
	out_data["headers"] = _client.get_response_headers_as_dictionary()
	
	if not _client.is_response_chunked():
		out_data["length"] = _client.get_response_body_length()
	
	# 读取 Body (循环)
	var rb = PackedByteArray()
	
	# 预分配内存优化 (如果是 Content-Length 模式)
	# 注意：resize 会填充 0，所以 append 逻辑需要调整，或者直接用 append_array 让底层处理
	# 这里为了通用性和安全性，还是用 append_array，但必须避免 + 操作符
	
	while _client.get_status() == HTTPClient.STATUS_BODY:
		_client.poll()
		var chunk = _client.read_response_body_chunk()
		if chunk.size() > 0:
			# [重要优化] 使用 append_array 而不是 +
			rb.append_array(chunk)
		else:
			OS.delay_msec(1)
			
	out_data["body"] = rb
	return OK


# --- 结束处理 ---
func _finish(data: Dictionary, error_code: int):
	data["error"] = error_code
	
	# 如果发生错误，且没有 Body，确保 body 字段不是 null
	if data["body"] == null:
		data["body"] = PackedByteArray()
		
	call_deferred("_emit_main", data)

func _emit_main(data: Dictionary):
	finished.emit(data)
