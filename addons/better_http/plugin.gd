@tool
extends EditorPlugin


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	add_autoload_singleton("BetterHttp", "res://addons/better_http/better_http.gd")

func _exit_tree() -> void:
	remove_autoload_singleton("BetterHttp")
