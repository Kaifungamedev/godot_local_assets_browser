@tool
class_name Local_Assets extends Control
@onready var Files: FileDialog = $FileDialog
@onready var assetPath: LineEdit = %AssetsPath
@onready var grid: GridContainer = %GridContainer
@onready var backgroundText = %BackgroundText
@onready var thread1: Thread = Thread.new()
var editorSettings: EditorSettings = EditorInterface.get_editor_settings()
var items: Array[Dictionary]
var file_names: PackedStringArray
var useFirstImage: bool
var useUniformImageSize: bool
var uniformImageSize: Vector2i
const fileExtentions = ["png", "jpeg", "jpg", "bmp", "tga", "webp", "svg"]


func _ready():
	editorSettings.settings_changed.connect(_eSettings_changed)
	$VBoxContainer/TopBar/path/OpenDir.icon = EditorInterface.get_editor_theme().get_icon("Folder", "EditorIcons")
	set_up_settings()
	_eSettings_changed()


func _eSettings_changed():
	if editorSettings.has_setting("Local_Assets/asset_dir"):
		assetPath.text = editorSettings.get_setting("Local_Assets/asset_dir")
		assetPath.text_changed.emit(assetPath.text)
	if editorSettings.has_setting("Local_Assets/asset_dir"):
		file_names = editorSettings.get_setting("Local_Assets/File_preview_names")
	if editorSettings.has_setting("Local_Assets/use_first_image_found"):
		useFirstImage = editorSettings.get_setting("Local_Assets/use_first_image_found")
	if editorSettings.has_setting("Local_Assets/use_uniform_image_size"):
		useUniformImageSize = editorSettings.get_setting("Local_Assets/use_uniform_image_size")
	if editorSettings.has_setting("Local_Assets/uniform_image_size"):
		uniformImageSize = editorSettings.get_setting("Local_Assets/uniform_image_size")


func set_up_settings():
	if !editorSettings.has_setting("Local_Assets/asset_dir"):
		set_editor_setting("Local_Assets/asset_dir", "", TYPE_STRING)
	if !editorSettings.has_setting("Local_Assets/File_preview_names"):
		set_editor_setting("Local_Assets/File_preview_names", PackedStringArray(["Preview", "Asset"]), TYPE_PACKED_STRING_ARRAY)
	if !editorSettings.has_setting("Local_Assets/use_first_image_found"):
		set_editor_setting("Local_Assets/use_first_image_found", false, TYPE_BOOL)
	if !editorSettings.has_setting("Local_Assets/use_uniform_image_size"):
		set_editor_setting("Local_Assets/use_uniform_image_size", false, TYPE_BOOL)
	if !editorSettings.has_setting("Local_Assets/uniform_image_size"):
		set_editor_setting("Local_Assets/uniform_image_size", Vector2i(918, 515), TYPE_VECTOR2I)


func set_editor_setting(s_name: String, value: Variant, type: Variant.Type):
	editorSettings.set_setting(s_name, value)
	editorSettings.add_property_info({"name": s_name, "type": type})


func _exit_tree():
	if thread1.is_started():
		await thread1.wait_to_finish()


func _on_open_dir_pressed():
	Files.show()
	var f = await Files.dir_selected
	assetPath.text = f
	_on_assets_path_text_changed(f)


func _on_assets_path_text_changed(new_text: String):
	for child in grid.get_children():
		child.queue_free()
	get_assets(new_text)


func search(search_string: String):
	backgroundText.hide()

	for c: Control in grid.get_children():
		c.show()
	if search_string.is_empty():
		return

	var found: bool = false
	search_string = search_string.to_lower()
	var tag_search_term: String = ""
	var tag_search_pattern = "tag:"
	var search_terms: Array = search_string.split(" ") as Array

	for term in search_terms:
		if term.begins_with(tag_search_pattern):
			tag_search_term = term.substr(tag_search_pattern.length())
			search_terms.erase(term)
			break
	var name_search_string: String
	for i: String in search_terms:
		name_search_string += i + " "
	name_search_string = name_search_string.strip_edges()

	for node: LocalAssetsItem in grid.get_children():
		var name_found = false
		var tag_found = false
		if tag_search_term != "":
			for tag in node.tags:
				if tag.to_lower() == tag_search_term:
					tag_found = true
					break
		if name_search_string != "":
			if node.asset_name.to_lower().find(name_search_string) != -1:
				name_found = true
		if (tag_search_term != "" and name_found and tag_found) or (tag_search_term == "" and name_found):
			node.visible = true
			found = true
		else:
			node.visible = false

	if !found:
		backgroundText.text = "Not Found"
		backgroundText.show()


