@tool
class_name LocalAssetsPreviewWindow extends Window

## A popup that previews a single asset at a larger size before import. Adapts to the
## asset type: images show full size, audio gets play/stop, glTF models get an
## interactive (drag-to-rotate) 3D view.

const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "bmp", "tga", "webp", "svg"]
const AUDIO_EXTENSIONS := ["ogg", "mp3", "wav"]

var _root_box: VBoxContainer
var _audio_player: AudioStreamPlayer

# Model orbit state.
var _model_camera: Camera3D
var _model_center: Vector3 = Vector3.ZERO
var _model_distance: float = 1.0
var _model_yaw: float = 0.6
var _model_pitch: float = 0.4
var _dragging: bool = false


func _ready() -> void:
	title = "Asset Preview"
	size = Vector2i(720, 620)
	min_size = Vector2i(360, 320)
	exclusive = false
	visible = false
	always_on_top = true
	close_requested.connect(_on_close)

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	add_child(margin)

	_root_box = VBoxContainer.new()
	margin.add_child(_root_box)


func show_asset(path: String, asset_name: String) -> void:
	title = asset_name if not asset_name.is_empty() else path.get_file()
	_clear()

	var ext := path.get_extension().to_lower()
	if ext in IMAGE_EXTENSIONS:
		_build_image(path)
	elif LocalAssetsModelPreviewer.is_model(path):
		_build_model(path)
	elif ext in AUDIO_EXTENSIONS:
		_build_audio(path, ext)
	else:
		_build_unsupported(path)

	popup_centered(Vector2i(720, 620))
	move_to_foreground()
	grab_focus()


func _clear() -> void:
	_audio_player.stop()
	_audio_player.stream = null
	_model_camera = null
	for c in _root_box.get_children():
		c.free()


func _build_image(path: String) -> void:
	var img := Image.load_from_file(path)
	var rect := TextureRect.new()
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var info := ""
	if img != null:
		rect.texture = ImageTexture.create_from_image(img)
		info = "%d x %d" % [img.get_width(), img.get_height()]
	_root_box.add_child(rect)
	_add_footer(path, info)


func _build_audio(path: String, ext: String) -> void:
	var stream: AudioStream = null
	if ext == "ogg":
		stream = AudioStreamOggVorbis.load_from_file(path)
	elif ext == "mp3":
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(path)
		stream = mp3

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var icon := TextureRect.new()
	icon.texture = EditorInterface.get_editor_theme().get_icon("AudioStream", "EditorIcons")
	icon.custom_minimum_size = Vector2(96, 96)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)

	if stream != null:
		_audio_player.stream = stream
		var controls := HBoxContainer.new()
		controls.alignment = BoxContainer.ALIGNMENT_CENTER
		var theme := EditorInterface.get_editor_theme()
		var play := Button.new()
		play.text = "Play"
		play.icon = theme.get_icon("Play", "EditorIcons")
		play.pressed.connect(_play_audio)
		var stop := Button.new()
		stop.text = "Stop"
		stop.icon = theme.get_icon("Stop", "EditorIcons")
		stop.pressed.connect(_stop_audio)
		controls.add_child(play)
		controls.add_child(stop)
		box.add_child(controls)
	else:
		var lbl := Label.new()
		lbl.text = "Playback of .%s files is not supported in this Godot version." % ext
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(lbl)

	_root_box.add_child(center)
	_add_footer(path, "")


func _build_model(path: String) -> void:
	var scene := LocalAssetsModelPreviewer.build_model_scene(path)
	if scene == null:
		_build_unsupported(path)
		return

	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.gui_input.connect(_on_model_gui_input)

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpc.add_child(viewport)

	viewport.add_child(scene)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -40, 0)
	light.light_energy = 1.3
	viewport.add_child(light)

	_model_camera = Camera3D.new()
	_model_camera.fov = 45.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.55)
	_model_camera.environment = env
	viewport.add_child(_model_camera)

	# The viewport must be in the tree before framing, otherwise Camera3D.look_at()
	# fails ("Node not inside tree") and the model stays unframed until the first drag.
	_root_box.add_child(vpc)

	var aabb := LocalAssetsModelPreviewer.compute_aabb(scene)
	_model_center = aabb.get_center()
	var radius: float = max(aabb.size.length() * 0.5, 0.001)
	_model_distance = radius / sin(deg_to_rad(_model_camera.fov * 0.5)) * 1.3
	_update_model_camera()

	var hint := Label.new()
	hint.text = "Drag to rotate"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	_root_box.add_child(hint)

	_add_footer(path, "%.2f x %.2f x %.2f" % [aabb.size.x, aabb.size.y, aabb.size.z])


func _update_model_camera() -> void:
	if _model_camera == null:
		return
	var dir := Vector3(
		cos(_model_pitch) * sin(_model_yaw),
		sin(_model_pitch),
		cos(_model_pitch) * cos(_model_yaw)
	)
	_model_camera.global_position = _model_center + dir * _model_distance
	_model_camera.look_at(_model_center, Vector3.UP)


func _on_model_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_model_yaw -= event.relative.x * 0.01
		_model_pitch = clamp(_model_pitch + event.relative.y * 0.01, -1.4, 1.4)
		_update_model_camera()


func _build_unsupported(path: String) -> void:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = EditorInterface.get_editor_theme().get_icon("FileBroken", "EditorIcons")
	icon.custom_minimum_size = Vector2(96, 96)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var lbl := Label.new()
	lbl.text = "No preview available for .%s" % path.get_extension()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	center.add_child(box)
	_root_box.add_child(center)
	_add_footer(path, "")


func _add_footer(path: String, info: String) -> void:
	var footer := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = path.get_file()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(name_lbl)
	if not info.is_empty():
		var info_lbl := Label.new()
		info_lbl.text = info
		info_lbl.modulate = Color(1, 1, 1, 0.6)
		footer.add_child(info_lbl)
	_root_box.add_child(footer)


func _play_audio() -> void:
	if _audio_player.stream != null:
		_audio_player.play()


func _stop_audio() -> void:
	_audio_player.stop()


func _on_close() -> void:
	_audio_player.stop()
	hide()
