# BetterHttp

**BetterHttp** is a high-performance, multithreaded HTTP client plugin for Godot 4.x.

It provides a modern, script-based alternative to the standard `HTTPRequest` node. By leveraging `WorkerThreadPool` and low-level `HTTPClient`, BetterHttp executes network requests asynchronously on background threads without blocking the main game loop or requiring nodes to be added to the SceneTree.

## Features

* **True Multithreading:** Utilizes Godot's `WorkerThreadPool` to handle DNS resolution, connection, and data transfer off the main thread. Prevents frame drops during heavy network operations.
* **Node-Independent:** Operates as a global Singleton (Autoload). Call it from anywhere (`Node`, `Resource`, `RefCounted`, or other threads) without `add_child()`.
* **Await Support:** Fully supports modern GDScript `await` syntax for linear, readable code execution.
* **Smart Object Pooling:** Implements an internal pool for `HTTPClient` instances to minimize memory allocation overhead and reduce Garbage Collection (GC) pressure.
* **Type Safety:** Returns a strongly typed `HttpResponse` object, providing full Autocomplete/IntelliSense support in the Godot Editor.
* **Built-in Utilities:** Includes automatic JSON parsing, smart header merging, and automatic User-Agent handling to prevent server rejection.

## Installation

1. Copy the `better_http` folder into your project's `addons/` directory.
2. Open **Project** -> **Project Settings** -> **Plugins**.
3. Enable **BetterHttp**.
4. **Restart the editor** to ensure the Autoload singleton is registered correctly.

## Usage

### Basic GET Request

```gdscript
func _ready():
	# Returns a strongly typed HttpResponse object
	var response = await BetterHttp.GET("https://jsonplaceholder.typicode.com/todos/1")
	
	if response.is_success():
		# Automatically parse JSON
		var data = response.json()
		print("Title: ", data["title"])
	else:
		push_error("Request failed. Code: %d" % response.code)

```

### POST Request with JSON

```gdscript
func send_score():
	var payload = JSON.stringify({
		"username": "PlayerOne",
		"score": 9999
	})
	
	# Content-Type header is set to application/json by default for POST
	var response = await BetterHttp.POST("https://api.example.com/scores", payload)
	
	if response.is_success():
		print("Score submitted successfully.")

```

### Custom Headers

```gdscript
func get_protected_data():
	var headers = [
		"Authorization: Bearer YOUR_TOKEN",
        "Custom-Header: Value"
	]
	
	var response = await BetterHttp.GET("https://api.example.com/protected", headers)

```

### Binary Data (Downloading Files)

```gdscript
func download_image():
	var response = await BetterHttp.GET("https://godotengine.org/assets/logo.png")
	
	if response.is_success():
		var image = Image.new()
		# Access raw bytes via body_raw
		var err = image.load_png_from_buffer(response.body_raw)
		if err == OK:
			var texture = ImageTexture.create_from_image(image)
			$Sprite2D.texture = texture

```

## API Reference

### Methods

All methods are asynchronous and must be awaited.

* `GET(url: String, headers: PackedStringArray = []) -> HttpResponse`
* `POST(url: String, body: String, headers: PackedStringArray = [...]) -> HttpResponse`
* `PUT(url: String, body: String, headers: PackedStringArray = [...]) -> HttpResponse`
* `DELETE(url: String, headers: PackedStringArray = []) -> HttpResponse`

### HttpResponse Object

The `HttpResponse` object returned by requests contains the following properties and methods:

* **Properties:**
* `code` (int): HTTP status code (e.g., 200, 404).
* `headers` (Dictionary): Response headers.
* `body_raw` (PackedByteArray): Raw response body.
* `error` (int): Godot `Error` enum (e.g., `OK`, `ERR_CANT_CONNECT`).


* **Methods:**
* `is_success() -> bool`: Returns `true` if `error` is `OK` and `code` is between 200-299.
* `text() -> String`: returns the body as a UTF-8 string.
* `json() -> Variant`: Parses the body as JSON. Returns `null` on failure.
* `save_to_file(path: String) -> Error`: Saves the raw body directly to a file.

## Example

![Example Code](doc/example.png)

![Example Result](doc/result.png)

## License

MIT License. Free to use in personal and commercial projects.
