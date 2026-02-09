extends Node2D
@onready var sprite_2d: Sprite2D = $Sprite2D

func _ready() -> void:
	var resp = await BetterHttp.GET("https://jsonplaceholder.typicode.com/todos/1")
	if resp.is_success():
		print(resp.status)
		print(resp.headers["Content-Type"])	
		var text = resp.text()
		print(text)
		var json = resp.json()
		print(json["title"])
		
func _process(delta: float) -> void:
	sprite_2d.global_position += Vector2.RIGHT * delta * 100
