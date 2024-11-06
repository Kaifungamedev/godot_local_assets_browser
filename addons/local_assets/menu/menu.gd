@tool
class_name LocalAssets extends Control

@onready var Files: FileDialog = $FileDialog
@onready var assetPath: LineEdit = %AssetsPath
@onready var grid: GridContainer = %GridContainer
@onready var backgroundText = %BackgroundText
@onready var thread1: Thread = Thread.new()

var editorSettings: EditorSettings = EditorInterface.get_editor_settings()
var file_names: PackedStringArray
var useFirstImage: bool
var useUniformImageSize: bool
var uniformImageSize: Vector2i
var assetFinder: LocalAssetsAssetFinder
var cache_path = EditorInterface.get_editor_paths().get_cache_dir().path_join("LocalAssets")
var assets_cache_path = cache_path.path_join("assetGroup")
var item = load("res://addons/local_assets/Components/Item/Item.tscn")
const fileExtentions = ["png", "jpeg", "jpg", "bmp", "tga", "webp", "svg"]


## Called when the node is added to the scene.
func _ready():
	# Set up the editor settings and load assets based on the current settings.
	editorSettings.settings_changed.connect(_eSettings_changed)
	$VBoxContainer/TopBar/path/OpenDir.icon = EditorInterface.get_editor_theme().get_icon(
		"Folder", "EditorIcons"
	)
	set_up_settings()
	_eSettings_changed()
	assetFinder = LocalAssetsAssetFinder.new()
	get_assets(assetPath.text)


## Updates settings from the EditorSettings object.
func _eSettings_changed():
	if editorSettings.has_setting("Local_Assets/asset_dir"):
		assetPath.text = editorSettings.get_setting("Local_Assets/asset_dir")
		assetPath.text_changed.emit(assetPath.text)
	if editorSettings.has_setting("Local_Assets/File_preview_names"):
		file_names = editorSettings.get_setting("Local_Assets/File_preview_names")
	if editorSettings.has_setting("Local_Assets/use_first_image_found"):
		useFirstImage = editorSettings.get_setting("Local_Assets/use_first_image_found")
	if editorSettings.has_setting("Local_Assets/use_uniform_image_size"):
		useUniformImageSize = editorSettings.get_setting("Local_Assets/use_uniform_image_size")
	if editorSettings.has_setting("Local_Assets/uniform_image_size"):
		uniformImageSize = editorSettings.get_setting("Local_Assets/uniform_image_size")


## Sets up default editor settings if they are not present.
func set_up_settings():
	if !editorSettings.has_setting("Local_Assets/asset_dir"):
		set_editor_setting("Local_Assets/asset_dir", "", TYPE_STRING)
	if !editorSettings.has_setting("Local_Assets/File_preview_names"):
		set_editor_setting(
			"Local_Assets/File_preview_names",
			PackedStringArray(["Preview", "Asset"]),
			TYPE_PACKED_STRING_ARRAY
		)
	if !editorSettings.has_setting("Local_Assets/use_first_image_found"):
		set_editor_setting("Local_Assets/use_first_image_found", false, TYPE_BOOL)
	if !editorSettings.has_setting("Local_Assets/use_uniform_image_size"):
		set_editor_setting("Local_Assets/use_uniform_image_size", false, TYPE_BOOL)
	if !editorSettings.has_setting("Local_Assets/uniform_image_size"):
		set_editor_setting("Local_Assets/uniform_image_size", Vector2i(918, 515), TYPE_VECTOR2I)


## Helper function to set an editor setting and update its type.
func set_editor_setting(s_name: String, value: Variant, type: Variant.Type):
	editorSettings.set_setting(s_name, value)
	editorSettings.add_property_info({"name": s_name, "type": type})


## Cleans up the cache when exiting the scene tree.
func _exit_tree():
	if thread1.is_started():
		await thread1.wait_to_finish()
	DirAccess.remove_absolute(cache_path)


## Opens a file dialog to select a directory for assets.
func _on_open_dir_pressed():
	Files.show()
	var f = await Files.dir_selected
	assetPath.text = f
	_on_assets_path_changed(f)


## Updates the displayed assets when the asset path changes.
func _on_assets_path_changed(new_text: String):
	for child in grid.get_children():
		child.queue_free()
	if assetFinder:
		get_assets(new_text)


