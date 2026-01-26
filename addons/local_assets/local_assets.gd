@tool
extends EditorPlugin

const ICON = preload("res://addons/local_assets/Icon.svg")

var main_panel_instance
var command_palette = EditorInterface.get_command_palette()


func _enter_tree():
	main_panel_instance = load("res://addons/local_assets/menu/menu.tscn").instantiate()
	command_palette.add_command(
		"Reset DB", "localAssets/Reset_db", Callable(main_panel_instance, "_reset_db")
	)
	if OS.get_name() == "Linux":
		command_palette.add_command("Add template", "localAssets/config_template", _add_template)
		command_palette.add_command(
			"Remove template", "localAssets/remove_config_template", _remove_template
		)

	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	_make_visible(false)


func _exit_tree():
	if main_panel_instance:
		EditorInterface.get_editor_main_screen().remove_child(main_panel_instance)
		command_palette.remove_command("localAssets/Reset_db")
		if OS.get_name() == "Linux":
			command_palette.remove_command("localAssets/config_template")
			command_palette.remove_command("localAssets/remove_config_template")
		main_panel_instance.free()


func _has_main_screen():
	return true


func _make_visible(visible):
	if main_panel_instance:
		main_panel_instance.visible = visible


func _get_plugin_name():
	return "Local Assets"


func _get_plugin_icon():
	return ICON


func _add_template():
	var template_path = ProjectSettings.globalize_path(
		"res://addons/local_assets/Assets_template.json"
	)
	DirAccess.copy_absolute(template_path, "~/Templates/Asset.json")


func _remove_template():
	DirAccess.remove_absolute("~/Templates/Asset.json")
