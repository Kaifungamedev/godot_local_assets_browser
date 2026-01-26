@tool
class_name LocalAssetsItem extends PanelContainer

var asset_name: String
var asset_path: String
var asset_icon: Image
var asset_icon_path: String:
	set = set_image_path
var asset: Dictionary
var root: LocalAssets
var tags: Array
var is_ready: bool = false
var id: int

@onready var icon_rect: TextureRect = $MarginContainer/VBoxContainer/HBoxContainer/Icon
@onready var name_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Name
@onready var path_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Path
@onready
var tags_container: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Tags


func _ready():
	path_button.icon = EditorInterface.get_editor_theme().get_icon("Load", "EditorIcons")
	is_ready = true


func set_image_path(path):
	if path != null:
		asset_icon = Image.load_from_file(path)


func set_from_asset_dict(dict: Dictionary):
	asset_name = dict.get("name")
	asset_path = dict.get("path")
	asset_icon_path = dict.get("image_path")
	tags = dict.get("tags")


func update():
	if not is_ready:
		await ready
	path_button.text = asset_path
	path_button.tooltip_text = asset_path
	if asset_icon:
		icon_rect.texture = make_icon(asset_icon)
		icon_rect.tooltip_text = icon_rect.texture.resource_name
	else:
		icon_rect.texture = EditorInterface.get_editor_theme().get_icon("FileBroken", "EditorIcons")
	name_label.text = asset_name
	name_label.tooltip_text = asset_name
	_update_tags()


func _update_tags():
	for child in tags_container.get_children():
		child.queue_free()
	for tag in tags:
		var tag_node = load("res://addons/local_assets/Components/Tag/Tag.tscn").instantiate()
		tag_node.text = tag
		tags_container.call_thread_safe("add_child", tag_node)


func _on_path_pressed():
	OS.shell_show_in_file_manager(asset_path, true)


func _on_import_pressed():
	root.copy_asset(asset_path, asset_name)


func make_icon(source_icon: Image) -> ImageTexture:
	var texture: ImageTexture = ImageTexture.new()
	if root.use_uniform_image_size:
		source_icon.resize(
			root.uniform_image_size.x, root.uniform_image_size.y, Image.INTERPOLATE_NEAREST
		)
	return texture.create_from_image(source_icon)


func _on_edit_pressed() -> void:
	root.edit_asset(asset["id"], self)
