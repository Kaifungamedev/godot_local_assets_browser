@tool
extends PanelContainer
class_name LocalAssetsItem
var asset_name: String
var asset_path: String
var asset_icon: Image
var asset_icon_path: String:
	set = set_image_path
var asset:Dictionary
var root: LocalAssets
var tags: Array
var is_ready: bool = false
var useUniformImageSize: bool = false
var id:int
@onready var _icon: TextureRect = $MarginContainer/VBoxContainer/HBoxContainer/Icon
@onready var _name: Label = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Name
@onready var _path: Button = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Path
@onready var _tags: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Tags


func _ready():
	_path.icon = EditorInterface.get_editor_theme().get_icon("Load", "EditorIcons")
	is_ready = true


func set_image_path(path):
	if path != null:
		asset_icon = Image.load_from_file(path)

func set_from_asset_dict(dict:Dictionary):
	asset_name = dict.get("name")
	asset_path = dict.get("path")
	asset_icon_path = dict.get("image_path")
	tags = dict.get("tags")

func update():
	if !is_ready:
		await ready
	_path.text = asset_path
	_path.tooltip_text = asset_path
	if asset_icon:
		_icon.texture = make_icon(asset_icon)
		_icon.tooltip_text = _icon.texture.resource_name
	else:
		_icon.texture = EditorInterface.get_editor_theme().get_icon("FileBroken", "EditorIcons")
	_name.text = asset_name
	_name.tooltip_text = asset_name
	if tags:
		_update_tags()


func _update_tags():
	for c in _tags.get_children():
		c.queue_free()
	for tag in tags:
		var tagNode = load("res://addons/local_assets/Components/Tag/Tag.tscn").instantiate()
		tagNode.text = tag
		_tags.call_thread_safe("add_child", tagNode)


func _on_path_pressed():
	OS.shell_show_in_file_manager(asset_path, true)


func _on_import_pressed():
	root.copy_asset(asset_path, asset_name)


func make_icon(icon: Image) -> ImageTexture:
	var texture: ImageTexture = ImageTexture.new()
	var _icon = icon
	if root.useUniformImageSize:
		icon.resize(root.uniformImageSize.x, root.uniformImageSize.y, Image.INTERPOLATE_NEAREST)
	return texture.create_from_image(icon)


func _on_edit_pressed() -> void:
	print(asset["id"])
	root.edit_asset(asset["id"],self)
