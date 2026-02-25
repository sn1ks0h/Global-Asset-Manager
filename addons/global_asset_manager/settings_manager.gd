@tool
class_name SettingsManager
extends AcceptDialog

signal settings_changed
signal database_cleared

const ALL_3D_FORMATS: PackedStringArray = ["glb", "gltf", "fbx"]
const ALL_2D_FORMATS: PackedStringArray = ["png", "jpg", "jpeg", "webp"]
const ALL_AUDIO_FORMATS: PackedStringArray = ["ogg", "mp3", "wav"]

var db: Dictionary

var _current_path_target: String = ""

@onready var clear_button: Button = $ScrollContainer/VBoxContainer/DangerZoneBox/ClearButton
@onready var dir_dialog: FileDialog = $DirDialog
@onready var path_btn_2d: Button = $ScrollContainer/VBoxContainer/PathsVBox/Path2DBox/Path2DBtn
@onready var path_btn_3d: Button = $ScrollContainer/VBoxContainer/PathsVBox/Path3DBox/Path3DBtn
@onready var path_btn_audio: Button = $ScrollContainer/VBoxContainer/PathsVBox/PathAudioBox/PathAudioBtn
@onready var path_btn_shader: Button = $ScrollContainer/VBoxContainer/PathsVBox/PathShaderBox/PathShaderBtn
@onready var path_edit_2d: LineEdit = $ScrollContainer/VBoxContainer/PathsVBox/Path2DBox/Path2DEdit
@onready var path_edit_3d: LineEdit = $ScrollContainer/VBoxContainer/PathsVBox/Path3DBox/Path3DEdit
@onready var path_edit_audio: LineEdit = $ScrollContainer/VBoxContainer/PathsVBox/PathAudioBox/PathAudioEdit
@onready var path_edit_shader: LineEdit = $ScrollContainer/VBoxContainer/PathsVBox/PathShaderBox/PathShaderEdit
@onready var reset_button: Button = $ScrollContainer/VBoxContainer/DangerZoneBox/ResetButton
@onready var settings_tree: Tree = $ScrollContainer/VBoxContainer/SettingsTree
@onready var volume_label: Label = $ScrollContainer/VBoxContainer/VolumeLabel
@onready var volume_slider: HSlider = $ScrollContainer/VBoxContainer/VolumeSlider
@onready var wav_length_label: Label = $ScrollContainer/VBoxContainer/WavLengthLabel
@onready var wav_length_slider: HSlider = $ScrollContainer/VBoxContainer/WavLengthSlider

