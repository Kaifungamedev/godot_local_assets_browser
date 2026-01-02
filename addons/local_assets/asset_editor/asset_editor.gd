@tool
class_name LocalAssetsAssetEditor extends Control
@onready var image: TextureRect = $VBoxContainer/Edit/Preview
@onready var asset_path = $VBoxContainer/Edit/GridContainer/Path
@onready var asset_name = $VBoxContainer/Edit/GridContainer/Name
@onready var asset_image_path = $VBoxContainer/Edit/GridContainer/ImagePath/ImagePath
@onready var asset_image_path_button = $VBoxContainer/Edit/GridContainer/ImagePath/OpenFile
@onready var asset_tags = $VBoxContainer/Edit/GridContainer/Tags
@onready var file_diolog = EditorFileDialog.new()
@export var menu: LocalAssets
var asset: Dictionary
var asset_manager:AssetManager
var item:LocalAssetsItem

func _ready():
	file_diolog.title = "Open file"
	file_diolog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_diolog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_diolog.filters = ["png", "jpeg", "jpg", "bmp", "tga", "webp", "svg", "*.png *.jpeg *.jpg *.bmp *.tga *.webp *.svg ; All suported images"]
	add_child(file_diolog)
	asset_image_path_button.icon = EditorInterface.get_editor_theme().get_icon(
		"Folder", "EditorIcons"
	)


func edit(id:int, _item:LocalAssetsItem):
	item = _item
	if asset_manager == null:
		_get_asset_manager()
	asset = asset_manager.get_asset(id)
	_set_line_edits()
	_set_image()
	show()

func _get_asset_manager():
	if not menu.asset_manager == null:
		asset_manager = menu.asset_manager

func _set_line_edits():
	if asset == null:
		return
	asset_path.text = asset.get("path","")
	asset_name.text = asset.get("name","")
	asset_image_path.text = asset.get("image_path","")
	asset_tags.text = ", ".join(asset.get("tags",[]))

func _set_image():
	var _image_path:String = asset_image_path.text
	var _image: Image
	var _texture:Texture2D
	if _image_path.is_empty():
		_texture = EditorInterface.get_editor_theme().get_icon("FileBrokenBigThumb", "EditorIcons")
		image.set_tooltip_text("No image path")
	else:
		_image = Image.load_from_file(_image_path)
		_texture = ImageTexture.create_from_image(_image)
		image.set_tooltip_text(_image_path)
		
	image.set_texture(_texture)



func _on_save_pressed() -> void:
	var _tags: Array = Array()
	for i in asset_tags.text.split(","):
		var tag = i.strip_edges()
		if not tag.is_empty():
			_tags.append(tag)
	
	var asset_dict:Dictionary = {
	"path":asset_path.text,
	"name":asset_name.text,
	"image_path":asset_image_path.text,
	"tags":_tags
	}
	item.set_from_asset_dict(asset_dict)
	FileAccess.open(asset_dict.path.path_join("Asset.json"),FileAccess.WRITE).store_string(JSON.stringify(asset_dict,"\t"))
	asset_dict["id"] = asset["id"]
	item.asset = asset_dict
	var error = asset_manager.update_asset(asset["id"],asset_dict)
	if error != OK: 
		print("Update failed")
	item.update()




func _on_discard_pressed() -> void:
	hide()


func _on_image_path_text_changed(new_text: String) -> void:
	_set_image()


func _on_open_file_pressed() -> void:
	file_diolog.popup_file_dialog()


func _on_toggle_pressed() -> void:
	hide()
