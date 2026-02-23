@tool
extends EditorPlugin

var main_panel_instance: Control


func _enter_tree() -> void:
	main_panel_instance = preload("res://addons/global_asset_manager/asset_manager.tscn").instantiate()
	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	_make_visible(false)

func _exit_tree() -> void:
	if main_panel_instance:
		main_panel_instance.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if main_panel_instance:
		main_panel_instance.visible = visible

func _get_plugin_name() -> String:
	return "AssetHub"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Load", "EditorIcons")
