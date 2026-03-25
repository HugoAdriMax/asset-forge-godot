class_name AssetForgeUtils
## Asset Forge — Shared Utilities
##
## Common helper functions used by both BatchProcessor and MeshSplitter.


## Recursively set owner on all children of a node.
static func set_owner_recursive(node: Node, new_owner: Node) -> void:
	for child in node.get_children():
		child.owner = new_owner
		set_owner_recursive(child, new_owner)


## Create a directory (and parents) if it doesn't exist.
## Returns log messages for the caller to handle.
static func ensure_dir(path: String) -> String:
	if not DirAccess.dir_exists_absolute(path):
		var err: int = DirAccess.make_dir_recursive_absolute(path)
		if err == OK:
			return "Created: %s" % path
		else:
			return "[color=red]✗ mkdir failed: %s (error %d)[/color]" % [path, err]
	return ""


## Sanitize a string to produce a valid GDScript/filesystem identifier.
## Keeps only A-Z, a-z, 0-9, and underscore. Prepends underscore if it
## starts with a digit. Falls back to a default name if result is empty.
static func sanitize(raw: String, fallback_prefix: String, fallback_index: int) -> String:
	var clean: String = raw.replace("-", "_").replace(" ", "_").replace(".", "_")
	var result: String = ""
	for i: int in clean.length():
		var c: int = clean.unicode_at(i)
		# A-Z (65-90), a-z (97-122), 0-9 (48-57), underscore (95)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95:
			result += clean[i]
	if not result.is_empty() and result.unicode_at(0) >= 48 and result.unicode_at(0) <= 57:
		result = "_" + result
	if result.is_empty():
		result = "%s_%d" % [fallback_prefix, fallback_index]
	return result


## Return a unique file path by appending _2, _3, etc. if the file already exists.
static func unique_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var dir: String = path.get_base_dir()
	var base: String = path.get_file().get_basename()
	var ext: String = path.get_extension()
	var n: int = 2
	while n < 10000:
		var candidate: String = dir.path_join("%s_%d.%s" % [base, n, ext])
		if not FileAccess.file_exists(candidate):
			return candidate
		n += 1
	return path
