@tool
extends RefCounted
class_name LocalAssetsAssetCopier


static func copy_assets(src_path: String, dst_path: String) -> void:
	var src_dir = DirAccess.open(src_path)
	var dst_dir: DirAccess = DirAccess.open("res://")
	if src_dir.get_open_error() == OK:
		if !dst_dir.dir_exists(dst_path):
			dst_dir.make_dir_recursive(dst_path)
		src_dir.list_dir_begin()
		while true:
			var file_or_dir = src_dir.get_next()
			if file_or_dir == "":
				break
			var src_item_path = src_path + "/" + file_or_dir
			var dst_item_path = dst_path + "/" + file_or_dir
			if src_dir.current_is_dir():
				# Recursively copy subdirectory
				copy_assets(src_item_path, dst_item_path)
			else:
				# Copy file
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

	EditorInterface.get_resource_filesystem().scan()
