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
	var array_header = header_dict_to_array(final_headers)
	var client = _borrow_client()
	var job = HttpJob.new(client, final_url, method, array_header, body, defaults.timeout)
	
	# 线程池执行
	WorkerThreadPool.add_task(job.execute)
	# 等待 Job 返回原始字典
	var raw_result: Dictionary = await job.finished
	
	_return_client(client)
	
	# [关键点] 将字典包装为强类型的 HttpResponse 对象
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

func header_dict_to_array(headers: Dictionary) -> PackedStringArray:
	var result:PackedStringArray = []
	for key in headers.keys():
		result.append("%s: %s" % [key, headers[key]])
	return result

# --- 池化逻辑 (线程安全) ---
func _borrow_client() -> HTTPClient:
	_pool_mutex.lock() # 锁定，防止多线程竞争
	var client: HTTPClient
	
	if _client_pool.is_empty():
		# 池空了，不得不新建一个
		client = HTTPClient.new()
		# 可以在这里设置一些全局默认值，如 blocking_mode_enabled = false
	else:
		# 复用旧的
		client = _client_pool.pop_back()
		
	_pool_mutex.unlock() # 解锁
	return client

func _return_client(client: HTTPClient):
	# 简单清洗一下状态
	# 注意：connect_to_host 会自动重置状态，但为了保险可以手动 close
	# 如果你想做 Keep-Alive (连接复用)，逻辑会复杂十倍，这里先做对象复用
	client.close()
	
	_pool_mutex.lock()
	if _client_pool.size() < MAX_POOL_SIZE:
		_client_pool.append(client)
	else:
		# 池子满了，这个多余的 client 就让它随风而去(被 GC)吧
		pass
	_pool_mutex.unlock()
# --- 公开 API (全大写) ---

func GET(url: String, headers: Dictionary = {}) -> BetterHttpResponse:
	var common_headers = merge_header(headers, defaults.headers.COMMON)
	var final_headers = merge_header(common_headers, defaults.headers.GET)
	return await _request(url, M_GET, final_headers, "")

func POST(url: String, data: String, headers: Dictionary = {"Content-Type": "application/json"}) -> BetterHttpResponse:
	var common_headers = merge_header(headers, defaults.headers.COMMON)
	var final_headers = merge_header(common_headers, defaults.headers.POST)
	return await _request(url, M_POST, final_headers, data)

func PUT(url: String, data: String, headers: Dictionary = {"Content-Type": "application/json"}) -> BetterHttpResponse:
	var common_headers = merge_header(headers, defaults.headers.COMMON)
	var final_headers = merge_header(common_headers, defaults.headers.PUT)
	return await _request(url, M_PUT, final_headers, data)

func DELETE(url: String, headers: Dictionary = {}) -> BetterHttpResponse:
	var common_headers = merge_header(headers, defaults.headers.COMMON)
	var final_headers = merge_header(common_headers, defaults.headers.DELETE)
	return await _request(url, M_DELETE, final_headers, "")
