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
		# Preserve global position when reparenting into the new scene
		mesh_copy.transform = mi.global_transform

		part_root.add_child(mesh_copy)
		mesh_copy.owner = part_root

		# If the mesh has children (e.g. collision shapes, skeletons), include them
		AssetForgeUtils.set_owner_recursive(mesh_copy, part_root)

		# Save
		var save_path: String = AssetForgeUtils.unique_path(output_dir.path_join(part_name + ".tscn"))
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

	return AssetForgeUtils.sanitize(raw, "part", index)


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

func _ensure_dir(path: String) -> void:
	var msg: String = AssetForgeUtils.ensure_dir(path)
	if not msg.is_empty():
		_log(msg)


func _log(msg: String) -> void:
	log_messages.append(msg)
