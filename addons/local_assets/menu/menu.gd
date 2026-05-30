@tool
class_name LocalAssets extends Control

enum ViewMode { PACKS, INDIVIDUAL }

## File extensions scanned when listing individual assets (single files).
const INDIVIDUAL_ASSET_EXTENSIONS := [
	"png", "jpg", "jpeg", "obj", "fbx", "glb", "gltf", "wav", "ogg", "mp3"
]

var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
var file_names: PackedStringArray
var use_first_image: bool
var use_folder_name: bool
var use_uniform_image_size: bool
var uniform_image_size: Vector2i
var asset_manager: AssetManager
var page_size: int = 50
var item_scene = load("res://addons/local_assets/Components/Item/Item.tscn")
var asset_item_scene = load("res://addons/local_assets/Components/asset_item/asset_item.tscn")
var view_mode: int = ViewMode.PACKS
var _scanned_modes: Dictionary = {}
var model_previewer: LocalAssetsModelPreviewer
var preview_window: LocalAssetsPreviewWindow

@onready var files_dialog: FileDialog = $FileDialog
@onready var asset_path_edit: LineEdit = %AssetsPath
@onready var grid: GridContainer = %GridContainer
@onready var background_text = %BackgroundText
@onready var db_path: String = (
	EditorInterface.get_editor_paths()
	.get_data_dir()
	.path_join("assets.db")
)
@onready var asset_editor: LocalAssetsAssetEditor = $VSplitContainer/AssetEditor
@onready var view_tabs: TabBar = %ViewTabs


func _ready():
	editor_settings.settings_changed.connect(_on_editor_settings_changed)
	$VSplitContainer/VBoxContainer/TopBar/path/OpenDir.icon = (
		EditorInterface.get_editor_theme().get_icon("Folder", "EditorIcons")
	)
	_setup_previews()
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



func _setup_previews():
	model_previewer = LocalAssetsModelPreviewer.new()
	add_child(model_previewer)
	preview_window = LocalAssetsPreviewWindow.new()
	add_child(preview_window)


func open_preview(path: String, asset_name: String) -> void:
	if preview_window != null:
		preview_window.show_asset(path, asset_name)


func _on_view_tabs_tab_changed(tab: int):
	view_mode = tab
	%Search.text = ""
	clear_items()
	if asset_path_edit.text.is_empty():
		background_text.text = "No path selected"
		background_text.show()
		grid.hide()
		return
	# The database is persisted, so only walk the filesystem when this mode has no
	# data yet. Re-scanning on every switch would freeze the UI for several seconds.
	var already_scanned: bool = _scanned_modes.get(view_mode, false)
	var should_scan: bool = not already_scanned and _get_total_count() == 0
	load_assets(should_scan)


func _get_page(page: int) -> Dictionary:
	if view_mode == ViewMode.INDIVIDUAL:
		return asset_manager.get_individual_assets(page)
	return asset_manager.get_assets(page)


func _search_page(query: String, page: int) -> Dictionary:
	if view_mode == ViewMode.INDIVIDUAL:
		return asset_manager.search_individual_assets(query, page)
	return asset_manager.search(query, page)


func _get_total_count() -> int:
	if view_mode == ViewMode.INDIVIDUAL:
		return asset_manager.get_individual_asset_count()
	return asset_manager.get_asset_count()


func _get_total_pages() -> int:
	if view_mode == ViewMode.INDIVIDUAL:
		return asset_manager.get_individual_asset_pages()
	return asset_manager.get_pages()


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
	_scanned_modes.clear()
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

	var results = _search_page(search_string, 1)

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


func load_assets(scan: bool = true):
	print_verbose("LocalAssets: scanning for assets")
	background_text.text = "Loading..."
	grid.hide()
	background_text.show()

	if scan:
		# The AssetManager extension must only be called from the main thread.
		# Running the scan on a Thread let the instance be freed mid-call, which
		# crashes godot-rust ("Destroyed an object ... while a bind() was active").
		await get_tree().process_frame
		if asset_manager == null:
			return
		_scan_assets(asset_path_edit.text)
		_scanned_modes[view_mode] = true

		if asset_manager.get_error() != OK:
			background_text.text = "Failed to scan directory"
			return

	var total_count = _get_total_count()

	if total_count == 0:
		background_text.text = "No assets found."
		return

	update_pagination_bars(_get_total_pages())

	var page_data = _get_page(1)

	if asset_manager.get_error() == OK and not page_data.assets.is_empty():
		add_items(page_data.assets)
		save()
		background_text.hide()
		grid.show()
	else:
		background_text.text = "Failed to load assets"


func _scan_assets(path: String):
	if view_mode == ViewMode.INDIVIDUAL:
		asset_manager.find_individual_assets(path, PackedStringArray(INDIVIDUAL_ASSET_EXTENSIONS))
	else:
		asset_manager.find_assets(path)


func add_items(items: Array):
	if view_mode == ViewMode.INDIVIDUAL:
		_add_individual_items(items)
	else:
		_add_pack_items(items)


func _add_pack_items(items: Array):
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
			grid.call_deferred("add_child",asset_item)


func _add_individual_items(items: Array):
	for i in items:
		var asset_item: LocalAssetsAssetItem = asset_item_scene.instantiate()
		if asset_item:
			asset_item.root = self
			asset_item.asset = i
			asset_item.id = i.get("id", 0)
			asset_item.asset_name = i.get("name", "")
			asset_item.asset_path = i.get("path", "")

			var img_path = i.get("image_path", "")
			if not img_path.is_empty():
				asset_item.asset_icon = Image.load_from_file(img_path)

			asset_item.update()
			grid.call_deferred("add_child",asset_item)


func _on_pagination_bar_page_changed(new_page: int):
	clear_items()
	var page_data = _get_page(new_page)
	if asset_manager.get_error() == OK:
		add_items(page_data.assets)
	var pagebars = get_tree().get_nodes_in_group("PageBarLocalAssets_sdlakjf")
	for bar: LocalAssetsPaginationBar in pagebars:
		bar.on_page_button_pressed(new_page, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if asset_manager:
			asset_manager = null


func copy_asset(dir: String, name: String):
	var thread = Thread.new()
	thread.start(LocalAssetsAssetCopier.copy_assets.bind(dir, "res://Assets/%s" % name))
	await _wait_for_thread(thread)
	EditorInterface.get_resource_filesystem().scan()


func copy_file(src_path: String, _name: String = ""):
	var dst_path := "res://Assets/%s" % src_path.get_file()
	var thread := Thread.new()
	if src_path.get_extension().to_lower() == "gltf":
		thread.start(LocalAssetsAssetCopier.copy_gltf_file.bind(src_path, dst_path))
	else:
		thread.start(LocalAssetsAssetCopier.copy_file.bind(src_path, dst_path))
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

	_scanned_modes.clear()
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
