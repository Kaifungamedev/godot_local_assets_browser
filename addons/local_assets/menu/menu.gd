@tool
extends Control
@onready var Files: FileDialog = $FileDialog
@onready var asset_path: LineEdit = %AssetsPath
@onready var grid: GridContainer = %GridContainer
@onready var thread1: Thread = Thread.new()
var settings = EditorInterface.get_editor_settings()
var items: Array[Dictionary]


# Called when the node enters the scene tree for the first time.
func _ready():
	$VBoxContainer/TopBar/path/OpenDir.icon = EditorInterface.get_editor_theme().get_icon("Folder", "EditorIcons")
	if settings.has_setting("Local_Assets/asset_dir"):
		asset_path.text = settings.get_setting("Local_Assets/asset_dir")
		asset_path.text_changed.emit(asset_path.text)


func _exit_tree():
	if thread1.is_started():
		thread1.wait_to_finish()


func _on_open_dir_pressed():
	Files.show()
	var f = await Files.dir_selected
	asset_path.text = f
	_on_assets_path_text_changed(f)


func _on_assets_path_text_changed(new_text: String):
	save()
	for child in grid.get_children():
		child.queue_free()
	get_assets(new_text)


func search(s: String):
	print(s)
	if s == "" or s == null:
		for c: Control in grid.get_children():
			c.visible = true
	else:
		for c: Control in grid.get_children():
			prints(c.name, c.name.contains(s))
			if !c.name.to_lower().contains(s.to_lower()):
				c.visible = false


func save():
	settings.set_setting("Local_Assets/asset_dir", asset_path.text)

	var property_info = {
		"name": "Local_Assets/asset_dir", "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM_SUGGESTION, "hint_string": "Path to the dictionary where the assets are stored"
	}
	settings.add_property_info(property_info)


func get_assets(Path: String):
	$VBoxContainer/Panel/Label.visible = true
	thread1.start(find_files_recursive.bind(Path, "Preview.png"))
	while thread1.is_alive():
		await get_tree().process_frame
	var assets = await thread1.wait_to_finish()
	prints("Found", assets.size(), "assets.")
	assets.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	items = assets
	#prints("items", items)
	$VBoxContainer/Panel/Label.visible = false
	add_items(assets)


func add_items(_items: Array[Dictionary]):
	for i in _items:
		var item = load("res://addons/local_assets/Components/Item.tscn").instantiate()
		if item != null:
			item.asset_icon = ImageTexture.create_from_image(Image.load_from_file(i.image_path))
			item.asset_name = i.name
			item.asset_path = i.path
			item.root = self
			item.update()
			grid.add_child(item)
			item.name = i.name
	prints(grid.get_child_count())


func find_files_recursive(folder_path: String, file_name: String) -> Array[Dictionary]:
	var dir = DirAccess.open(folder_path)
	var found_files: Array[Dictionary] = []
	if dir:
		dir.list_dir_begin()  # Skip hidden files and include navigational markers (., ..)
		while true:
			var file_or_dir = dir.get_next()
			if file_or_dir == "":
				break

			var path = (folder_path + "/" + file_or_dir).replace("//", "/")
			if dir.current_is_dir():
				found_files += find_files_recursive(path, file_name)
			else:
				if file_or_dir == file_name:
					var ana: Array = path.get_base_dir().split("/")
					var an = ana[ana.size() - 1]
					found_files.append({"image_path": path, "name": an, "path": path.get_base_dir()})
		dir.list_dir_end()
	return found_files


func copy_files_recursive(src_path: String, dst_path: String) -> void:
	var src_dir = DirAccess.open(src_path)
	var dst_dir: DirAccess = DirAccess.open("res://")

	if src_dir.get_open_error() == OK:
		# Ensure destination directory exists
		if !dst_dir.dir_exists(dst_path):
			dst_dir.make_dir_recursive(dst_path)

		src_dir.list_dir_begin()  # Skip hidden files and include navigational markers (., ..)
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
