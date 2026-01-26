@tool
class_name LocalAssetsAssetEditor extends Control

@export var menu: LocalAssets

var asset: Dictionary
var asset_manager: AssetManager
var item: LocalAssetsItem

@onready var image: TextureRect = $VBoxContainer/Edit/Preview
@onready var asset_path_edit = $VBoxContainer/Edit/GridContainer/Path
@onready var asset_name_edit = $VBoxContainer/Edit/GridContainer/Name
@onready var asset_image_path_edit = $VBoxContainer/Edit/GridContainer/ImagePath/ImagePath
@onready var asset_image_path_button = $VBoxContainer/Edit/GridContainer/ImagePath/OpenFile
@onready var asset_tags_edit = $VBoxContainer/Edit/GridContainer/Tags
@onready var file_dialog = EditorFileDialog.new()


func _ready():
	file_dialog.title = "Open file"
	file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = [
		"png",
		"jpeg",
		"jpg",
		"bmp",
		"tga",
		"webp",
		"svg",
		"*.png *.jpeg *.jpg *.bmp *.tga *.webp *.svg ; All supported images"
	]
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)
	asset_image_path_button.icon = EditorInterface.get_editor_theme().get_icon(
		"Folder", "EditorIcons"
	)


func edit(id: int, edited_item: LocalAssetsItem):
	item = edited_item
	if asset_manager == null:
		_get_asset_manager()
	asset = asset_manager.get_asset(id)
	_set_line_edits()
	_set_image()
	show()


func _get_asset_manager():
	if menu.asset_manager != null:
		asset_manager = menu.asset_manager


func _set_line_edits():
	if asset == null:
		return
	asset_path_edit.text = asset.get("path", "")
	asset_name_edit.text = asset.get("name", "")
	asset_image_path_edit.text = asset.get("image_path", "")
	asset_tags_edit.text = ", ".join(asset.get("tags", []))


func _set_image():
	var img_path: String = asset_image_path_edit.text
	var tex: Texture2D
	if img_path.is_empty():
		tex = EditorInterface.get_editor_theme().get_icon("FileBrokenBigThumb", "EditorIcons")
		image.set_tooltip_text("No image path")
	else:
		var img: Image = Image.load_from_file(img_path)
		tex = ImageTexture.create_from_image(img)
		image.set_tooltip_text(img_path)
	image.set_texture(tex)


func _on_save_pressed() -> void:
	var tags: Array[String] = []
	for i in asset_tags_edit.text.split(","):
		var tag = i.strip_edges()
		if not tag.is_empty():
			tags.append(tag)

	var asset_dict: Dictionary = {
		"path": asset_path_edit.text,
		"name": asset_name_edit.text,
		"image_path": asset_image_path_edit.text,
		"tags": tags
	}
	item.set_from_asset_dict(asset_dict)
	var file = FileAccess.open(asset_dict.path.path_join("Asset.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(asset_dict, "\t"))
		file.close()
	asset_dict["id"] = asset["id"]
	item.asset = asset_dict
	var error = asset_manager.update_asset(asset["id"], asset_dict)
	if error != OK:
		print("AssetManager: Update failed: ", error)
	item.update()


func _on_discard_pressed() -> void:
	hide()


func _on_image_path_text_changed(_new_text: String) -> void:
	_set_image()


func _on_open_file_pressed() -> void:
	file_dialog.popup_file_dialog()


func _on_file_selected(path: String) -> void:
	asset_image_path_edit.text = path


func _on_toggle_pressed() -> void:
	hide()


func _exit_tree() -> void:
	asset_manager = null
