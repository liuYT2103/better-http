extends Node2D
@onready var sprite_2d: Sprite2D = $Sprite2D

func _ready() -> void:
	BetterHttp.defaults.base_url = "https://jsonplaceholder.typicode.com" # Default URL 支持配置默认地址
	BetterHttp.defaults.headers.COMMON["Authorization"] = "Bearer Token" # Default Headers 支持配置默认请求头
	BetterHttp.defaults.headers.GET["Authorization"] = "Bearer Get Token" # Default Header With Method 支持根据请求方式配置默认请求头
	BetterHttp.defaults.timeout = 5.0
	
	var request_interceptor = func(url:String, method, headers, body):
		print("URL: %s" % url)
		print("Final Headers: %s" % JSON.stringify(headers))
		return url.ends_with("3")
	BetterHttp.interceptors.use_request(request_interceptor) # Request Interceptor 支持请求拦截器
	
	var response_interceptor = func(response:BetterHttpResponse):
		print("Response Status: %s" % response.status)
	BetterHttp.interceptors.use_response(response_interceptor) # Response Interceptor 支持响应拦截器
	
	var resp = await BetterHttp.GET("/posts/3")
	if resp.is_success():
		print(resp.headers["Content-Type"])	
		print(resp.text()) # Simple Response Reader 简易响应获取
		print(resp.json()) # Simple Json Method JSON语法糖
	else:
		print(resp._errmsg) 
	
	BetterHttp.interceptors.eject_request(request_interceptor) # Clean Interceptor 清除指定拦截器
	BetterHttp.interceptors.eject_response(response_interceptor)
		
func _process(delta: float) -> void:
	# 请求不阻塞游戏运行
	sprite_2d.global_position += Vector2.RIGHT * delta * 100 # This module is designed to test asynchronously.
