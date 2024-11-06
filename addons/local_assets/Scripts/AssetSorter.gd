extends RefCounted
class_name LocalAssetsAssetSorter


# Sorts JSON assets across multiple files alphabetically by "name" key
# Pass `entries_per_file` as the number of entries per file
static func sort(json_dir: String, entries_per_file: int):
	# Get all JSON files in the specified directory
	var json_files = []
	var dir = DirAccess.open(json_dir)
	if dir:
		for file in dir.get_files():
			if file.ends_with(".json"):
				json_files.append(json_dir + "/" + file)
		json_files.sort()

	# Ensure there are files to process
	if json_files.size() == 0:
		print("No JSON files found in the specified directory.")
		return

	# Collect all JSON entries across files
	var all_entries = []

	for i in range(0, json_files.size(), 2):
		# Open the first file
		var json1 = load(json_files[i]) as JSON
		if json1:
			all_entries.append_array(json1.data)

		# Open the second file if it exists
		if i + 1 < json_files.size():
			var json2 = load(json_files[i + 1]) as JSON
			if json2:
				all_entries.append_array(json2.data)

	# Remove duplicate entries based on the "name" key
	var unique_entries = {}
	for entry in all_entries:
		var name = entry["name"]
		unique_entries[name] = entry  # Overwrites duplicates, keeping only the last one

	# Convert the unique entries back to a list
	all_entries = unique_entries.values()

	# Sort the entries by the "name" key using naturalnocasecmp_to
	all_entries.sort_custom(_compare_names)

	# Calculate the number of files and extra entries
	var num_files = json_files.size()
	var extra_entries = all_entries.size() % num_files
	var start_index = 0

	for idx in range(num_files):
		# Calculate end index for each file
		var end_index = start_index + entries_per_file + (1 if idx < extra_entries else 0)

		# Write sorted subset to the current file
		var f = FileAccess.open(json_files[idx], FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(all_entries.slice(start_index, end_index), "\t", true))
			f.close()

		start_index = end_index

	# Now remove empty files after processing
	for file in json_files:
		if FileAccess.get_file_as_string(file).length() <= 5:
			print_verbose("LocalAssets: Removing empty file: " + file)
			DirAccess.open(json_dir).remove(file)  # Remove the empty file

	print_verbose("LocalAssets: Files sorted and written successfully!")


# Helper function for sorting by "name" key using naturalnocasecmp_to
static func _compare_names(a: Dictionary, b: Dictionary) -> bool:
	return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
