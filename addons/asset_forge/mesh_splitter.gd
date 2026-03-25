extends RefCounted
## Asset Forge — Mesh Splitter
##
## Takes a single GLTF/GLB file containing multiple meshes (e.g. character
## body parts) and saves each MeshInstance3D as its own standalone .tscn scene.
##
## Before: manually importing GLB, making each part root, deleting the rest,
##         saving as new .tscn × N parts.
## After:  one click.

var log_messages: Array[String] = []


func split(source_path: String, output_dir: String) -> void:
	log_messages.clear()

	# ── Validate source
	if not FileAccess.file_exists(source_path):
		_log("[color=red]✗ File not found: %s[/color]" % source_path)
		return

	var ext: String = source_path.get_extension().to_lower()
	if ext != "gltf" and ext != "glb":
		_log("[color=red]✗ Not a GLTF/GLB file: %s[/color]" % source_path)
		return

	# ── Load the GLTF
	_log("Loading: %s" % source_path.get_file())

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var parse_err: int = doc.append_from_file(source_path, state)
	if parse_err != OK:
		_log("[color=red]✗ Parse error (code %d)[/color]" % parse_err)
		return

	var root: Node = doc.generate_scene(state)
	if root == null:
		_log("[color=red]✗ generate_scene() returned null[/color]")
		return

	# ── Ensure output dir
	_ensure_dir(output_dir)

	# ── Find all MeshInstance3D nodes (recursive)
	var mesh_nodes: Array[MeshInstance3D] = []
	_find_mesh_instances(root, mesh_nodes)

	if mesh_nodes.is_empty():
		_log("[color=red]✗ No MeshInstance3D nodes found in this file[/color]")
		root.free()
		return

	_log("Found [b]%d[/b] mesh(es)\n" % mesh_nodes.size())

	var saved_count: int = 0
	var source_name: String = source_path.get_file().get_basename()

	for mi in mesh_nodes:
		# Build a clean part name
		var part_name: String = _build_part_name(mi, source_name, saved_count)

		_log("  Splitting: [b]%s[/b]" % part_name)

		# Create a standalone scene for this mesh
		var part_root := Node3D.new()
		part_root.name = part_name

		# Duplicate the MeshInstance3D so we don't mess with the original tree
		var mesh_copy: MeshInstance3D = mi.duplicate() as MeshInstance3D
		mesh_copy.name = mi.name
		# Reset transform so the part is at origin
		mesh_copy.transform = mi.global_transform

		part_root.add_child(mesh_copy)
		mesh_copy.owner = part_root

		# If the mesh has children (e.g. collision shapes, skeletons), include them
		_set_owner_recursive(mesh_copy, part_root)

		# Save
		var save_path: String = _unique_path(output_dir.path_join(part_name + ".tscn"))
		var saved: bool = _save_packed_scene(part_root, save_path)
		part_root.free()

		if saved:
			_log("    [color=green]✓ %s[/color]" % save_path)
			saved_count += 1
		else:
			_log("    [color=red]✗ Failed to save[/color]")

	root.free()

	_log("\n[b]Summary:[/b] %d / %d parts saved to %s" % [saved_count, mesh_nodes.size(), output_dir])


# ── Find all MeshInstance3D nodes recursively ──────────────────

func _find_mesh_instances(node: Node, results: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			results.append(mi)
	for child in node.get_children():
		_find_mesh_instances(child, results)


# ── Name builder ───────────────────────────────────────────────

func _build_part_name(mi: MeshInstance3D, source_name: String, index: int) -> String:
	var raw: String = mi.name
	# Skip generic names
	if raw.is_empty() or raw == "MeshInstance3D" or raw.begins_with("@"):
		raw = "%s_part_%d" % [source_name, index]

	return _sanitize(raw, index)


# ── Save ───────────────────────────────────────────────────────

func _save_packed_scene(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err != OK:
		_log("    [color=red]pack() error %d[/color]" % pack_err)
		return false
	var save_err: int = ResourceSaver.save(packed, path)
	if save_err != OK:
		_log("    [color=red]save() error %d[/color]" % save_err)
		return false
	return true


# ── Utils ──────────────────────────────────────────────────────

func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	for child in node.get_children():
		child.owner = new_owner
		_set_owner_recursive(child, new_owner)


func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		var err: int = DirAccess.make_dir_recursive_absolute(path)
		if err == OK:
			_log("Created: %s" % path)
		else:
			_log("[color=red]✗ mkdir failed: %s (error %d)[/color]" % [path, err])


func _sanitize(raw: String, fallback: int) -> String:
	var clean: String = raw.replace("-", "_").replace(" ", "_").replace(".", "_")
	var result: String = ""
	for i in clean.length():
		var c: int = clean.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95:
			result += clean[i]
	if not result.is_empty() and result.unicode_at(0) >= 48 and result.unicode_at(0) <= 57:
		result = "_" + result
	if result.is_empty():
		result = "part_%d" % fallback
	return result


func _unique_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var dir: String = path.get_base_dir()
	var base: String = path.get_file().get_basename()
	var ext_str: String = path.get_extension()
	var n: int = 2
	while true:
		var candidate: String = dir.path_join("%s_%d.%s" % [base, n, ext_str])
		if not FileAccess.file_exists(candidate):
			return candidate
		n += 1
	return path


func _log(msg: String) -> void:
	log_messages.append(msg)
