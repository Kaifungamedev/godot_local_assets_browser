@tool
extends Panel

var asset_name: String
var asset_path: String
var asset_icon: Texture2D
var root: Node
var is_ready: bool = false
@onready var _icon: TextureRect = %Icon
@onready var _name: Label = %Name
@onready var _path: Button = %Path


func _ready():
	_path.icon = EditorInterface.get_editor_theme().get_icon("Load", "EditorIcons")
	is_ready = true


func update():
	if !is_ready:
		await ready
	_path.text = asset_path
	_path.tooltip_text = asset_path
	if asset_icon:
		_icon.texture = asset_icon
		_icon.tooltip_text = _icon.texture.resource_name
	else:
		_icon.texture = EditorInterface.get_editor_theme().get_icon("FileBroken", "EditorIcons")
	_name.text = asset_name
	_name.tooltip_text = asset_name


func _on_path_pressed():
	OS.shell_show_in_file_manager(asset_path, true)


func _on_import_pressed():
	root.copy_files_recursive(asset_path, "res://Assets/%s" % asset_name)
