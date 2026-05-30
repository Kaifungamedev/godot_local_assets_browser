@tool
class_name LocalAssetsAssetItem extends PanelContainer

var asset_name: String
var asset_path: String
var asset_icon: Image
var asset: Dictionary
var root: LocalAssets
var id: int

@onready var icon_rect: TextureRect = $MarginContainer/VBoxContainer/HBoxContainer/Icon
@onready var name_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Name
@onready var path_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Path
@onready var preview_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/Preview


func _ready():
	path_button.icon = EditorInterface.get_editor_theme().get_icon("Load", "EditorIcons")
	if not preview_button.pressed.is_connected(_on_preview_pressed):
		preview_button.pressed.connect(_on_preview_pressed)


func update():
	if not is_node_ready():
		await ready
	path_button.text = asset_path
	path_button.tooltip_text = asset_path
	if asset_icon:
		icon_rect.texture = ImageTexture.create_from_image(asset_icon)
	else:
		_apply_fallback_icon()
	name_label.text = asset_name
	name_label.tooltip_text = asset_name


func _apply_fallback_icon() -> void:
	var theme := EditorInterface.get_editor_theme()
	var ext := asset_path.get_extension().to_lower()
	if ext in ["glb", "gltf"] and root != null and root.model_previewer != null:
		# Mesh icon as a placeholder; the rendered thumbnail replaces it when ready.
		icon_rect.texture = theme.get_icon("MeshInstance3D", "EditorIcons")
		root.model_previewer.request_thumbnail(asset_path, _on_thumbnail_ready)
	elif ext in ["wav", "ogg", "mp3"]:
		icon_rect.texture = theme.get_icon("AudioStream", "EditorIcons")
	elif ext in ["obj", "fbx"]:
		icon_rect.texture = theme.get_icon("MeshInstance3D", "EditorIcons")
	else:
		icon_rect.texture = theme.get_icon("FileBroken", "EditorIcons")


func _on_thumbnail_ready(tex: Texture2D) -> void:
	if tex != null:
		icon_rect.texture = tex
		icon_rect.tooltip_text = asset_name


func _on_preview_pressed() -> void:
	if root != null:
		root.open_preview(asset_path, asset_name)


func _on_path_pressed():
	OS.shell_show_in_file_manager(asset_path, true)


func _on_import_pressed():
	root.copy_file(asset_path, asset_name)
