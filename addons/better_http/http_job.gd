extends RefCounted
class_name HttpJob

signal finished(result: Dictionary)

var _client: HTTPClient
var _url: String
var _method: int
var _headers: PackedStringArray
var _body: String
var _timeout: float  # 改为浮点数，单位秒

func _init(client: HTTPClient, url: String, method: int, headers: PackedStringArray, body: String, timeout: float = 6.0):
	_client = client
	_url = url
	_method = method
	_headers = headers
	_body = body
	_timeout = timeout

# --- 主执行流程 ---
func execute():
	var start_time = Time.get_ticks_msec()
	
	# 准备一个空的返回结构
	var response_data = {
		"code": 0,
		"headers": {},
		"body": PackedByteArray(),
		"length": 0,
		"error": OK
	}
	
	# Step 1: 解析 URL
	if _check_timeout(start_time):
		_finish(response_data, ERR_TIMEOUT)
		return
		
	var url_info = _parse_url(_url)
	if not url_info.valid:
		_finish(response_data, ERR_INVALID_PARAMETER)
		return

	# Step 2: 连接服务器（带超时）
	if _check_timeout(start_time):
		_finish(response_data, ERR_TIMEOUT)
		return
		
	var conn_err = _connect_client_with_timeout(url_info, start_time)
	if conn_err != OK:
		_finish(response_data, conn_err)
		return

	# Step 3: 发送请求
	if _check_timeout(start_time):
		_finish(response_data, ERR_TIMEOUT)
		_client.close()
		return
		
	var req_err = _send_request(url_info)
	if req_err != OK:
		_finish(response_data, req_err)
		_client.close()
		return

	# Step 4: 读取响应（带超时）
	if _check_timeout(start_time):
		_finish(response_data, ERR_TIMEOUT)
		_client.close()
		return
		
	var read_err = _read_response_with_timeout(response_data, start_time)
	
	# Step 5: 完成
	_finish(response_data, read_err)
	_client.close()

# --- 超时检查函数 ---
func _check_timeout(start_time: int) -> bool:
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	return elapsed > _timeout

# --- 带超时的连接 ---
func _connect_client_with_timeout(url_info: Dictionary, start_time: int) -> int:
	_client.close()
	
	var opts = TLSOptions.client() if url_info.is_ssl else null
	var err = _client.connect_to_host(url_info.domain, url_info.port, opts)
	
	if err != OK:
		return err
		
	# 带超时的轮询
	var poll_start = Time.get_ticks_msec()
	while _client.get_status() == HTTPClient.STATUS_CONNECTING or _client.get_status() == HTTPClient.STATUS_RESOLVING:
		_client.poll()
		
		# 检查连接超时
		if _check_timeout(start_time):
			_client.close()
			return ERR_TIMEOUT
			
		# 检查单个操作超时（DNS解析等）
		var poll_elapsed = (Time.get_ticks_msec() - poll_start) / 1000.0
		if poll_elapsed > min(_timeout / 2.0, 10.0):  # 最多等待10秒或总超时的一半
			_client.close()
			return ERR_TIMEOUT
			
		OS.delay_msec(10)  # 稍微延迟，避免 CPU 占用过高
		
	if _client.get_status() != HTTPClient.STATUS_CONNECTED:
		return FAILED
		
	return OK

# --- 带超时的发送请求 ---
func _send_request(url_info: Dictionary) -> int:
	# 等待上一个请求状态结束
	var poll_start = Time.get_ticks_msec()
	while _client.get_status() == HTTPClient.STATUS_REQUESTING:
		_client.poll()
		
		var poll_elapsed = (Time.get_ticks_msec() - poll_start) / 1000.0
		if poll_elapsed > 5.0:  # 请求发送最多等待5秒
			return ERR_TIMEOUT
			
		OS.delay_msec(1)
		
	var err = _client.request(_method, url_info.path, _headers, _body)
	return err

