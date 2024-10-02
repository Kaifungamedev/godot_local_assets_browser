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
const fileExtentions = ["png", "jpeg", "jpg", "bmp", "tga", "webp", "svg"]


func _ready():
	editorSettings.settings_changed.connect(_eSettings_changed)
	$VBoxContainer/TopBar/path/OpenDir.icon = EditorInterface.get_editor_theme().get_icon("Folder", "EditorIcons")
	set_up_settings()
	_eSettings_changed()
	assetFinder = LocalAssetsAssetFinder.new()
	get_assets(assetPath.text)


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
	DirAccess.remove_absolute(cache_path)


func _on_open_dir_pressed():
	Files.show()
	var f = await Files.dir_selected
	assetPath.text = f
	_on_assets_path_changed(f)


func _on_assets_path_changed(new_text: String):
	for child in grid.get_children():
		child.queue_free()
	if assetFinder:
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
	print("looking for assets")
	backgroundText.text = "Loading"
	grid.hide()
	backgroundText.show()
	for file in DirAccess.get_directories_at(cache_path):
		DirAccess.remove_absolute(file)
	if thread1.is_started():
		await _wait_for_thread_non_blocking(thread1)
	assetFinder._file_index = 1
	thread1.start(assetFinder.find_assets.bind(Path, file_names, useFirstImage, useUniformImageSize, uniformImageSize))
	await _wait_for_thread_non_blocking(thread1)

	var assets = load(cache_path.path_join("assetGroup_1.json")).data
	if typeof(assets) == TYPE_ARRAY:
		if assets.is_empty():
			backgroundText.text = "No assets found."
			return
		assets.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)

		if thread1.is_started():
			await _wait_for_thread_non_blocking(thread1)
		add_items(assets)
		save()
		backgroundText.hide()
		grid.show()
		await _wait_for_thread_non_blocking(thread1)
		_on_folder_changed()


func _wait_for_thread_non_blocking(thread: Thread) -> Variant:
	while thread.is_alive():
		await get_tree().process_frame
	if thread.is_started():
		return await thread.wait_to_finish()
	else:
		return FAILED


func add_items(_items: Array):
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


func _on_pagination_bar_page_changed(new_page: int):
	clear_items()
	prints("loading page", new_page)
	add_items(load(cache_path.path_join("assetGroup_%s.json" % str(new_page))).data)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			DirAccess.remove_absolute(cache_path)


func _on_folder_changed() -> void:
	var files = DirAccess.get_files_at(cache_path)
	%PaginationBar.total_pages = files.size()
