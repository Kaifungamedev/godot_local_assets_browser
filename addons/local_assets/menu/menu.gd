@tool
class_name LocalAssets extends Control

@onready var Files: FileDialog = $FileDialog
@onready var assetPath: LineEdit = %AssetsPath
@onready var grid: GridContainer = %GridContainer
@onready var backgroundText = %BackgroundText

var editorSettings: EditorSettings = EditorInterface.get_editor_settings()
var command_palette = EditorInterface.get_command_palette()
var file_names: PackedStringArray
var useFirstImage: bool
var useUniformImageSize: bool
var uniformImageSize: Vector2i
var assetManager: AssetManager
var pageSize:int = 50
var db_path: String = EditorInterface.get_editor_paths().get_data_dir().path_join("assets.db")
var item = load("res://addons/local_assets/Components/Item/Item.tscn")


func _ready():
	editorSettings.settings_changed.connect(_eSettings_changed)
	$VBoxContainer/TopBar/path/OpenDir.icon = EditorInterface.get_editor_theme().get_icon(
		"Folder", "EditorIcons"
	)
	set_up_settings()
	_eSettings_changed()
	# external_command is a function that will be called with the command is executed.
	command_palette.add_command("Reset_db", "localAssets/Reset_db",_reset_db)

	# Initialize AssetManager with database
	assetManager = AssetManager.new_db(db_path)

	# Configure preview settings from editor settings
	if not file_names.is_empty():
		assetManager.set_preview_file_names(file_names)
	assetManager.set_use_first_image(useFirstImage)

	# Load assets if path is set
	if not assetPath.text.is_empty():
		var start = Time.get_ticks_msec()
		await load_assets()
		var end = Time.get_ticks_msec()
		print("time: ", end - start," ms")


func _eSettings_changed():
	if editorSettings.has_setting("Local_Assets/asset_dir"):
		assetPath.text = editorSettings.get_setting("Local_Assets/asset_dir")
		assetPath.text_changed.emit(assetPath.text)
	if editorSettings.has_setting("Local_Assets/File_preview_names"):
		file_names = editorSettings.get_setting("Local_Assets/File_preview_names")
		if assetManager and not file_names.is_empty():
			assetManager.set_preview_file_names(file_names)
	if editorSettings.has_setting("Local_Assets/page_size"):
			pageSize = editorSettings.get_setting("Local_Assets/page_size")
			if assetManager:
				assetManager.set_page_size(pageSize)
				clear_items()
				load_assets()
	if editorSettings.has_setting("Local_Assets/use_first_image_found"):
		useFirstImage = editorSettings.get_setting("Local_Assets/use_first_image_found")
		if assetManager:
			assetManager.set_use_first_image(useFirstImage)
	if editorSettings.has_setting("Local_Assets/use_uniform_image_size"):
		useUniformImageSize = editorSettings.get_setting("Local_Assets/use_uniform_image_size")
	if editorSettings.has_setting("Local_Assets/uniform_image_size"):
		uniformImageSize = editorSettings.get_setting("Local_Assets/uniform_image_size")


func set_up_settings():
	if !editorSettings.has_setting("Local_Assets/asset_dir"):
		set_editor_setting("Local_Assets/asset_dir", "", TYPE_STRING)
	if !editorSettings.has_setting("Local_Assets/File_preview_names"):
		set_editor_setting(
			"Local_Assets/File_preview_names",
			PackedStringArray(["Preview", "Asset"]),
			TYPE_PACKED_STRING_ARRAY
		)
	if !editorSettings.has_setting("Local_Assets/page_size"):
		set_editor_setting("Local_Assets/page_size", 50, TYPE_INT)
	if !editorSettings.has_setting("Local_Assets/use_first_image_found"):
		set_editor_setting("Local_Assets/use_first_image_found", false, TYPE_BOOL)
	if !editorSettings.has_setting("Local_Assets/use_uniform_image_size"):
		set_editor_setting("Local_Assets/use_uniform_image_size", false, TYPE_BOOL)
	if !editorSettings.has_setting("Local_Assets/uniform_image_size"):
		set_editor_setting("Local_Assets/uniform_image_size", Vector2i(918, 515), TYPE_VECTOR2I)
	if !editorSettings.has_setting("Local_Assets/uniform_image_size"):
		set_editor_setting("Local_Assets/uniform_image_size", Vector2i(918, 515), TYPE_VECTOR2I)


