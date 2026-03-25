extends RefCounted
## Asset Forge — Batch Processor
##
## 1. Find & load GLTFs from source folder
## 2. Extract materials as standalone .tres files
## 3. Replace inline materials with saved references
## 4. Organize into a clean folder structure
## 5. Generate a GridMap MeshLibrary from all meshes

var log_messages: Array[String] = []
var _material_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}


func process(config: Dictionary) -> void:
	log_messages.clear()
	_material_cache.clear()
	_mesh_cache.clear()

	var source: String = config.source_folder
	var output: String = config.output_folder

	if not DirAccess.dir_exists_absolute(source):
		_log("[color=red]✗ Source folder not found: %s[/color]" % source)
		return

	var scenes_dir: String = output.path_join(config.scenes_subdir)
	var materials_dir: String = output.path_join(config.materials_subdir)
	var meshlib_dir: String = output.path_join(config.meshlib_subdir)

	_ensure_dir(output)
	_ensure_dir(scenes_dir)
	if config.extract_materials:
		_ensure_dir(materials_dir)
	if config.generate_meshlib:
		_ensure_dir(meshlib_dir)

	var gltf_files: Array[String] = []
	_find_gltf_files(source, gltf_files, config.recursive)

	if gltf_files.is_empty():
		_log("[color=red]✗ No .gltf or .glb files found in: %s[/color]" % source)
		return

	_log("Found [b]%d[/b] GLTF file(s)\n" % gltf_files.size())

	var mesh_lib := MeshLibrary.new()
	var next_mesh_id: int = 0
	var success_count: int = 0
	var fail_count: int = 0
	var spacing: float = config.spacing_x

	for i in gltf_files.size():
		var file_path: String = gltf_files[i]
		var file_name: String = file_path.get_file().get_basename()
		var clean_name: String = _sanitize(file_name, i)

		_log("[%d/%d] [b]%s[/b]" % [i + 1, gltf_files.size(), file_path.get_file()])

		var root_node: Node = _load_gltf(file_path)
		if root_node == null:
			fail_count += 1
			continue

		root_node.name = clean_name

		if config.extract_materials:
			_extract_materials(root_node, materials_dir, clean_name)

		if config.generate_meshlib:
			next_mesh_id = _collect_meshes(root_node, mesh_lib, next_mesh_id, clean_name)

		if root_node is Node3D and spacing > 0.0:
			(root_node as Node3D).position.x = success_count * spacing

		var scene_path: String = scenes_dir.path_join(clean_name + ".tscn")
		var saved: bool = _save_scene(root_node, scene_path)
		root_node.free()

		if saved:
			_log("  [color=green]✓ Scene: %s[/color]" % scene_path)
			success_count += 1
		else:
			fail_count += 1
		_log("")

	if config.generate_meshlib and next_mesh_id > 0:
		var lib_path: String = meshlib_dir.path_join("mesh_library.tres")
		var lib_err: int = ResourceSaver.save(mesh_lib, lib_path)
		if lib_err == OK:
			_log("[color=green]✓ MeshLibrary: %s (%d items)[/color]" % [lib_path, next_mesh_id])
		else:
			_log("[color=red]✗ MeshLibrary save failed (error %d)[/color]" % lib_err)

	_log("\n[b]Summary:[/b] %d ok, %d failed" % [success_count, fail_count])
	if config.extract_materials:
		_log("  Materials: %d" % _material_cache.size())
	if config.generate_meshlib:
		_log("  MeshLib items: %d" % next_mesh_id)


# ── GLTF ───────────────────────────────────────────────────────

