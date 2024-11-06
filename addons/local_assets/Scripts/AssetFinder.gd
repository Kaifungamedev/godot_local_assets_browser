@tool
extends RefCounted
class_name LocalAssetsAssetFinder

var _file_index: int = 1
var _cache_path: String = EditorInterface.get_editor_paths().get_cache_dir().path_join(
	"LocalAssets"
)
var _chunk: Array = []
var _max_chunk_size: int = 50  # Define the maximum size of the chunk before saving
var fileExtentions: Array = ["png", "jpeg", "jpg", "bmp", "tga", "webp", "svg"]


func find_assets(
	folder_path: String,
	file_names: PackedStringArray,
	useFirstImage: bool,
	useUniformImageSize: bool,
	uniformImageSize: Vector2i,
	max_chunk_size: int = 50  # You can pass chunk size as a parameter
):
	_collect_assets(
		folder_path,
		file_names,
		useFirstImage,
		useUniformImageSize,
		uniformImageSize,
		_max_chunk_size
	)
	LocalAssetsAssetSorter.sort(_cache_path.path_join("assetGroup"), _max_chunk_size)


func _collect_assets(
	folder_path: String,
	file_names: PackedStringArray,
	useFirstImage: bool,
	useUniformImageSize: bool,
	uniformImageSize: Vector2i,
	max_chunk_size: int = 50  # You can pass chunk size as a parameter
) -> void:
	_max_chunk_size = max_chunk_size
	var dir = DirAccess.open(folder_path)
	if dir:
		var path = dir.get_current_dir(true)
		if dir.file_exists("Asset.json"):
			_add_to_chunk(load(path.path_join("Asset.json")).data)
			return
		for file in file_names:
			for extention in fileExtentions:
				var filename = "%s.%s" % [file, extention]
				var foldername = (
					(dir.get_current_dir().get_base_dir().replace("\\", "/").split("/") as Array)
					. back()
				)
				var folderfilename = "%s.%s" % [foldername, extention]
				if dir.file_exists(filename):
					_add_asset(path, filename)
					return
				elif dir.file_exists(folderfilename):
					_add_asset(path, folderfilename)
					return
		if useFirstImage:
			for file in dir.get_files():
				if file.get_extension() in fileExtentions:
					_add_asset(path, file)
					return
		var folders = dir.get_directories() as Array
		folders.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
		for folder in folders:
			_collect_assets(
				path.path_join(folder),
				file_names,
				useFirstImage,
				useUniformImageSize,
				uniformImageSize,
				_max_chunk_size
			)


func _add_asset(path: String, filename: String) -> void:
	var ana: Array = path.split("/")
	var a_name = ana.back()
	_add_to_chunk({"image_path": path.path_join(filename), "name": a_name, "path": path})


func _add_to_chunk(asset_data: Dictionary) -> void:
	_chunk.append(asset_data)
	if _chunk.size() >= _max_chunk_size:
		_save_chunk(_chunk)
		_chunk.clear()


func _save_chunk(chunk: Array):
	if not DirAccess.dir_exists_absolute(_cache_path.path_join("assetGroup")):
		DirAccess.make_dir_recursive_absolute(_cache_path.path_join("assetGroup"))
	var file = FileAccess.open(
		_cache_path.path_join("assetGroup").path_join("assetGroup_%s.json" % str(_file_index)),
		FileAccess.WRITE
	)
	file.store_string(JSON.stringify(chunk))
	file.close()
	_file_index += 1  # Increment the file index for the next chunk