func set_editor_setting(s_name: String, value: Variant, type: Variant.Type):
	editorSettings.set_setting(s_name, value)
	editorSettings.add_property_info({"name": s_name, "type": type})


func _exit_tree():
	if assetManager:
		assetManager.quit()


func _on_open_dir_pressed():
	Files.show()
	var f = await Files.dir_selected
	assetPath.text = f
	_on_assets_path_changed(f)


func _on_assets_path_changed(new_text: String):
	clear_items()
	if new_text.is_empty():
		backgroundText.text = "No path selected"
		backgroundText.show()
		grid.hide()
		return
	load_assets()


func search(search_string: String):
	backgroundText.hide()

	if search_string.is_empty():
		_on_pagination_bar_page_changed(%PaginationBar.current_page)
		return

	clear_items()

	# Use AssetManager's search functionality
	var results = assetManager.search(search_string, 1)

	if assetManager.get_error() != OK:
		backgroundText.text = "Search failed"
		backgroundText.show()
		return

	if results.assets.is_empty():
		backgroundText.text = "Not Found"
		backgroundText.show()
		return

	# Update pagination
	%PaginationBar.total_pages = results.num_of_pages
	%PaginationBar.current_page = 1

	# Display results
	add_items(results.assets)
	backgroundText.hide()
	grid.show()


func save():
	set_editor_setting("Local_Assets/asset_dir", assetPath.text, TYPE_STRING)


func clear_items():
	for c: Control in grid.get_children():
		c.queue_free()


func load_assets():
	print_verbose("LocalAssets: scanning for assets")
	backgroundText.text = "Loading..."
	grid.hide()
	backgroundText.show()

	# Scan directory for assets in a separate thread
	var thread = Thread.new()
	thread.start(_scan_assets_thread.bind(assetPath.text))
	await _wait_for_thread_non_blocking(thread)

	if assetManager.get_error() != OK:
		backgroundText.text = "Failed to scan directory"
		return

	# Get total count
	var total_count = assetManager.get_asset_count()

	if total_count == 0:
		backgroundText.text = "No assets found."
		return

	# Update pagination
	%PaginationBar.total_pages = assetManager.get_pages()
	%PaginationBar.current_page = 1

	# Load first page
	var page_data = assetManager.get_assets(1)

	if assetManager.get_error() == OK and not page_data.assets.is_empty():
		add_items(page_data.assets)
		save()
		backgroundText.hide()
		grid.show()
	else:
		backgroundText.text = "Failed to load assets"


func _scan_assets_thread(path: String):
	assetManager.find_assets(path)


func add_items(_items: Array):
	for i in _items:
		var asset_item: LocalAssetsItem = item.instantiate()
		if asset_item:
			asset_item.root = self
			asset_item.asset_name = i.get("name", "")
			asset_item.asset_path = i.get("path", "")
			asset_item.tags = i.get("tags", [])

			# Load image if path exists
			var img_path = i.get("image_path", "")
			if not img_path.is_empty():
				asset_item.asset_icon = Image.load_from_file(img_path)

			asset_item.update()
			grid.add_child(asset_item)


func _on_pagination_bar_page_changed(new_page: int):
	clear_items()

	var page_data = assetManager.get_assets(new_page)

	if assetManager.get_error() == OK:
		add_items(page_data.assets)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if assetManager:
			assetManager.quit()


func copy_asset(dir: String, asset_name: String):
	# Copy assets to project
	var thread = Thread.new()
	thread.start(LocalAssetsAssetCopier.copy_assets.bind(dir, "res://Assets/%s" % asset_name))
	await _wait_for_thread_non_blocking(thread)
	EditorInterface.get_resource_filesystem().scan()


func _wait_for_thread_non_blocking(thread: Thread) -> Variant:
	while thread.is_alive():
		await get_tree().process_frame
	if thread.is_started():
		return await thread.wait_to_finish()
	else:
		return FAILED

func _reset_db():
	assetManager.quit()
	DirAccess.remove_absolute(db_path)
	assetManager = AssetManager.new_db(db_path)
	clear_items()
	if not assetPath.text.is_empty():
		load_assets()


func _on_tree_exiting() -> void:
	if assetManager:
		assetManager.quit()
	command_palette.remove_command("localAssets/Reset_db")
	
