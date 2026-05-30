@tool
class_name LocalAssetsAssetCopier extends RefCounted


static func copy_file(src_path: String, dst_path: String) -> void:
	if not FileAccess.file_exists(src_path):
		printerr("LocalAssets: Failed to open source file for reading: ", src_path)
		return
	var dst_dir: DirAccess = DirAccess.open("res://")
	var dst_base_dir = dst_path.get_base_dir()
	if dst_dir and not dst_dir.dir_exists(dst_base_dir):
		dst_dir.make_dir_recursive(dst_base_dir)
	var file_data = FileAccess.get_file_as_bytes(src_path)
	var file = FileAccess.open(dst_path, FileAccess.WRITE)
	if file and file.get_error() == OK:
		file.store_buffer(file_data)
		file.close()
	else:
		printerr("LocalAssets: Failed to open destination file for writing: ", dst_path)


static func copy_gltf_file(src_path: String, dst_path: String) -> void:
	copy_file(src_path, dst_path)

	var f := FileAccess.open(src_path, FileAccess.READ)
	if not f:
		return
	var content := f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(content) != OK:
		return
	var data = json.data
	if not data is Dictionary:
		return

	var src_base := src_path.get_base_dir()
	var dst_base := dst_path.get_base_dir()
	for image in data.get("images", []):
		if not image is Dictionary:
			continue
		var uri: String = image.get("uri", "")
		if uri.is_empty() or uri.begins_with("data:"):
			continue
		copy_file(src_base.path_join(uri), dst_base.path_join(uri))


static func copy_assets(src_path: String, dst_path: String) -> void:
	var src_dir = DirAccess.open(src_path)
	var dst_dir: DirAccess = DirAccess.open("res://")
	if src_dir.get_open_error() == OK:
		if not dst_dir.dir_exists(dst_path):
			dst_dir.make_dir_recursive(dst_path)
		src_dir.list_dir_begin()
		while true:
			var file_or_dir = src_dir.get_next()
			if file_or_dir == "":
				break
			var src_item_path = src_path + "/" + file_or_dir
			var dst_item_path = dst_path + "/" + file_or_dir
			if src_dir.current_is_dir():
				copy_assets(src_item_path, dst_item_path)
			else:
				if FileAccess.file_exists(src_item_path):
					var file_data = FileAccess.get_file_as_bytes(src_item_path)
					var file = FileAccess.open(dst_item_path, FileAccess.WRITE)
					if file.get_error() == OK:
						file.store_buffer(file_data)
						file.close()
					else:
						printerr(
							"LocalAssets: Failed to open destination file for writing: ",
							dst_item_path
						)
				else:
					printerr("LocalAssets: Failed to open source file for reading: ", src_item_path)
		src_dir.list_dir_end()
	else:
		printerr("LocalAssets: Failed to open source directory: ", src_path)
