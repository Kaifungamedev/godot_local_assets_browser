@tool
class_name LocalAssetsModelPreviewer extends Node

## Renders thumbnails for glTF model files into a reusable off-screen viewport and
## builds runtime-renderable model scenes for the larger preview window.
## Only glTF (.glb/.gltf) can be loaded at runtime.

const MODEL_EXTENSIONS := ["glb", "gltf"]

var thumb_size: Vector2i = Vector2i(96, 96)

var _viewport: SubViewport
var _camera: Camera3D
var _holder: Node3D
var _cache: Dictionary = {}  # path -> ImageTexture
var _queue: Array = []  # Array of { "path": String, "callback": Callable }
var _busy: bool = false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = thumb_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true

	_holder = Node3D.new()
	_viewport.add_child(_holder)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -40, 0)
	light.light_energy = 1.4
	_viewport.add_child(light)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.environment = _make_environment()
	_viewport.add_child(_camera)

	add_child(_viewport)


static func is_model(path: String) -> bool:
	return path.get_extension().to_lower() in MODEL_EXTENSIONS


static func _make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.ambient_light_energy = 1.0
	return env


## Build a runtime-renderable scene from a glTF file. Returns null on failure.
static func build_model_scene(path: String) -> Node3D:
	if not is_model(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var scene := doc.generate_scene(state)
	if scene == null:
		return null
	_convert_importer_meshes(scene)
	_recover_textures(scene, path, state.json)
	return scene


## glTF loaded at runtime produces non-rendering ImporterMeshInstance3D nodes; swap each
## for a MeshInstance3D holding the baked mesh.
static func _convert_importer_meshes(root: Node) -> void:
	var importers: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n := stack.pop_back() as Node
		for c in n.get_children():
			stack.append(c)
		if n is ImporterMeshInstance3D:
			importers.append(n)
	for node in importers:
		var imi := node as ImporterMeshInstance3D
		var importer_mesh := imi.get_mesh()
		if importer_mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = importer_mesh.get_mesh()
		mi.transform = imi.transform
		var parent := imi.get_parent()
		var idx := imi.get_index()
		parent.add_child(mi)
		parent.move_child(mi, idx)
		parent.remove_child(imi)
		imi.free()


## Combined world-space AABB of every visual instance under [param scene].
static func compute_aabb(scene: Node3D) -> AABB:
	var aabb := AABB()
	var has := false
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n := stack.pop_back() as Node
		for c in n.get_children():
			stack.append(c)
		var vi := n as VisualInstance3D
		if vi == null:
			continue
		var a := vi.get_aabb()
		var t := vi.global_transform
		for i in 8:
			var cx: float = a.size.x if (i & 1) else 0.0
			var cy: float = a.size.y if (i & 2) else 0.0
			var cz: float = a.size.z if (i & 4) else 0.0
			var wp := t * (a.position + Vector3(cx, cy, cz))
			if not has:
				aabb = AABB(wp, Vector3.ZERO)
				has = true
			else:
				aabb = aabb.expand(wp)
	return aabb


## Runtime glTF/GLB loading can't import textures referenced by an external URI: those
## files live outside the project and have no import metadata, so the model loads
## untextured (asset packs commonly ship one shared colormap/palette this way). Re-load the
## referenced image straight off disk and apply it to any surface that ended up untextured.
## [param json] is GLTFState.json, which is populated for both .gltf and binary .glb.
static func _recover_textures(scene: Node3D, model_path: String, json: Dictionary) -> void:
	if not json.has("images"):
		return
	var base_dir := model_path.get_base_dir()
	var tex: Texture2D = null
	var images: Array = json["images"]
	for entry in images:
		if not (entry is Dictionary):
			continue
		var img: Dictionary = entry
		var uri := str(img.get("uri", ""))
		if uri.is_empty() or uri.begins_with("data:"):
			continue
		var found := _find_texture(base_dir, uri.uri_decode())
		if found.is_empty():
			continue
		var image := Image.load_from_file(found)
		if image != null:
			tex = ImageTexture.create_from_image(image)
			break
	if tex == null:
		return
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n := stack.pop_back() as Node
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var bm := mi.get_active_material(i) as BaseMaterial3D
			if bm != null and bm.albedo_texture == null:
				var bm2 := bm.duplicate() as BaseMaterial3D
				bm2.albedo_texture = tex
				mi.set_surface_override_material(i, bm2)


static func _find_texture(start_dir: String, uri: String) -> String:
	var file_name := uri.get_file()
	var dir := start_dir
	for _i in 6:
		# the URI exactly as declared (e.g. "Textures/colormap.png"), relative to this dir
		var as_declared := dir.path_join(uri)
		if FileAccess.file_exists(as_declared):
			return as_declared
		var here := dir.path_join(file_name)
		if FileAccess.file_exists(here):
			return here
		var in_textures := dir.path_join("Textures").path_join(file_name)
		if FileAccess.file_exists(in_textures):
			return in_textures
		var parent := dir.get_base_dir()
		if parent == dir or parent.is_empty():
			break
		dir = parent
	return ""


func request_thumbnail(path: String, callback: Callable) -> void:
	if _cache.has(path):
		callback.call(_cache[path])
		return
	_queue.append({"path": path, "callback": callback})
	if not _busy:
		_process_queue()


func _process_queue() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var job: Dictionary = _queue.pop_front()
	await _render_thumbnail(job["path"], job["callback"])
	_process_queue()


func _render_thumbnail(path: String, callback: Callable) -> void:
	for c in _holder.get_children():
		c.free()
	var scene := build_model_scene(path)
	if scene == null:
		if _callback_valid(callback):
			callback.call(null)
		return
	_holder.add_child(scene)
	var aabb := compute_aabb(scene)
	var center := aabb.get_center()
	var radius: float = max(aabb.size.length() * 0.5, 0.001)
	var dist: float = radius / sin(deg_to_rad(_camera.fov * 0.5))
	_camera.global_position = center + Vector3(1, 0.7, 1).normalized() * dist * 1.2
	_camera.look_at(center, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var tex := ImageTexture.create_from_image(_viewport.get_texture().get_image())
	_cache[path] = tex
	for c in _holder.get_children():
		c.free()
	if _callback_valid(callback):
		callback.call(tex)


func _callback_valid(callback: Callable) -> bool:
	var obj := callback.get_object()
	return obj != null and is_instance_valid(obj)
