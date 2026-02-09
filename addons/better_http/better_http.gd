# addons/better_http/better_http.gd
extends Node

# 定义常用方法常量
const M_GET = HTTPClient.METHOD_GET
const M_POST = HTTPClient.METHOD_POST
const M_PUT = HTTPClient.METHOD_PUT
const M_DELETE = HTTPClient.METHOD_DELETE
const M_HEAD = HTTPClient.METHOD_HEAD
# --- 对象池配置 ---
var _client_pool: Array[HTTPClient] = []
var _pool_mutex: Mutex = Mutex.new()
const MAX_POOL_SIZE = 20 # 只要不是几百个，内存占用都极小

# --- 核心请求方法 ---
func _request(url: String, method: int, headers: PackedStringArray, body: String) -> BetterHttpResponse:
	# --- 新增：智能合并 Headers ---
	var final_headers = headers.duplicate()
	
	# 检查是否已经有 User-Agent，如果没有则加上 Godot 的标准 UA
	if not _has_header(final_headers, "User-Agent"):
		final_headers.append("User-Agent: GodotEngine/%s (BetterHttp Addon)" % Engine.get_version_info().string)
	
	# 告诉服务器：我支持所有类型
	if not _has_header(final_headers, "Accept"):
		final_headers.append("Accept: */*")
		
	# (进阶) 如果你后续实现了 GZIP 解压，加上这个头会让数据传输更小，且百度更倾向于发 UTF-8
	# final_headers.append("Accept-Encoding: gzip, deflate")
	# [加锁] 从池中借出一个 Client
	var client = _borrow_client()
	
	# 创建 Job，注入 Client
	var job = HttpJob.new(client, url, method, headers, body)
	
	# 丢给线程池执行
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
	
	return response

# --- 池化逻辑 (线程安全) ---
# 简单的辅助函数，检查 headers 数组里是否包含某个 key
func _has_header(headers: PackedStringArray, key: String) -> bool:
	key = key.to_lower() + ":"
	for h in headers:
		if h.to_lower().begins_with(key):
			return true
	return false
	
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

func GET(url: String, headers: PackedStringArray = []) -> BetterHttpResponse:
	return await _request(url, M_GET, headers, "")

func POST(url: String, data: String, headers: PackedStringArray = ["Content-Type: application/json"]) -> BetterHttpResponse:
	return await _request(url, M_POST, headers, data)

func PUT(url: String, data: String, headers: PackedStringArray = ["Content-Type: application/json"]) -> BetterHttpResponse:
	return await _request(url, M_PUT, headers, data)

func DELETE(url: String, headers: PackedStringArray = []) -> BetterHttpResponse:
	return await _request(url, M_DELETE, headers, "")