## Searches assets by name and tag, displaying matched items.
func search(search_string: String):
	backgroundText.hide()
	if search_string.is_empty():
		_on_pagination_bar_page_changed(%PaginationBar.current_page)
		return
	clear_items()

	var found: bool = false
	search_string = search_string.to_lower()
	var tag_search_term: String = ""
	var tag_search_pattern = "tag:"
	var search_terms: Array = search_string.split(" ")

	# Extract tag search term if present
	for term in search_terms:
		if term.begins_with(tag_search_pattern):
			tag_search_term = term.substr(tag_search_pattern.length())
			search_terms.erase(term)
			break

	# Construct name search string
	var name_search_string = array_to_string(search_terms).strip_edges()

	# Locate JSON files and search entries
	var dir = DirAccess.open(assets_cache_path)
	if dir:
		for file in dir.get_files():
			if file.ends_with(".json"):
				var json = load(assets_cache_path.path_join(file)) as JSON
				if json and json.data:
					for entry in json.data:
						var name_found = entry["name"].to_lower().find(name_search_string) != -1
						var tag_found = tag_search_term in entry.get("tags", [])

						if (
							(tag_search_term != "" and name_found and tag_found)
							or (tag_search_term == "" and name_found)
						):
							var node: LocalAssetsItem = item.instantiate()
							node.root = self
							node.asset_name = entry["name"]
							node.asset_icon_path = entry.get("image_path", null)
							node.asset_path = entry["path"]
							node.tags = entry.get("tags", [])
							node.visible = true
							node.update()
							grid.call_deferred("add_child", node)
							found = true

	# Show "Not Found" message if no matches are found
	if !found:
		backgroundText.text = "Not Found"
		backgroundText.show()


## Saves the current asset directory path to editor settings.
func save():
	set_editor_setting("Local_Assets/asset_dir", assetPath.text, TYPE_STRING)


## Clears all items from the grid container.
func clear_items():
	for c: Control in grid.get_children():
		c.queue_free()


## Loads assets from the specified path and starts the asset finding process.
func get_assets(Path: String):
	print_verbose("LocalAssets: looking for assets")
	backgroundText.text = "Loading"
	grid.hide()
	backgroundText.show()
	for file in DirAccess.get_directories_at(cache_path):
		DirAccess.remove_absolute(file)
	if thread1.is_started():
		await _wait_for_thread_non_blocking(thread1)

	assetFinder._file_index = 1
	thread1.start(
		assetFinder.find_assets.bind(
			Path, file_names, useFirstImage, useUniformImageSize, uniformImageSize
		)
	)
	await _wait_for_thread_non_blocking(thread1)

	var assets = load(assets_cache_path.path_join("assetGroup_1.json")).data
	if typeof(assets) == TYPE_ARRAY:
		if assets.is_empty():
			backgroundText.text = "No assets found."
			return
		assets.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
		add_items(assets)
		save()
		backgroundText.hide()
		grid.show()
		_on_folder_changed()


# Waits non-blocking until the given thread finishes its task.
func _wait_for_thread_non_blocking(thread: Thread) -> Variant:
	while thread.is_alive():
		await get_tree().process_frame
	if thread.is_started():
		return await thread.wait_to_finish()
	else:
		return FAILED


# Adds items from the provided asset array to the grid container.
func add_items(_items: Array):
	for i: Dictionary in _items:
		var item: LocalAssetsItem = (
			load("res://addons/local_assets/Components/Item/Item.tscn").instantiate()
		)
		if item:
			item.root = self
			item.asset_icon = Image.load_from_file(i.get("image_path", ""))
			item.tags = i.get("tags", [])
			item.asset_name = i.get("name", "")
			item.asset_path = i.get("path", "")
			item.update()
			grid.call_deferred_thread_group("add_child", item)


# Updates the displayed items when pagination page changes.
func _on_pagination_bar_page_changed(new_page: int):
	clear_items()
	add_items(load(assets_cache_path.path_join("assetGroup_%s.json" % str(new_page))).data)


# Handles cleanup notifications before the node is deleted.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		await DirAccess.remove_absolute(cache_path)


func array_to_string(array: Array) -> String:
	var string: String
	for i in array:
		string += i + " "
	return string


# Called when the folder content changes, updates the pagination bar.
func _on_folder_changed() -> void:
	var files = DirAccess.get_files_at(assets_cache_path)
	%PaginationBar.total_pages = files.size()
