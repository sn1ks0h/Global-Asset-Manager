@tool
@icon("res://icon.svg")
@static_unload
class_name AssetManager
extends Control
## Main interface for the Global Asset Manager plugin.

signal asset_selected(path: String)
signal db_updated

enum AssetType { MODEL_3D, IMAGE_2D, AUDIO, SHADER, UNKNOWN }

const ALL_3D_FORMATS: PackedStringArray = ["glb", "gltf", "fbx"]
const ALL_2D_FORMATS: PackedStringArray = ["png", "jpg", "jpeg", "webp"]
const ALL_AUDIO_FORMATS: PackedStringArray = ["ogg", "mp3", "wav"]
const DB_FILE_PATH: String = "user://asset_database.json"

var db: Dictionary = {
	"assets": {},
	"folders": {},
	"settings": {}
}

var all_known_tags: Array[String] = []
var current_selected_path: String = ""

var _current_asset_type: AssetType = AssetType.UNKNOWN
var _loaded_3d_node: Node3D = null
var _current_filter_folder: String = ""
var _active_filter_tags: Array[String] = []
var _is_dragging_3d: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _thumbnail_cache: Dictionary = {}
var _tag_to_delete: String = ""
var _grid_population_version: int = 0
var _current_page: int = 0
var _items_per_page: int = 100
var _search_query: String = ""
var _tag_display_limit: int = 20

var folders_root: TreeItem
var tags_root: TreeItem

@onready var scan_button: Button = $MarginContainer/MainSplit/Sidebar/ScanButton
@onready var settings_button: Button = $MarginContainer/MainSplit/Sidebar/SettingsButton
@onready var nav_tree: Tree = $MarginContainer/MainSplit/Sidebar/NavigationTree
@onready var search_input: LineEdit = $MarginContainer/MainSplit/ContentSplit/CenterPanel/SearchInput
@onready var asset_grid: ItemList = $MarginContainer/MainSplit/ContentSplit/CenterPanel/AssetGrid
@onready var prev_page_button: Button = $MarginContainer/MainSplit/ContentSplit/CenterPanel/PaginationContainer/PrevPageButton
@onready var next_page_button: Button = $MarginContainer/MainSplit/ContentSplit/CenterPanel/PaginationContainer/NextPageButton
@onready var page_label: Label = $MarginContainer/MainSplit/ContentSplit/CenterPanel/PaginationContainer/PageLabel
@onready var preview_3d_viewport: SubViewport = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/PreviewContainer/SubViewportContainer/SubViewport
@onready var preview_3d_pivot: Node3D = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/PreviewContainer/SubViewportContainer/SubViewport/ModelPivot
@onready var preview_2d_rect: TextureRect = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/PreviewContainer/TextureRect
@onready var file_name_label: Label = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/DetailsPanel/FileNameLabel
@onready var replay_button: Button = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/DetailsPanel/ActionButtons/ReplayButton
@onready var open_external_button: Button = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/DetailsPanel/ActionButtons/OpenExternalButton
@onready var open_location_button: Button = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/DetailsPanel/ActionButtons/OpenLocationButton
@onready var send_to_project_button: Button = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/DetailsPanel/ActionButtons/SendToProjectButton
@onready var tag_input_field: LineEdit = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/DetailsPanel/TagInputField
@onready var tag_flow_container: HFlowContainer = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/DetailsPanel/CurrentTagsScroll/TagFlowContainer
@onready var available_tags_flow_container: HFlowContainer = $MarginContainer/MainSplit/ContentSplit/PreviewPanel/DetailsPanel/AvailableTagsScroll/AvailableTagsFlowContainer
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var folder_dialog: FileDialog = $FolderDialog
@onready var settings_dialog: SettingsManager = $SettingsDialog
@onready var tag_context_menu: PopupMenu = $TagContextMenu