# --- 带超时的读取响应 ---
func _read_response_with_timeout(out_data: Dictionary, start_time: int) -> int:
	# 等待请求发送完成并开始接收响应
	var wait_start = Time.get_ticks_msec()
	while _client.get_status() == HTTPClient.STATUS_REQUESTING:
		_client.poll()
		
		if _check_timeout(start_time):
			return ERR_TIMEOUT
			
		var wait_elapsed = (Time.get_ticks_msec() - wait_start) / 1000.0
		if wait_elapsed > 5.0:  # 等待响应最多5秒
			return ERR_TIMEOUT
			
		OS.delay_msec(10)
	
	# 检查是否有响应
	if not _client.has_response():
		return FAILED
		
	# 读取元数据
	out_data["code"] = _client.get_response_code()
	out_data["headers"] = _client.get_response_headers_as_dictionary()
	
	if not _client.is_response_chunked():
		out_data["length"] = _client.get_response_body_length()
	
	# 读取 Body（带超时）
	var rb = PackedByteArray()
	var body_start = Time.get_ticks_msec()
	
	while _client.get_status() == HTTPClient.STATUS_BODY:
		_client.poll()
		
		# 检查总超时
		if _check_timeout(start_time):
			return ERR_TIMEOUT
			
		# 检查读取 Body 超时（单独计算，因为可能下载大文件）
		var body_elapsed = (Time.get_ticks_msec() - body_start) / 1000.0
		if body_elapsed > _timeout * 0.8:  # 给 Body 读取分配 80% 的时间
			return ERR_TIMEOUT
			
		var chunk = _client.read_response_body_chunk()
		if chunk.size() > 0:
			rb.append_array(chunk)
			body_start = Time.get_ticks_msec()  # 重置超时计时器（只要有数据）
		else:
			# 没有数据时，等待一下但不要太长
			var chunk_elapsed = (Time.get_ticks_msec() - body_start) / 1000.0
			if chunk_elapsed > 2.0:  # 单个 chunk 最多等待2秒
				return ERR_TIMEOUT
			OS.delay_msec(50)
			
	out_data["body"] = rb
	return OK

# --- 原有的辅助函数（保持不变）---
func _parse_url(input_url: String) -> Dictionary:
	var result = {
		"valid": false,
		"domain": "",
		"port": 80,
		"path": "/",
		"is_ssl": false
	}
	
	var is_ssl = input_url.begins_with("https://")
	var scheme = "https://" if is_ssl else "http://"
	
	var url_no_scheme = input_url
	if input_url.begins_with(scheme):
		url_no_scheme = input_url.substr(scheme.length())
	elif input_url.begins_with("http://"): 
		is_ssl = false
		scheme = "http://"
		url_no_scheme = input_url.substr(7)
	
	var slash_pos = url_no_scheme.find("/")
	var authority = ""
	
	if slash_pos == -1:
		authority = url_no_scheme
		result.path = "/"
	else:
		authority = url_no_scheme.left(slash_pos)
		result.path = url_no_scheme.substr(slash_pos)
		
	var domain = authority
	var port = 443 if is_ssl else 80
	
	var colon_pos = authority.find(":")
	if colon_pos != -1:
		domain = authority.left(colon_pos)
		var p_str = authority.substr(colon_pos + 1)
		if p_str.is_valid_int():
			port = p_str.to_int()
	
	result.domain = domain
	result.port = port
	result.is_ssl = is_ssl
	result.valid = true
	
	if domain.is_empty():
		result.valid = false
	
	return result

# --- 结束处理 ---
func _finish(data: Dictionary, error_code: int):
	data["error"] = error_code
	if error_code == ERR_TIMEOUT:
		data["code"] = 408  # HTTP 408 Request Timeout
	if data["body"] == null:
		data["body"] = PackedByteArray()
	call_deferred("_emit_main", data)

func _emit_main(data: Dictionary):
	finished.emit(data)