func save():
	set_editor_setting("Local_Assets/asset_dir", assetPath.text, TYPE_STRING)


func clear_items():
	for c: Control in grid.get_children():
		c.queue_free()


func get_assets(Path: String):
	backgroundText.text = "Loading"
	grid.hide()
	backgroundText.show()
	if thread1.is_started():
		await _wait_for_thread_non_blocking(thread1)
	thread1.start(find_files_recursive.bind(Path))
	var assets = await _wait_for_thread_non_blocking(thread1)
	if typeof(assets) == TYPE_ARRAY:
		if assets.is_empty():
			backgroundText.text = "No assets found."
			return
		assets.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
		items = assets
		if thread1.is_started():
			await _wait_for_thread_non_blocking(thread1)
		thread1.start(add_items.bind(items))
		await _wait_for_thread_non_blocking(thread1)
		prints("Found", assets.size(), "assets.")
		save()
		backgroundText.hide()
		grid.show()
		await _wait_for_thread_non_blocking(thread1)


func _wait_for_thread_non_blocking(thread: Thread) -> Variant:
	while thread.is_alive():
		await get_tree().process_frame
	if thread.is_started():
		return await thread.wait_to_finish()
	else:
		return FAILED


func add_items(_items: Array[Dictionary]):
	for i: Dictionary in _items:
		var item: LocalAssetsItem = load("res://addons/local_assets/Components/Item/Item.tscn").instantiate()
		if item != null:
			item.root = self
			if i.has("image_path"):
				item.asset_icon = Image.load_from_file(i.image_path)
			item.tags = i.get("tags", [])
			item.asset_name = i.name
			item.asset_path = i.path
			item.update()
			grid.call_deferred_thread_group("add_child", item)


func find_files_recursive(folder_path: String) -> Array[Dictionary]:
	file_names = editorSettings.get_setting("Local_Assets/File_preview_names")
	var dir = DirAccess.open(folder_path)
	var found_files: Array[Dictionary] = []
	if dir:
		var path = dir.get_current_dir(true)
		if dir.file_exists("Asset.json"):
			found_files.append(load(path.path_join("Asset.json")).data)
			return found_files
		for file in file_names:
			for extention in fileExtentions:
				var filename = "%s.%s" % [file, extention]
				var foldername = (dir.get_current_dir().get_base_dir().replace("\\", "/").split("/") as Array).back()
				var folderfilename = "%s.%s" % [foldername, extention]
				if dir.file_exists(filename):
					var ana: Array = path.split("/")
					var a_name = ana.back()
					found_files.append({"image_path": path.path_join(filename), "name": a_name, "path": path})
					return found_files
				if dir.file_exists(folderfilename):
					print("filefonder name")
					var ana: Array = path.split("/")
					var a_name = ana.back()
					found_files.append({"image_path": path.path_join(folderfilename), "name": a_name, "path": path})
					return found_files
		if useFirstImage:
			for file in dir.get_files():
				if file.get_extension() in fileExtentions:
					var ana: Array = path.split("/")
					var a_name = ana.back()
					found_files.append({"image_path": path.path_join(file), "name": a_name, "path": path})
					return found_files
		for folder in dir.get_directories():
			found_files.append_array(find_files_recursive(path.path_join(folder)))
	return found_files


func copy_files_recursive(src_path: String, dst_path: String) -> void:
	var src_dir = DirAccess.open(src_path)
	var dst_dir: DirAccess = DirAccess.open("res://")
	if src_dir.get_open_error() == OK:
		if !dst_dir.dir_exists(dst_path):
			dst_dir.make_dir_recursive(dst_path)
		src_dir.list_dir_begin()
		while true:
			var file_or_dir = src_dir.get_next()
			if file_or_dir == "":
				break
			var src_item_path = src_path + "/" + file_or_dir
			var dst_item_path = dst_path + "/" + file_or_dir
			if src_dir.current_is_dir():
				# Recursively copy subdirectory
				copy_files_recursive(src_item_path, dst_item_path)
			else:
				# Copy file
				if FileAccess.file_exists(src_item_path):
					var file_data = FileAccess.get_file_as_bytes(src_item_path)
					var file = FileAccess.open(dst_item_path, FileAccess.WRITE)
					if file.get_error() == OK:
						file.store_buffer(file_data)
						file.close()
					else:
						print("Failed to open destination file for writing: ", dst_item_path)
				else:
					print("Failed to open source file for reading: ", src_item_path)
		src_dir.list_dir_end()
	else:
		print("Failed to open source directory: ", src_path)

	EditorInterface.get_resource_filesystem().scan()