func _ready() -> void:
	preview_2d_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	asset_grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	scan_button.pressed.connect(_on_scan_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	folder_dialog.dir_selected.connect(_on_folder_selected)
	nav_tree.item_selected.connect(_on_nav_tree_item_selected)
	nav_tree.item_edited.connect(_on_nav_tree_item_edited)
	nav_tree.item_mouse_selected.connect(_on_nav_tree_item_mouse_selected)
	search_input.text_changed.connect(_on_search_text_changed)
	asset_grid.multi_selected.connect(_on_asset_grid_multi_selected)
	asset_grid.item_selected.connect(_on_asset_grid_item_selected)
	prev_page_button.pressed.connect(_on_prev_page_pressed)
	next_page_button.pressed.connect(_on_next_page_pressed)
	tag_input_field.text_changed.connect(_on_tag_input_text_changed)
	tag_input_field.text_submitted.connect(_on_tag_input_submitted)
	replay_button.pressed.connect(_on_replay_button_pressed)
	open_external_button.pressed.connect(_on_open_external_pressed)
	open_location_button.pressed.connect(_on_open_location_pressed)
	send_to_project_button.pressed.connect(_on_send_to_project_pressed)
	preview_3d_viewport.get_parent().gui_input.connect(_on_preview_gui_input)
	tag_context_menu.id_pressed.connect(_on_tag_context_menu_id_pressed)
	audio_player.finished.connect(_on_audio_finished)

	settings_dialog.settings_changed.connect(_on_settings_changed)
	settings_dialog.database_cleared.connect(_on_database_cleared)

	_load_database()
	settings_dialog.setup(db)
	_update_audio_volume()
	_rebuild_nav_tree()

func scan_directory(path: String) -> void:
	if not db["folders"].has(path):
		db["folders"].append(path)

	var dir := DirAccess.open(path)
	if dir:
		_recursive_scan(dir, path, path)
		_save_database()
		_rebuild_nav_tree()
		db_updated.emit()
		_select_folder_in_tree(path)
	else:
		push_error("Failed to open directory: ", path)

func load_asset_preview(file_path: String) -> void:
	current_selected_path = file_path
	_current_asset_type = _determine_asset_type(file_path.get_extension())
	file_name_label.text = file_path.get_file()

	_display_preview()
	_update_tag_ui()

func add_tag_to_selected_assets(tag_text: String) -> void:
	var clean_tag: String = tag_text.strip_edges().to_lower().replace(" ", "_")
	if clean_tag.is_empty():
		return

	var selected_items := asset_grid.get_selected_items()
	if selected_items.is_empty():
		return

	var modified := false
	for idx in selected_items:
		var path: String = asset_grid.get_item_metadata(idx)
		if not db["assets"].has(path):
			db["assets"][path] = {"tags": []}

		var tags: Array = db["assets"][path]["tags"]
		if not tags.has(clean_tag):
			tags.append(clean_tag)
			modified = true

	if modified:
		_save_database()
		call_deferred("_update_tags_tree")
		_update_tag_ui()

func remove_tag_from_selected_assets(tag_text: String) -> void:
	var selected_items := asset_grid.get_selected_items()
	if selected_items.is_empty():
		return

	var modified := false
	for idx in selected_items:
		var path: String = asset_grid.get_item_metadata(idx)
		if db["assets"].has(path):
			var tags: Array = db["assets"][path].get("tags", [])
			if tags.has(tag_text):
				tags.erase(tag_text)
				modified = true

	if modified:
		_save_database()
		call_deferred("_update_tags_tree")
		_update_tag_ui()

func _delete_tag_globally(tag_text: String) -> void:
	var modified := false
	for path: String in db["assets"].keys():
		var tags: Array = db["assets"][path].get("tags", [])
		if tags.has(tag_text):
			tags.erase(tag_text)
			modified = true

	if _active_filter_tags.has(tag_text):
		_active_filter_tags.erase(tag_text)

	if modified:
		_save_database()
		call_deferred("_update_tags_tree")
		_populate_asset_grid()
		_handle_selection_change()
		_update_tag_ui()

func _get_shared_tags() -> Array[String]:
	var selected := asset_grid.get_selected_items()
	if selected.is_empty():
		return []

	var path0: String = asset_grid.get_item_metadata(selected[0])
	if not db["assets"].has(path0):
		return []

	var shared_tags: Array = db["assets"][path0].get("tags", []).duplicate()

	for i in range(1, selected.size()):
		var path: String = asset_grid.get_item_metadata(selected[i])
		if db["assets"].has(path):
			var current_tags: Array = db["assets"][path].get("tags", [])
			var intersection: Array = []
			for tag in shared_tags:
				if current_tags.has(tag):
					intersection.append(tag)
			shared_tags = intersection
		else:
			return []

	var result: Array[String] = []
	result.assign(shared_tags)
	return result

func _get_thumbnail(path: String, type: AssetType) -> Texture2D:
	if _thumbnail_cache.has(path):
		return _thumbnail_cache[path]

	if type == AssetType.IMAGE_2D:
		var img := Image.load_from_file(path)
		if img:
			var size := img.get_size()
			var max_dim := maxf(size.x, size.y)
			if max_dim > 64:
				var scale := 64.0 / max_dim
				img.resize(int(size.x * scale), int(size.y * scale), Image.INTERPOLATE_NEAREST)
			var tex := ImageTexture.create_from_image(img)
			_thumbnail_cache[path] = tex
			return tex
	return null

func _recursive_scan(dir: DirAccess, current_path: String, root_path: String) -> void:
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				var next_dir_path := current_path + "/" + file_name
				var next_dir := DirAccess.open(next_dir_path)
				if next_dir:
					_recursive_scan(next_dir, next_dir_path, root_path)
		else:
			var ext := file_name.get_extension().to_lower()
			var full_path := current_path + "/" + file_name
			var type := _determine_asset_type(ext)

			if type != AssetType.UNKNOWN:
				if not db["assets"].has(full_path):
					var base_tag := _get_type_tag(type)
					var initial_tags: Array[String] = []
					initial_tags.append(base_tag)

					var root_folder_name := root_path.get_file().strip_edges().to_lower().replace(" ", "_")
					if not root_folder_name.is_empty() and not initial_tags.has(root_folder_name):
						initial_tags.append(root_folder_name)

					var relative_dir := current_path.trim_prefix(root_path)
					if relative_dir.begins_with("/"):
						relative_dir = relative_dir.substr(1)

					if not relative_dir.is_empty():
						var folder_parts := relative_dir.split("/")
						for part in folder_parts:
							var clean_part := part.strip_edges().to_lower().replace(" ", "_")
							if not clean_part.is_empty() and not initial_tags.has(clean_part):
								initial_tags.append(clean_part)

					db["assets"][full_path] = {
						"tags": initial_tags,
						"type": type
					}
		file_name = dir.get_next()
	dir.list_dir_end()

func _determine_asset_type(extension: String) -> AssetType:
	var ext: String = extension.to_lower()
	var active_formats: Array = db["settings"].get("active_formats", [])

	if not active_formats.has(ext):
		return AssetType.UNKNOWN

	if ext in ALL_3D_FORMATS:
		return AssetType.MODEL_3D
	elif ext in ALL_2D_FORMATS:
		return AssetType.IMAGE_2D
	elif ext in ALL_AUDIO_FORMATS:
		return AssetType.AUDIO

	return AssetType.UNKNOWN

func _get_type_tag(type: AssetType) -> String:
	match type:
		AssetType.MODEL_3D: return "3d_model"
		AssetType.IMAGE_2D: return "2d_image"
		AssetType.AUDIO: return "audio"
		AssetType.SHADER: return "shader"
		_: return "unknown"

func _load_database() -> void:
	if FileAccess.file_exists(DB_FILE_PATH):
		var file := FileAccess.open(DB_FILE_PATH, FileAccess.READ)
		var json_string := file.get_as_text()
		var parsed: Variant = JSON.parse_string(json_string)
		if parsed and parsed is Dictionary:
			if parsed.has("assets"): db["assets"] = parsed["assets"]
			if parsed.has("folders"): db["folders"] = parsed["folders"]
			if parsed.has("settings"): db["settings"] = parsed["settings"]

func _save_database() -> void:
	var file := FileAccess.open(DB_FILE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(db, "\t"))

func _rebuild_nav_tree() -> void:
	nav_tree.clear()
	var root := nav_tree.create_item()

	folders_root = nav_tree.create_item(root)
	folders_root.set_text(0, "Scanned Folders")
	for folder: String in db["folders"]:
		var f_item := nav_tree.create_item(folders_root)
		f_item.set_text(0, folder.get_file())
		f_item.set_metadata(0, {"type": "folder", "path": folder})

	tags_root = nav_tree.create_item(root)
	tags_root.set_text(0, "Tags")

	_update_tags_tree()

func _update_tags_tree() -> void:
	if not is_instance_valid(tags_root):
		return

	var child := tags_root.get_first_child()
	while child:
		var next := child.get_next()
		child.free()
		child = next

	all_known_tags.clear()
	var tag_counts := {}

	for path: String in db["assets"].keys():
		var data: Dictionary = db["assets"][path]
		var should_add := true

		if not _current_filter_folder.is_empty() and not path.begins_with(_current_filter_folder):
			should_add = false

		if should_add and not _active_filter_tags.is_empty():
			var asset_tags: Array = data.get("tags", [])
			for t in _active_filter_tags:
				if not asset_tags.has(t):
					should_add = false
					break

		if should_add:
			var asset_tags: Array = data.get("tags", [])
			for tag: String in asset_tags:
				tag_counts[tag] = tag_counts.get(tag, 0) + 1

	for asset_data: Dictionary in db["assets"].values():
		for tag: String in asset_data.get("tags", []):
			if not all_known_tags.has(tag):
				all_known_tags.append(tag)

	var display_tags: Array[String] = []
	for tag in tag_counts.keys():
		display_tags.append(tag)

	for active_tag in _active_filter_tags:
		if not display_tags.has(active_tag):
			display_tags.append(active_tag)
			tag_counts[active_tag] = 0

	var unselected_tags: Array[String] = []
	for tag in display_tags:
		if not _active_filter_tags.has(tag):
			unselected_tags.append(tag)

	unselected_tags.sort_custom(func(a: String, b: String) -> bool:
		if tag_counts.get(a, 0) == tag_counts.get(b, 0):
			return a < b
		return tag_counts.get(a, 0) > tag_counts.get(b, 0)
	)

	var final_ordered_tags: Array[String] = []
	final_ordered_tags.append_array(_active_filter_tags)
	final_ordered_tags.append_array(unselected_tags)

	var count := 0
	for tag in final_ordered_tags:
		if count >= _tag_display_limit:
			var more_item := nav_tree.create_item(tags_root)
			more_item.set_text(0, "Load More (+20)...")
			more_item.set_metadata(0, {"type": "load_more"})
			break

		var t_item := nav_tree.create_item(tags_root)
		t_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		var t_count: int = tag_counts.get(tag, 0)
		t_item.set_text(0, "#" + tag + " (" + str(t_count) + ")")
		t_item.set_editable(0, true)
		t_item.set_checked(0, _active_filter_tags.has(tag))
		t_item.set_metadata(0, {"type": "tag", "value": tag})

		count += 1

func _update_audio_volume() -> void:
	var val: float = db["settings"].get("volume", 50.0)
	if val <= 0:
		audio_player.volume_db = -80.0
	else:
		audio_player.volume_db = linear_to_db(val / 100.0)

func _select_folder_in_tree(folder_path: String) -> void:
	var root := nav_tree.get_root()
	if not root or root.get_child_count() == 0:
		return

	var target_root := root.get_child(0)
	for i in range(target_root.get_child_count()):
		var item := target_root.get_child(i)
		var meta: Variant = item.get_metadata(0)
		if meta and meta is Dictionary and meta.get("path") == folder_path:
			item.select(0)
			nav_tree.scroll_to_item(item)
			return

func _populate_asset_grid() -> void:
	asset_grid.clear()
	_grid_population_version += 1
	var current_version := _grid_population_version

	var matching_paths: Array[String] = []

	for path: String in db["assets"].keys():
		var data: Dictionary = db["assets"][path]
		var should_add := true

		if not _current_filter_folder.is_empty() and not path.begins_with(_current_filter_folder):
			should_add = false

		if should_add and not _active_filter_tags.is_empty():
			var asset_tags: Array = data.get("tags", [])
			for t in _active_filter_tags:
				if not asset_tags.has(t):
					should_add = false
					break

		if should_add and not _search_query.is_empty():
			var filename := path.get_file()
			if not _search_query.is_subsequence_ofn(filename):
				should_add = false

		if should_add:
			matching_paths.append(path)

	if not _search_query.is_empty():
		matching_paths.sort_custom(func(a: String, b: String) -> bool:
			var file_a := a.get_file()
			var file_b := b.get_file()
			var exact_a := file_a.findn(_search_query) != -1
			var exact_b := file_b.findn(_search_query) != -1

			if exact_a != exact_b:
				return exact_a
			return file_a.nocasecmp_to(file_b) < 0
		)
	else:
		matching_paths.sort_custom(func(a: String, b: String) -> bool:
			return a.get_file().nocasecmp_to(b.get_file()) < 0
		)

	var total_pages: int = maxi(1, ceili(matching_paths.size() / float(_items_per_page)))
	_current_page = clampi(_current_page, 0, total_pages - 1)

	page_label.text = "Page " + str(_current_page + 1) + " of " + str(total_pages)
	prev_page_button.disabled = _current_page == 0
	next_page_button.disabled = _current_page >= total_pages - 1

	var start_idx: int = _current_page * _items_per_page
	var end_idx: int = mini(start_idx + _items_per_page, matching_paths.size())

	var items_added := 0
	for i in range(start_idx, end_idx):
		if current_version != _grid_population_version:
			return

		var path := matching_paths[i]
		var asset_type: int = db["assets"][path].get("type", AssetType.UNKNOWN)
		var thumb := _get_thumbnail(path, asset_type)

		var idx := asset_grid.add_item(path.get_file(), thumb)
		asset_grid.set_item_metadata(idx, path)
		asset_grid.set_item_tooltip(idx, path)

		items_added += 1
		if items_added % 200 == 0:
			await get_tree().process_frame

func _handle_selection_change() -> void:
	var selected := asset_grid.get_selected_items()

	var has_selection := selected.size() > 0
	var is_single := selected.size() == 1
	open_location_button.disabled = not has_selection
	send_to_project_button.disabled = not has_selection
	open_external_button.disabled = not is_single

	if selected.size() == 0:
		current_selected_path = ""
		file_name_label.text = "No asset selected"
		_clear_current_preview()
		tag_input_field.editable = false
		_update_tag_ui()

	elif selected.size() == 1:
		var path: String = asset_grid.get_item_metadata(selected[0])
		tag_input_field.editable = true
		load_asset_preview(path)

	else:
		current_selected_path = ""
		file_name_label.text = str(selected.size()) + " assets selected"
		_clear_current_preview()
		preview_2d_rect.visible = false
		preview_3d_viewport.get_parent().visible = false
		replay_button.visible = false
		tag_input_field.editable = true
		_update_tag_ui()

func _display_preview() -> void:
	preview_3d_viewport.get_parent().visible = _current_asset_type == AssetType.MODEL_3D
	preview_2d_rect.visible = _current_asset_type == AssetType.IMAGE_2D
	replay_button.visible = _current_asset_type == AssetType.AUDIO

	_clear_current_preview()

	if _current_asset_type == AssetType.MODEL_3D:
		_load_3d_model(current_selected_path)
	elif _current_asset_type == AssetType.IMAGE_2D:
		var img: Image = Image.load_from_file(current_selected_path)
		if img:
			preview_2d_rect.texture = ImageTexture.create_from_image(img)
	elif _current_asset_type == AssetType.AUDIO:
		_load_audio(current_selected_path)

func _clear_current_preview() -> void:
	preview_2d_rect.texture = null
	audio_player.stop()
	audio_player.stream = null
	replay_button.text = "Replay"
	preview_3d_pivot.rotation = Vector3.ZERO

	if is_instance_valid(_loaded_3d_node):
		_loaded_3d_node.queue_free()
		_loaded_3d_node = null

func _load_3d_model(path: String) -> void:
	var ext := path.get_extension().to_lower()
	var state := GLTFState.new()
	var err: int = FAILED

	if ext == "fbx":
		var fbx := FBXDocument.new()
		err = fbx.append_from_file(path, state)
		if err == OK:
			_loaded_3d_node = fbx.generate_scene(state)
	else:
		var gltf := GLTFDocument.new()
		err = gltf.append_from_file(path, state)
		if err == OK:
			_loaded_3d_node = gltf.generate_scene(state)

	if err == OK and _loaded_3d_node:
		preview_3d_pivot.add_child(_loaded_3d_node)
		_center_and_scale_3d_model(_loaded_3d_node)
	else:
		file_name_label.text += " (Failed to Parse FBX)"

func _center_and_scale_3d_model(node: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_find_meshes_recursive(node, meshes)

	if meshes.is_empty():
		return

	var aabb: AABB = meshes[0].get_aabb()
	aabb.position += meshes[0].global_position

	for i in range(1, meshes.size()):
		var mesh_aabb := meshes[i].get_aabb()
		mesh_aabb.position += meshes[i].global_position
		aabb = aabb.merge(mesh_aabb)

	var max_size: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	if max_size > 0:
		var target_scale: float = 2.0 / max_size
		node.scale = Vector3(target_scale, target_scale, target_scale)

	var center_offset: Vector3 = aabb.get_center() * node.scale
	node.position = -center_offset

func _find_meshes_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_meshes_recursive(child, result)

func _load_audio(path: String) -> void:
	var ext := path.get_extension().to_lower()

	if ext == "wav":
		audio_player.stream = _load_wav_from_file(path)
		if audio_player.stream:
			audio_player.play()
			replay_button.text = "Stop"
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return

	var buffer := file.get_buffer(file.get_length())

	if ext == "ogg":
		var stream := AudioStreamOggVorbis.load_from_buffer(buffer)
		audio_player.stream = stream
		audio_player.play()
		replay_button.text = "Stop"
	elif ext == "mp3":
		var stream := AudioStreamMP3.new()
		stream.data = buffer
		audio_player.stream = stream
		audio_player.play()
		replay_button.text = "Stop"

func _load_wav_from_file(path: String) -> AudioStreamWAV:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return null

	var stream := AudioStreamWAV.new()

	var riff := file.get_buffer(4).get_string_from_ascii()
	if riff != "RIFF": return null

	file.get_32()

	var wave := file.get_buffer(4).get_string_from_ascii()
	if wave != "WAVE": return null

	var format_found := false
	var data_found := false

	var format_tag: int = 0
	var bits_per_sample: int = 0
	var sample_rate: int = 0
	var channels: int = 0

	while file.get_position() < file.get_length() and not data_found:
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		if chunk_id.length() < 4:
			break

		var chunk_size := file.get_32()
		var next_chunk_pos := file.get_position() + chunk_size + (chunk_size % 2)

		if chunk_id == "fmt ":
			format_tag = file.get_16()
			channels = file.get_16()
			sample_rate = file.get_32()
			file.get_32()
			file.get_16()
			bits_per_sample = file.get_16()

			stream.mix_rate = sample_rate
			stream.stereo = (channels == 2)

			if format_tag == 1:
				if bits_per_sample == 8:
					stream.format = AudioStreamWAV.FORMAT_8_BITS
				elif bits_per_sample == 16 or bits_per_sample == 24:
					stream.format = AudioStreamWAV.FORMAT_16_BITS
				else:
					push_error("Unsupported WAV bit depth: ", bits_per_sample, " in ", path)
					return null
			elif format_tag == 3 and bits_per_sample == 32:
				stream.format = AudioStreamWAV.FORMAT_16_BITS
			else:
				push_error("Unsupported WAV format tag: ", format_tag, " in ", path)
				return null

			format_found = true

		elif chunk_id == "data":
			var bytes_per_sec: int = sample_rate * channels * (bits_per_sample / 8)
			var max_preview_bytes: int = bytes_per_sec * 10
			var bytes_to_read: int = mini(chunk_size, max_preview_bytes)

			var raw_data := file.get_buffer(bytes_to_read)
			if format_tag == 1 and bits_per_sample == 24:
				stream.data = _convert_24bit_to_16bit(raw_data)
			elif format_tag == 3 and bits_per_sample == 32:
				stream.data = _convert_32bit_float_to_16bit(raw_data)
			else:
				stream.data = raw_data
			data_found = true

		file.seek(next_chunk_pos)

	if not format_found or not data_found:
		push_error("Could not find valid fmt/data chunks in WAV: ", path)
		return null

	return stream

func _convert_24bit_to_16bit(data24: PackedByteArray) -> PackedByteArray:
	var num_samples: int = data24.size() / 3
	var data16 := PackedByteArray()
	data16.resize(num_samples * 2)
	var j: int = 0
	for i in range(0, num_samples * 3, 3):
		data16[j] = data24[i + 1]
		data16[j + 1] = data24[i + 2]
		j += 2
	return data16

func _convert_32bit_float_to_16bit(data32: PackedByteArray) -> PackedByteArray:
	var num_samples: int = data32.size() / 4
	var data16 := PackedByteArray()
	data16.resize(num_samples * 2)
	var j: int = 0
	var offset: int = 0
	for i in range(num_samples):
		var f: float = data32.decode_float(offset)
		offset += 4
		var int_val: int = int(clampf(f, -1.0, 1.0) * 32767.0)
		data16[j] = int_val & 0xFF
		data16[j + 1] = (int_val >> 8) & 0xFF
		j += 2
	return data16

func _update_tag_ui() -> void:
	for child in tag_flow_container.get_children():
		child.queue_free()
	for child in available_tags_flow_container.get_children():
		child.queue_free()

	var selected_items := asset_grid.get_selected_items()
	if selected_items.is_empty():
		return

	var shared_tags: Array[String] = _get_shared_tags()

	for tag in shared_tags:
		var btn := Button.new()
		btn.text = tag + " (x)"
		var captured_tag := tag
		btn.pressed.connect(func() -> void: remove_tag_from_selected_assets(captured_tag))
		tag_flow_container.add_child(btn)

	var search_text := tag_input_field.text.strip_edges().to_lower().replace(" ", "_")
	var available_tags: Array[String] = []

	for tag in all_known_tags:
		if not shared_tags.has(tag):
			if search_text.is_empty() or search_text.is_subsequence_ofn(tag):
				available_tags.append(tag)

	if not search_text.is_empty():
		available_tags.sort_custom(func(a: String, b: String) -> bool:
			var exact_a := a.findn(search_text) != -1
			var exact_b := b.findn(search_text) != -1
			if exact_a != exact_b:
				return exact_a
			return a.nocasecmp_to(b) < 0
		)

	for tag in available_tags:
		var btn := Button.new()
		btn.text = tag + " (+)"
		var captured_tag := tag
		btn.pressed.connect(func() -> void: add_tag_to_selected_assets(captured_tag))
		available_tags_flow_container.add_child(btn)

func _export_selected_to_project() -> void:
	var selected_items := asset_grid.get_selected_items()
	var export_count := 0

	for idx in selected_items:
		var path: String = asset_grid.get_item_metadata(idx)
		if db["assets"].has(path):
			var asset_type: int = db["assets"][path].get("type", AssetType.UNKNOWN)
			var dest_dir := "res://assets/misc"

			match asset_type:
				AssetType.MODEL_3D: dest_dir = db["settings"].get("import_path_3d", "res://assets/models")
				AssetType.IMAGE_2D: dest_dir = db["settings"].get("import_path_2d", "res://assets/images")
				AssetType.AUDIO: dest_dir = db["settings"].get("import_path_audio", "res://assets/audio")
				AssetType.SHADER: dest_dir = db["settings"].get("import_path_shader", "res://assets/shaders")

			if not DirAccess.dir_exists_absolute(dest_dir):
				DirAccess.make_dir_recursive_absolute(dest_dir)

			var dest_path := dest_dir + "/" + path.get_file()
			var err := DirAccess.copy_absolute(path, dest_path)
			if err == OK:
				export_count += 1
			else:
				push_error("Failed to copy file: ", path)

	if export_count > 0:
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
		var original_text := send_to_project_button.text
		send_to_project_button.text = "Exported " + str(export_count) + " file(s)!"
		get_tree().create_timer(2.0).timeout.connect(func() -> void: send_to_project_button.text = original_text)

func _on_scan_button_pressed() -> void:
	folder_dialog.popup_centered()

func _on_settings_button_pressed() -> void:
	settings_dialog.popup_centered()

func _on_folder_selected(path: String) -> void:
	scan_directory(path)

func _on_search_text_changed(new_text: String) -> void:
	_search_query = new_text
	_current_page = 0
	_populate_asset_grid()
	_handle_selection_change()

func _on_prev_page_pressed() -> void:
	_current_page -= 1
	_populate_asset_grid()
	_handle_selection_change()

func _on_next_page_pressed() -> void:
	_current_page += 1
	_populate_asset_grid()
	_handle_selection_change()

func _on_nav_tree_item_selected() -> void:
	var selected := nav_tree.get_selected()
	if not selected:
		return

	var meta: Variant = selected.get_metadata(0)
	if meta and meta is Dictionary:
		if meta.get("type") == "folder":
			_current_filter_folder = meta.get("path", "")
			_current_page = 0
			_tag_display_limit = 20
			_populate_asset_grid()
			_handle_selection_change()
			call_deferred("_update_tags_tree")
		elif meta.get("type") == "load_more":
			_tag_display_limit += 20
			selected.deselect(0)
			call_deferred("_update_tags_tree")
		elif meta.get("type") == "tag":
			selected.deselect(0)
	else:
		_current_filter_folder = ""
		_current_page = 0
		_tag_display_limit = 20
		_populate_asset_grid()
		_handle_selection_change()
		call_deferred("_update_tags_tree")

func _on_nav_tree_item_edited() -> void:
	var item := nav_tree.get_edited()
	var meta: Variant = item.get_metadata(0)
	if meta and meta is Dictionary and meta.get("type") == "tag":
		var tag_val: String = meta.get("value", "")
		var is_checked: bool = item.is_checked(0)
		if is_checked and not _active_filter_tags.has(tag_val):
			_active_filter_tags.append(tag_val)
		elif not is_checked and _active_filter_tags.has(tag_val):
			_active_filter_tags.erase(tag_val)

		_current_page = 0
		_populate_asset_grid()
		_handle_selection_change()
		call_deferred("_update_tags_tree")

func _on_nav_tree_item_mouse_selected(position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_RIGHT:
		var item := nav_tree.get_item_at_position(position)
		if item:
			var meta: Variant = item.get_metadata(0)
			if meta and meta is Dictionary and meta.get("type") == "tag":
				_tag_to_delete = meta.get("value", "")
				tag_context_menu.position = Vector2i(get_global_mouse_position())
				tag_context_menu.popup()

func _on_tag_context_menu_id_pressed(id: int) -> void:
	if id == 0 and not _tag_to_delete.is_empty():
		_delete_tag_globally(_tag_to_delete)

func _on_asset_grid_multi_selected(_index: int, _selected: bool) -> void:
	_handle_selection_change()

func _on_asset_grid_item_selected(_index: int) -> void:
	_handle_selection_change()

func _on_tag_input_text_changed(_new_text: String) -> void:
	_update_tag_ui()

func _on_tag_input_submitted(new_text: String) -> void:
	tag_input_field.clear()
	add_tag_to_selected_assets(new_text)
	_update_tag_ui()

func _on_replay_button_pressed() -> void:
	if audio_player.playing:
		audio_player.stop()
		replay_button.text = "Replay"
	elif audio_player.stream:
		audio_player.play()
		replay_button.text = "Stop"

func _on_audio_finished() -> void:
	replay_button.text = "Replay"

func _on_open_external_pressed() -> void:
	if not current_selected_path.is_empty():
		OS.shell_open(current_selected_path)

func _on_open_location_pressed() -> void:
	var selected_items := asset_grid.get_selected_items()
	for idx in selected_items:
		var path: String = asset_grid.get_item_metadata(idx)
		OS.shell_show_in_file_manager(path)

func _on_send_to_project_pressed() -> void:
	_export_selected_to_project()

func _on_preview_gui_input(event: InputEvent) -> void:
	if _current_asset_type != AssetType.MODEL_3D:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging_3d = true
				_last_mouse_pos = event.position
			else:
				_is_dragging_3d = false

	elif event is InputEventMouseMotion and _is_dragging_3d:
		var motion := event as InputEventMouseMotion
		var delta: Vector2 = motion.position - _last_mouse_pos
		_last_mouse_pos = motion.position

		preview_3d_pivot.rotate_y(-delta.x * 0.01)

		preview_3d_pivot.rotation.x += -delta.y * 0.01
		preview_3d_pivot.rotation.x = clampf(preview_3d_pivot.rotation.x, -PI / 2.5, PI / 2.5)

func _on_settings_changed() -> void:
	_update_audio_volume()
	_populate_asset_grid()

func _on_database_cleared() -> void:
	db["assets"].clear()
	db["folders"].clear()
	_save_database()

	all_known_tags.clear()
	_active_filter_tags.clear()
	_current_filter_folder = ""
	_search_query = ""
	search_input.clear()

	_rebuild_nav_tree()
	_populate_asset_grid()
	_handle_selection_change()
