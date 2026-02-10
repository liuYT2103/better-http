English | [简体中文](../README.md)
# BetterHttp

**BetterHttp** is a high-performance, multithreaded HTTP client plugin for Godot 4.x.

It provides a modern, script-based alternative to the standard `HTTPRequest` node. By leveraging `WorkerThreadPool` and low-level `HTTPClient`, BetterHttp executes network requests asynchronously on background threads without blocking the main game loop or requiring nodes to be added to the SceneTree.

## Features

* **True Multithreading:** Utilizes Godot's `WorkerThreadPool` to handle DNS resolution, connection, and data transfer off the main thread. Prevents frame drops during heavy network operations.
* **Node-Independent:** Operates as a global Singleton (Autoload). Call it from anywhere (`Node`, `Resource`, `RefCounted`, or other threads) without `add_child()`.
* **Await Support:** Fully supports modern GDScript `await` syntax for linear, readable code execution.
* **Smart Object Pooling:** Implements an internal pool for `HTTPClient` instances to minimize memory allocation overhead and reduce Garbage Collection (GC) pressure.
* **Type Safety:** Returns a strongly typed `BetterHttpResponse` object, providing full Autocomplete/IntelliSense support in the Godot Editor.
* **Built-in Utilities:** Includes automatic JSON parsing, smart header merging, and automatic User-Agent handling to prevent server rejection.

## Installation

1. Copy the `better_http` folder into your project's `addons/` directory.
2. Open **Project** -> **Project Settings** -> **Plugins**.
3. Enable **BetterHttp**.
4. **Restart the editor** to ensure the Autoload singleton is registered correctly.

## Example

![Example Code](example.png)

Response Console Log :

![Example Result](result.png)

## Usage

### Default Options

```js
func _ready() -> void:
	BetterHttp.defaults.base_url = "https://jsonplaceholder.typicode.com"
	BetterHttp.defaults.headers.COMMON["Authorization"] = "Bearer Token"
	BetterHttp.defaults.headers.GET["Authorization"] = "Bearer Get Token"
	BetterHttp.defaults.timeout = 5.0
```

### Interceptor

```js
func _ready() -> void:
	var request_interceptor = func(url:String, method, headers, body):
		print("URL: %s" % url)
		print("Final Headers: %s" % JSON.stringify(headers))
		return url.ends_with("3")
	BetterHttp.interceptors.use_request(request_interceptor)
	
	var response_interceptor = func(response:BetterBetterHttpResponse):
		print("Response Status: %s" % response.status)
	BetterHttp.interceptors.use_response(response_interceptor)

	# clean
	BetterHttp.interceptors.eject_request(request_interceptor)
	BetterHttp.interceptors.eject_response(response_interceptor)
```

### Basic GET Request

```js
func _ready():
	# Returns a strongly typed BetterHttpResponse object
	var response = await BetterHttp.GET("https://jsonplaceholder.typicode.com/todos/1")
	
	if response.is_success():
		# Automatically parse JSON
		var data = response.json()
		print("Title: ", data["title"])
	else:
		push_error("Request failed. Code: %d" % response.code)

```

### POST Request with JSON

```js
func send_score():
	var payload = {
		"username": "PlayerOne",
		"score": 9999
	}
	
	# Content-Type header is set to application/json by default for POST
	var response = await BetterHttp.POST("https://api.example.com/scores", payload)
	
	if response.is_success():
		print("Score submitted successfully.")

```

## API Reference

### Methods

All methods are asynchronous and must be awaited.

* `GET(url: String, query: Dictionary, headers: PackedStringArray = []) -> BetterHttpResponse`
* `POST(url: String, body: String, headers: PackedStringArray = [...]) -> BetterHttpResponse`
* `PUT(url: String, body: String, headers: PackedStringArray = [...]) -> BetterHttpResponse`
* `DELETE(url: String, query: Dictionary, headers: PackedStringArray = []) -> BetterHttpResponse`

### BetterHttpResponse Object

The `BetterHttpResponse` object returned by requests contains the following properties and methods:

* **Properties:**
* `code` (int): HTTP status code (e.g., 200, 404).
* `headers` (Dictionary): Response headers.
* `body_raw` (PackedByteArray): Raw response body.
* `error` (int): Godot `Error` enum (e.g., `OK`, `ERR_CANT_CONNECT`).


* **Methods:**
* `is_success() -> bool`: Returns `true` if `error` is `OK` and `code` is between 200-299.
* `text() -> String`: returns the body as a UTF-8 string.
* `json() -> Variant`: Parses the body as JSON. Returns `null` on failure.

## License

MIT License. Free to use in personal and commercial projects.