func _load_gltf(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: int = doc.append_from_file(path, state)
	if err != OK:
		_log("  [color=red]✗ Parse error (code %d)[/color]" % err)
		return null
	var node: Node = doc.generate_scene(state)
	if node == null:
		_log("  [color=red]✗ generate_scene() returned null[/color]")
	return node


# ── Materials ──────────────────────────────────────────────────

func _extract_materials(node: Node, out_dir: String, prefix: String) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			_process_mesh_mats(mi, out_dir, prefix)
		for s in mi.get_surface_override_material_count():
			var mat: Material = mi.get_surface_override_material(s)
			if mat != null and not _is_external(mat):
				_save_override(mi, s, mat, out_dir, prefix)
	for child in node.get_children():
		_extract_materials(child, out_dir, prefix)


func _process_mesh_mats(mi: MeshInstance3D, out_dir: String, prefix: String) -> void:
	var mesh: Mesh = mi.mesh
	for s in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(s)
		if mat == null or _is_external(mat):
			continue

		var mat_id: int = mat.get_instance_id()
		if _material_cache.has(mat_id):
			var cached: Material = load(_material_cache[mat_id]) as Material
			if cached:
				mesh.surface_set_material(s, cached)
			continue

		var mat_name: String = mat.resource_name
		if mat_name.is_empty():
			mat_name = "mat_%s_s%d" % [mi.name, s]
		var save_path: String = _unique_path(out_dir.path_join(_sanitize(prefix + "_" + mat_name, s) + ".tres"))

		# Duplicate: GLTF sub-resources can't be saved directly
		var mat_copy: Material = mat.duplicate(true) as Material
		mat_copy.resource_path = ""
		mat_copy.resource_name = mat_name

		var save_err: int = ResourceSaver.save(mat_copy, save_path)
		if save_err == OK:
			_material_cache[mat_id] = save_path
			var saved: Material = load(save_path) as Material
			if saved:
				mesh.surface_set_material(s, saved)
			_log("  Material: %s" % save_path.get_file())
		else:
			_log("  [color=red]✗ Material save failed: %s (error %d)[/color]" % [save_path.get_file(), save_err])


func _save_override(mi: MeshInstance3D, s: int, mat: Material, out_dir: String, prefix: String) -> void:
	var mat_id: int = mat.get_instance_id()
	if _material_cache.has(mat_id):
		var cached: Material = load(_material_cache[mat_id]) as Material
		if cached:
			mi.set_surface_override_material(s, cached)
		return

	var mat_name: String = mat.resource_name
	if mat_name.is_empty():
		mat_name = "override_%s_s%d" % [mi.name, s]
	var save_path: String = _unique_path(out_dir.path_join(_sanitize(prefix + "_" + mat_name, s) + ".tres"))

	# Duplicate: GLTF sub-resources can't be saved directly
	var mat_copy: Material = mat.duplicate(true) as Material
	mat_copy.resource_path = ""
	mat_copy.resource_name = mat_name

	var save_err: int = ResourceSaver.save(mat_copy, save_path)
	if save_err == OK:
		_material_cache[mat_id] = save_path
		var saved: Material = load(save_path) as Material
		if saved:
			mi.set_surface_override_material(s, saved)
		_log("  Override: %s" % save_path.get_file())


func _is_external(mat: Material) -> bool:
	if mat.resource_path.is_empty():
		return false
	if mat.resource_path.begins_with("res://.godot"):
		return false
	return true


# ── MeshLibrary ────────────────────────────────────────────────

func _collect_meshes(node: Node, lib: MeshLibrary, next_id: int, prefix: String) -> int:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			var iid: int = mi.mesh.get_instance_id()
			if not _mesh_cache.has(iid):
				# Duplicate mesh so it survives root.free()
				var mesh_copy: Mesh = mi.mesh.duplicate(true) as Mesh

				lib.create_item(next_id)
				lib.set_item_mesh(next_id, mesh_copy)

				var item_name: String = mi.name
				if item_name.is_empty() or item_name == "MeshInstance3D":
					item_name = "%s_%d" % [prefix, next_id]
				lib.set_item_name(next_id, item_name)

				var shapes: Array = []
				var shape: ConvexPolygonShape3D = mesh_copy.create_convex_shape()
				if shape:
					shapes.append(Transform3D.IDENTITY)
					shapes.append(shape)
					lib.set_item_shapes(next_id, shapes)

				_log("  MeshLib [%d]: %s" % [next_id, item_name])
				_mesh_cache[iid] = next_id
				next_id += 1

	for child in node.get_children():
		next_id = _collect_meshes(child, lib, next_id, prefix)
	return next_id


# ── Save Scene ─────────────────────────────────────────────────

func _save_scene(root: Node, path: String) -> bool:
	_set_owner_recursive(root, root)
	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err != OK:
		_log("  [color=red]✗ pack() failed (error %d)[/color]" % pack_err)
		return false
	var save_err: int = ResourceSaver.save(packed, path)
	if save_err != OK:
		_log("  [color=red]✗ save() failed (error %d)[/color]" % save_err)
		return false
	return true


# ── File Utils ─────────────────────────────────────────────────

func _find_gltf_files(folder: String, results: Array[String], recursive: bool) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		_log("[color=red]✗ Cannot open: %s[/color]" % folder)
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full: String = folder.path_join(entry)
			if dir.current_is_dir():
				if recursive:
					_find_gltf_files(full, results, true)
			else:
				var ext: String = entry.get_extension().to_lower()
				if ext == "gltf" or ext == "glb":
					results.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	results.sort()


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
		result = "item_%d" % fallback
	return result


func _unique_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var dir: String = path.get_base_dir()
	var base: String = path.get_file().get_basename()
	var ext: String = path.get_extension()
	var n: int = 2
	while true:
		var candidate: String = dir.path_join("%s_%d.%s" % [base, n, ext])
		if not FileAccess.file_exists(candidate):
			return candidate
		n += 1
	return path


func _log(msg: String) -> void:
	log_messages.append(msg)