func save_database() -> void:
	var file := FileAccess.open("user://asset_database.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(db, "\t"))

func setup(database: Dictionary) -> void:
	db = database
	_verify_settings_schema()
	_update_ui_from_db()

	if not wav_length_slider.value_changed.is_connected(_on_wav_length_changed):
		wav_length_slider.value_changed.connect(_on_wav_length_changed)
	if not wav_length_slider.drag_ended.is_connected(_on_wav_length_drag_ended):
		wav_length_slider.drag_ended.connect(_on_wav_length_drag_ended)

func _ready() -> void:
	settings_tree.item_edited.connect(_on_settings_tree_item_edited)

	volume_slider.value_changed.connect(_on_volume_changed)
	volume_slider.drag_ended.connect(_on_volume_drag_ended)

	path_btn_3d.pressed.connect(func() -> void: _open_dir_dialog("3d"))
	path_btn_2d.pressed.connect(func() -> void: _open_dir_dialog("2d"))
	path_btn_audio.pressed.connect(func() -> void: _open_dir_dialog("audio"))
	path_btn_shader.pressed.connect(func() -> void: _open_dir_dialog("shader"))

	path_edit_3d.text_changed.connect(func(text: String) -> void: _update_path("3d", text))
	path_edit_2d.text_changed.connect(func(text: String) -> void: _update_path("2d", text))
	path_edit_audio.text_changed.connect(func(text: String) -> void: _update_path("audio", text))
	path_edit_shader.text_changed.connect(func(text: String) -> void: _update_path("shader", text))

	reset_button.pressed.connect(_on_reset_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	dir_dialog.dir_selected.connect(_on_dir_selected)

func _add_setting_category(parent: TreeItem, label: String, formats: PackedStringArray) -> void:
	var category_item := settings_tree.create_item(parent)
	category_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	category_item.set_text(0, label)
	category_item.set_editable(0, true)
	category_item.set_metadata(0, "category")

	var all_checked := true
	for ext in formats:
		var child := settings_tree.create_item(category_item)
		child.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		child.set_text(0, "." + ext)
		child.set_editable(0, true)

		var is_active: bool = db["settings"]["active_formats"].has(ext)
		child.set_checked(0, is_active)
		child.set_metadata(0, ext)

		if not is_active:
			all_checked = false

	category_item.set_checked(0, all_checked)

func _on_clear_pressed() -> void:
	database_cleared.emit()
	hide()

func _on_dir_selected(dir: String) -> void:
	if _current_path_target == "3d": path_edit_3d.text = dir
	elif _current_path_target == "2d": path_edit_2d.text = dir
	elif _current_path_target == "audio": path_edit_audio.text = dir
	elif _current_path_target == "shader": path_edit_shader.text = dir

	_update_path(_current_path_target, dir)

func _on_reset_pressed() -> void:
	db["settings"].clear()
	_verify_settings_schema()
	_update_ui_from_db()
	save_database()
	settings_changed.emit()

func _on_settings_tree_item_edited() -> void:
	var item := settings_tree.get_edited()
	var is_checked := item.is_checked(0)
	var meta: Variant = item.get_metadata(0)

	if meta is String and meta == "category":
		for i in range(item.get_child_count()):
			var child := item.get_child(i)
			child.set_checked(0, is_checked)
			var ext: String = child.get_metadata(0)
			_update_active_format(ext, is_checked)
	elif meta is String:
		_update_active_format(meta, is_checked)
		var parent := item.get_parent()
		if parent:
			var all_checked := true
			for i in range(parent.get_child_count()):
				if not parent.get_child(i).is_checked(0):
					all_checked = false
			parent.set_checked(0, all_checked)

	save_database()
	settings_changed.emit()

func _on_volume_changed(value: float) -> void:
	volume_label.text = "Max Audio Volume: " + str(int(value)) + "%"

func _on_volume_drag_ended(_value_changed: bool) -> void:
	db["settings"]["volume"] = volume_slider.value
	save_database()
	settings_changed.emit()

func _on_wav_length_changed(value: float) -> void:
	wav_length_label.text = "WAV Preview Length: " + str(int(value)) + "s"

func _on_wav_length_drag_ended(_value_changed: bool) -> void:
	db["settings"]["wav_preview_length"] = int(wav_length_slider.value)
	save_database()
	settings_changed.emit()

func _open_dir_dialog(target: String) -> void:
	_current_path_target = target
	dir_dialog.current_dir = "res://"
	dir_dialog.popup_centered()

func _populate_settings_tree() -> void:
	settings_tree.clear()
	var root := settings_tree.create_item()

	_add_setting_category(root, "3D Models", ALL_3D_FORMATS)
	_add_setting_category(root, "2D Images", ALL_2D_FORMATS)
	_add_setting_category(root, "Audio", ALL_AUDIO_FORMATS)

func _update_active_format(ext: String, is_active: bool) -> void:
	var active_list: Array = db["settings"]["active_formats"]
	if is_active and not active_list.has(ext):
		active_list.append(ext)
	elif not is_active and active_list.has(ext):
		active_list.erase(ext)

func _update_path(target: String, new_path: String) -> void:
	db["settings"]["import_path_" + target] = new_path
	save_database()
	settings_changed.emit()

func _update_ui_from_db() -> void:
	var s: Dictionary = db["settings"]
	volume_slider.value = s["volume"]
	volume_label.text = "Max Audio Volume: " + str(int(s["volume"])) + "%"

	wav_length_slider.value = s["wav_preview_length"]
	wav_length_label.text = "WAV Preview Length: " + str(int(s["wav_preview_length"])) + "s"

	path_edit_3d.text = s["import_path_3d"]
	path_edit_2d.text = s["import_path_2d"]
	path_edit_audio.text = s["import_path_audio"]
	path_edit_shader.text = s["import_path_shader"]

	_populate_settings_tree()

func _verify_settings_schema() -> void:
	if not db.has("settings"):
		db["settings"] = {}

	var s: Dictionary = db["settings"]
	if not s.has("active_formats"): s["active_formats"] = ["glb", "gltf", "png", "jpg", "jpeg", "webp", "ogg", "mp3", "wav"]
	if not s.has("volume"): s["volume"] = 25.0
	if not s.has("import_path_3d"): s["import_path_3d"] = "res://assets/models"
	if not s.has("import_path_2d"): s["import_path_2d"] = "res://assets/images"
	if not s.has("import_path_audio"): s["import_path_audio"] = "res://assets/audio"
	if not s.has("import_path_shader"): s["import_path_shader"] = "res://assets/shaders"
	if not s.has("wav_preview_length"): s["wav_preview_length"] = 10
