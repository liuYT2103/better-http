extends Node

const M_GET = HTTPClient.METHOD_GET
const M_POST = HTTPClient.METHOD_POST
const M_PUT = HTTPClient.METHOD_PUT
const M_DELETE = HTTPClient.METHOD_DELETE
const M_HEAD = HTTPClient.METHOD_HEAD

var _client_pool: Array[HTTPClient] = []
var _pool_mutex: Mutex = Mutex.new()
const MAX_POOL_SIZE = 20

var defaults := BetterHTTPDefaults.new()
var interceptors := BetterHTTPInterceptors.new()

func _request(url: String, method: int, headers: Dictionary, body: String) -> BetterHttpResponse:
	var final_headers = headers.duplicate()
	var final_url = defaults.base_url + url
	# 检查是否已经有 User-Agent，如果没有则加上 Godot 的标准 UA
	if not final_headers.get("User-Agent"):
		final_headers["User-Agent"] = "GodotEngine/%s (BetterHttp Addon)" % Engine.get_version_info().string
	
	# 告诉服务器：我支持所有类型
	if not final_headers.get("Accept"):
		final_headers["Accept"] = "*/*"
	
	for interceptor in interceptors._request:
		var _pass = await interceptor.call(final_url, method, final_headers, body)
		if not _pass:
			var response = BetterHttpResponse.new()
			response._set_error(ERR_CANT_RESOLVE, "Request cancelled by interceptor")
			return response
		
	# final_headers.append("Accept-Encoding: gzip, deflate")
	# 创建 Job，注入 Client
	var array_header = dict_to_array(final_headers, ": ")
	var client = _borrow_client()
	var job = HttpJob.new(client, final_url, method, array_header, body, defaults.timeout)
	
	# 线程池执行
	WorkerThreadPool.add_task(job.execute)
	# 等待 Job 返回原始字典
	var raw_result: Dictionary = await job.finished
	
	_return_client(client)
	
	# 包装为 HttpResponse 对象
	var response = BetterHttpResponse.new(
		raw_result["code"],
		raw_result["headers"],
		raw_result["body"],
		raw_result["error"],
		raw_result["length"]
	)
	
	for interceptor in interceptors._response:
		await interceptor.call(response)
		
	return response

func merge_header(headers: Dictionary, addons:Dictionary) -> Dictionary:
	headers.merge(addons, true)
	return headers

func dict_to_array(headers: Dictionary, symbol:String = "=") -> PackedStringArray:
	var result:PackedStringArray = []
	for key in headers.keys():
		result.append("%s%s%s" % [key, symbol, headers[key]])
	return result

# --- 池化逻辑 (线程安全) ---
func _borrow_client() -> HTTPClient:
	_pool_mutex.lock() # 锁定，防止多线程竞争
	var client: HTTPClient
	
	if _client_pool.is_empty():
		# 池空了新建一个
		client = HTTPClient.new()
	else:
		# 复用旧的
		client = _client_pool.pop_back()
		
	_pool_mutex.unlock() # 解锁
	return client

func _return_client(client: HTTPClient):
	client.close()
	
	_pool_mutex.lock()
	if _client_pool.size() < MAX_POOL_SIZE:
		_client_pool.append(client)
	else:
		# 池子满了，这个多余的 client GC 吧
		pass
	_pool_mutex.unlock()

# --- 公开 API ---
func GET(url: String, query: Dictionary = {}, headers: Dictionary = {}) -> BetterHttpResponse:
	url = _process_query(url, query)
	return await _process_request_with_data(url, M_GET, null, headers)

func POST(url: String, data: Variant = null, headers: Dictionary = {}) -> BetterHttpResponse:
	return await _process_request_with_data(url, M_POST, data, headers)

func PUT(url: String, data: Variant = null, headers: Dictionary = {}) -> BetterHttpResponse:
	return await _process_request_with_data(url, M_PUT, data, headers)

func DELETE(url: String, query: Dictionary = {}, headers: Dictionary = {}) -> BetterHttpResponse:
	url = _process_query(url, query)
	return await _process_request_with_data(url, M_DELETE, null, headers)

# --- 内部统一处理逻辑 ---
func _process_query(url:String, query:Dictionary) -> String:
	if not query.is_empty():
		var client_temp = HTTPClient.new()
		var query_string = client_temp.query_string_from_dict(query)
		
		if "?" in url:
			url += "&" + query_string
		else:
			url += "?" + query_string
	return url

func _process_request_with_data(url: String, method: int, data: Variant, extra_headers: Dictionary) -> BetterHttpResponse:
	# 1. 统一合并三层 Header: Common + Method-Specific + Extra
	var final_headers = defaults.headers.COMMON.duplicate()
	
	# 根据 method 获取对应的默认 header 配置
	var method_defaults = {}
	match method:
		M_GET: method_defaults = defaults.headers.GET
		M_POST: method_defaults = defaults.headers.POST
		M_PUT: method_defaults = defaults.headers.PUT
		M_DELETE: method_defaults = defaults.headers.DELETE
	
	final_headers.merge(method_defaults, true)
	final_headers.merge(extra_headers, true)
	
	# 2. 自动序列化逻辑
	var body_str = ""
	if data != null:
		if data is Dictionary or data is Array:
			body_str = JSON.stringify(data)
			if not final_headers.has("Content-Type") and not final_headers.has("content-type"):
				final_headers["Content-Type"] = "application/json"
		else:
			body_str = str(data)
	
	return await _request(url, method, final_headers, body_str)
