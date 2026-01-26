@tool
class_name LocalAssets extends Control

var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
var file_names: PackedStringArray
var use_first_image: bool
var use_folder_name: bool
var use_uniform_image_size: bool
var uniform_image_size: Vector2i
var asset_manager: AssetManager
var page_size: int = 50
var item_scene = load("res://addons/local_assets/Components/Item/Item.tscn")

@onready var files_dialog: FileDialog = $FileDialog
@onready var asset_path_edit: LineEdit = %AssetsPath
@onready var grid: GridContainer = %GridContainer
@onready var background_text = %BackgroundText
@onready
var db_path: String = EditorInterface.get_editor_paths().get_data_dir().path_join("assets.db")
@onready var asset_editor: LocalAssetsAssetEditor = $VSplitContainer/AssetEditor


func _ready():
	editor_settings.settings_changed.connect(_on_editor_settings_changed)
	$VSplitContainer/VBoxContainer/TopBar/path/OpenDir.icon = (
		EditorInterface.get_editor_theme().get_icon("Folder", "EditorIcons")
	)
	_setup_settings()
	_on_editor_settings_changed()

	asset_manager = AssetManager.new_db(db_path)

	if not file_names.is_empty():
		asset_manager.set_preview_file_names(file_names)
	asset_manager.set_use_first_image(use_first_image)
	asset_manager.set_use_folder_name(use_folder_name)

	if not asset_path_edit.text.is_empty():
		var start = Time.get_ticks_msec()
		await load_assets()
		var end = Time.get_ticks_msec()
		print_verbose("[Local Assets]: asset load time: ", end - start, " ms")


func _on_editor_settings_changed():
	if editor_settings.has_setting("Local_Assets/asset_dir"):
		asset_path_edit.text = editor_settings.get_setting("Local_Assets/asset_dir")
		asset_path_edit.text_changed.emit(asset_path_edit.text)
	if editor_settings.has_setting("Local_Assets/File_preview_names"):
		file_names = editor_settings.get_setting("Local_Assets/File_preview_names")
		if asset_manager and not file_names.is_empty():
			asset_manager.set_preview_file_names(file_names)
	if editor_settings.has_setting("Local_Assets/page_size"):
		page_size = editor_settings.get_setting("Local_Assets/page_size")
		if asset_manager:
			asset_manager.set_page_size(page_size)
			clear_items()
			load_assets()
	if editor_settings.has_setting("Local_Assets/use_first_image_found"):
		use_first_image = editor_settings.get_setting("Local_Assets/use_first_image_found")
		if asset_manager:
			asset_manager.set_use_first_image(use_first_image)
	if editor_settings.has_setting("Local_Assets/use_folder_name"):
		use_folder_name = editor_settings.get_setting("Local_Assets/use_folder_name")
		if asset_manager:
			asset_manager.set_use_folder_name(use_folder_name)
	if editor_settings.has_setting("Local_Assets/use_uniform_image_size"):
		use_uniform_image_size = editor_settings.get_setting("Local_Assets/use_uniform_image_size")
	if editor_settings.has_setting("Local_Assets/uniform_image_size"):
		uniform_image_size = editor_settings.get_setting("Local_Assets/uniform_image_size")


func edit_asset(id: int, item: LocalAssetsItem):
	asset_editor.edit(id, item)
	$VSplitContainer.queue_sort()


func _setup_settings():
	if not editor_settings.has_setting("Local_Assets/asset_dir"):
		_set_editor_setting("Local_Assets/asset_dir", "", TYPE_STRING)
	if not editor_settings.has_setting("Local_Assets/File_preview_names"):
		_set_editor_setting(
			"Local_Assets/File_preview_names",
			PackedStringArray(
				["Preview", "Asset", "^(?i)preview.*", "^(?i)asset.*", "^(?i)content.*"]
			),
			TYPE_PACKED_STRING_ARRAY
		)
	if not editor_settings.has_setting("Local_Assets/page_size"):
		_set_editor_setting("Local_Assets/page_size", 50, TYPE_INT)
	if not editor_settings.has_setting("Local_Assets/use_first_image_found"):
		_set_editor_setting("Local_Assets/use_first_image_found", false, TYPE_BOOL)
	if not editor_settings.has_setting("Local_Assets/use_folder_name"):
		_set_editor_setting("Local_Assets/use_folder_name", true, TYPE_BOOL)
	if not editor_settings.has_setting("Local_Assets/use_uniform_image_size"):
		_set_editor_setting("Local_Assets/use_uniform_image_size", false, TYPE_BOOL)
	if not editor_settings.has_setting("Local_Assets/uniform_image_size"):
		_set_editor_setting("Local_Assets/uniform_image_size", Vector2i(918, 515), TYPE_VECTOR2I)


func _set_editor_setting(setting_name: String, value: Variant, type: Variant.Type):
	editor_settings.set_setting(setting_name, value)
	editor_settings.add_property_info({"name": setting_name, "type": type})


func _exit_tree():
	if asset_manager:
		asset_manager = null


func _on_open_dir_pressed():
	files_dialog.show()
	var selected_path = await files_dialog.dir_selected
	asset_path_edit.text = selected_path
	_on_assets_path_changed(selected_path)


func _on_assets_path_changed(new_text: String):
	clear_items()
	if new_text.is_empty():
		background_text.text = "No path selected"
		background_text.show()
		grid.hide()
		return
	load_assets()


func search(search_string: String):
	background_text.hide()

	if search_string.is_empty():
		_on_pagination_bar_page_changed(%PaginationBar.current_page)
		return

	clear_items()

	var results = asset_manager.search(search_string, 1)

	if asset_manager.get_error() != OK:
		background_text.text = "Search failed"
		background_text.show()
		return

	if results.assets.is_empty():
		background_text.text = "Not Found"
		background_text.show()
		return

	update_pagination_bars(results.num_of_pages)
	add_items(results.assets)
	background_text.hide()
	grid.show()


func save():
	_set_editor_setting("Local_Assets/asset_dir", asset_path_edit.text, TYPE_STRING)


func clear_items():
	for child: Control in grid.get_children():
		child.queue_free()


func load_assets():
	print_verbose("LocalAssets: scanning for assets")
	background_text.text = "Loading..."
	grid.hide()
	background_text.show()

	var thread = Thread.new()
	thread.start(_scan_assets_thread.bind(asset_path_edit.text))
	await _wait_for_thread(thread)

	if asset_manager.get_error() != OK:
		background_text.text = "Failed to scan directory"
		return

	var total_count = asset_manager.get_asset_count()

	if total_count == 0:
		background_text.text = "No assets found."
		return

	update_pagination_bars(asset_manager.get_pages())

	var page_data = asset_manager.get_assets(1)

	if asset_manager.get_error() == OK and not page_data.assets.is_empty():
		add_items(page_data.assets)
		save()
		background_text.hide()
		grid.show()
	else:
		background_text.text = "Failed to load assets"


func _scan_assets_thread(path: String):
	asset_manager.find_assets(path)


func add_items(items: Array):
	for i in items:
		var asset_item: LocalAssetsItem = item_scene.instantiate()
		if asset_item:
			asset_item.root = self
			asset_item.asset = i
			asset_item.asset_name = i.get("name", "")
			asset_item.asset_path = i.get("path", "")
			asset_item.tags = i.get("tags", [])

			var img_path = i.get("image_path", "")
			if not img_path.is_empty():
				asset_item.asset_icon = Image.load_from_file(img_path)

			asset_item.update()
			grid.add_child(asset_item)


func _on_pagination_bar_page_changed(new_page: int):
	clear_items()
	var page_data = asset_manager.get_assets(new_page)
	if asset_manager.get_error() == OK:
		add_items(page_data.assets)
	var pagebars = get_tree().get_nodes_in_group("PageBarLocalAssets_sdlakjf")
	for bar: LocalAssetsPaginationBar in pagebars:
		bar.on_page_button_pressed(new_page,true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if asset_manager:
			asset_manager = null


func copy_asset(dir: String, name: String):
	var thread = Thread.new()
	thread.start(LocalAssetsAssetCopier.copy_assets.bind(dir, "res://Assets/%s" % name))
	await _wait_for_thread(thread)
	EditorInterface.get_resource_filesystem().scan()


func _wait_for_thread(thread: Thread) -> Variant:
	while thread.is_alive():
		await get_tree().process_frame
	if thread.is_started():
		return await thread.wait_to_finish()
	return FAILED


func _reset_db():
	asset_manager = null

	await get_tree().process_frame
	await get_tree().process_frame

	if FileAccess.file_exists(db_path):
		var err = DirAccess.remove_absolute(db_path)
		if err != OK:
			push_error("Failed to delete database: " + str(err))
			return

	await get_tree().process_frame

	asset_manager = AssetManager.new_db(db_path)
	asset_manager.set_preview_file_names(file_names)
	asset_manager.set_use_first_image(use_first_image)
	asset_manager.set_use_folder_name(use_folder_name)
	asset_manager.set_page_size(page_size)

	clear_items()
	if not asset_path_edit.text.is_empty():
		load_assets()

	print("Database reset complete")


func update_pagination_bars(total_pages: int, current_page: int = 1):
	var pagebars = get_tree().get_nodes_in_group("PageBarLocalAssets_sdlakjf")
	for bar: LocalAssetsPaginationBar in pagebars:
		if bar.current_page != current_page or bar.total_pages != total_pages:
			bar.current_page = current_page
			bar.total_pages = total_pages


func _on_tree_exiting() -> void:
	if asset_manager:
		asset_manager = null
