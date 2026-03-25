@tool
extends EditorPlugin

const BatchProcessor := preload("res://addons/asset_forge/batch_processor.gd")
const MeshSplitter := preload("res://addons/asset_forge/mesh_splitter.gd")

var _dock: Control

# ── Batch Import tab controls
var _src_input: LineEdit
var _out_input: LineEdit
var _scenes_input: LineEdit
var _mats_input: LineEdit
var _meshlib_input: LineEdit
var _extract_mats_cb: CheckBox
var _gen_meshlib_cb: CheckBox
var _recursive_cb: CheckBox
var _spacing_spin: SpinBox
var _batch_log: RichTextLabel

# ── Mesh Splitter tab controls
var _split_input: LineEdit
var _split_out_input: LineEdit
var _split_log: RichTextLabel

# ── File dialogs
var _src_dialog: EditorFileDialog
var _out_dialog: EditorFileDialog
var _split_file_dialog: EditorFileDialog
var _split_out_dialog: EditorFileDialog

# Track which dialog sets which input
var _active_dialog_target: LineEdit


func _enter_tree() -> void:
	_dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_build_dialogs()


func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	if _dock:
		_dock.queue_free()
	for d: EditorFileDialog in [_src_dialog, _out_dialog, _split_file_dialog, _split_out_dialog]:
		if d:
			d.queue_free()


# ══════════════════════════════════════════════════════════════
# DOCK BUILDER
# ══════════════════════════════════════════════════════════════

func _build_dock() -> Control:
	var root := VBoxContainer.new()
	root.name = "AssetForge"
	root.custom_minimum_size = Vector2(260, 0)

	# Header
	var title := Label.new()
	title.text = "Asset Forge"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	# Tabs
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	tabs.add_child(_build_batch_tab())
	tabs.add_child(_build_splitter_tab())

	return root


# ── Batch Import Tab ──────────────────────────────────────────

func _build_batch_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Batch Import"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Source folder
	vbox.add_child(_label("Source Folder (GLTFs)"))
	_src_input = LineEdit.new()
	_src_input.text = "res://models/raw/"
	_src_input.placeholder_text = "res://models/raw/"
	var src_row := _path_row(_src_input, "_on_browse_src")
	vbox.add_child(src_row)

	# Output folder
	vbox.add_child(_label("Output Base Folder"))
	_out_input = LineEdit.new()
	_out_input.text = "res://assets/"
	_out_input.placeholder_text = "res://assets/"
	var out_row := _path_row(_out_input, "_on_browse_out")
	vbox.add_child(out_row)

	vbox.add_child(HSeparator.new())

	# Subfolder config
	vbox.add_child(_label("Subfolder Names"))
	_scenes_input = _setting_row(vbox, "Scenes:", "scenes")
	_mats_input = _setting_row(vbox, "Materials:", "materials")
	_meshlib_input = _setting_row(vbox, "MeshLib:", "mesh_library")

	vbox.add_child(HSeparator.new())

	# Options
	vbox.add_child(_label("Options"))

	_extract_mats_cb = CheckBox.new()
	_extract_mats_cb.text = "Extract materials as .tres"
	_extract_mats_cb.button_pressed = true
	vbox.add_child(_extract_mats_cb)

	_gen_meshlib_cb = CheckBox.new()
	_gen_meshlib_cb.text = "Generate GridMap MeshLibrary"
	_gen_meshlib_cb.button_pressed = true
	vbox.add_child(_gen_meshlib_cb)

	_recursive_cb = CheckBox.new()
	_recursive_cb.text = "Scan subfolders"
	_recursive_cb.button_pressed = false
	vbox.add_child(_recursive_cb)

	var spacing_row := HBoxContainer.new()
	var sp_lbl := Label.new()
	sp_lbl.text = "X Spacing:"
	sp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacing_row.add_child(sp_lbl)
	_spacing_spin = SpinBox.new()
	_spacing_spin.min_value = 0.0
	_spacing_spin.max_value = 100.0
	_spacing_spin.step = 0.5
	_spacing_spin.value = 3.0
	_spacing_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacing_row.add_child(_spacing_spin)
	vbox.add_child(spacing_row)

	vbox.add_child(HSeparator.new())

	# Process button
	var btn := Button.new()
	btn.text = "Process"
	btn.pressed.connect(_on_batch_process)
	vbox.add_child(btn)

	vbox.add_child(HSeparator.new())

	# Log
	vbox.add_child(_label("Log"))
	_batch_log = _make_log()
	vbox.add_child(_batch_log)

	var clear := Button.new()
	clear.text = "Clear Log"
	clear.pressed.connect(func() -> void: _batch_log.clear())
	vbox.add_child(clear)

	return scroll


# ── Mesh Splitter Tab ─────────────────────────────────────────

func _build_splitter_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Mesh Splitter"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Description
	var desc := Label.new()
	desc.text = "Split a GLB/GLTF into individual scenes.\nEach mesh child becomes its own .tscn."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	# Source file
	vbox.add_child(_label("Source GLB / GLTF"))
	_split_input = LineEdit.new()
	_split_input.placeholder_text = "res://characters/hero.glb"
	var split_src_row := _path_row(_split_input, "_on_browse_split_file")
	vbox.add_child(split_src_row)

	# Output folder
	vbox.add_child(_label("Output Folder"))
	_split_out_input = LineEdit.new()
	_split_out_input.text = "res://parts/"
	_split_out_input.placeholder_text = "res://parts/"
	var split_out_row := _path_row(_split_out_input, "_on_browse_split_out")
	vbox.add_child(split_out_row)

	vbox.add_child(HSeparator.new())

	# Split button
	var btn := Button.new()
	btn.text = "Split Meshes"
	btn.pressed.connect(_on_split_process)
	vbox.add_child(btn)

	vbox.add_child(HSeparator.new())

	# Log
	vbox.add_child(_label("Log"))
	_split_log = _make_log()
	vbox.add_child(_split_log)

	var clear := Button.new()
	clear.text = "Clear Log"
	clear.pressed.connect(func() -> void: _split_log.clear())
	vbox.add_child(clear)

	return scroll


# ══════════════════════════════════════════════════════════════
# FILE DIALOGS
# ══════════════════════════════════════════════════════════════

func _build_dialogs() -> void:
	var base: Control = EditorInterface.get_base_control()

	# Folder dialogs
	_src_dialog = _make_dir_dialog("Select Source Folder")
	_src_dialog.dir_selected.connect(func(d: String) -> void: _src_input.text = d)
	base.add_child(_src_dialog)

	_out_dialog = _make_dir_dialog("Select Output Folder")
	_out_dialog.dir_selected.connect(func(d: String) -> void: _out_input.text = d)
	base.add_child(_out_dialog)

	_split_out_dialog = _make_dir_dialog("Select Split Output Folder")
	_split_out_dialog.dir_selected.connect(func(d: String) -> void: _split_out_input.text = d)
	base.add_child(_split_out_dialog)

	# File dialog for splitter source
	_split_file_dialog = EditorFileDialog.new()
	_split_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_split_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_split_file_dialog.title = "Select GLB / GLTF File"
	_split_file_dialog.add_filter("*.glb", "GLB Files")
	_split_file_dialog.add_filter("*.gltf", "GLTF Files")
	_split_file_dialog.file_selected.connect(func(f: String) -> void: _split_input.text = f)
	base.add_child(_split_file_dialog)


func _make_dir_dialog(title_text: String) -> EditorFileDialog:
	var d := EditorFileDialog.new()
	d.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	d.access = EditorFileDialog.ACCESS_RESOURCES
	d.title = title_text
	return d


# ══════════════════════════════════════════════════════════════
# CALLBACKS
# ══════════════════════════════════════════════════════════════

func _on_browse_src() -> void:
	_src_dialog.current_dir = _src_input.text
	_src_dialog.popup_centered(Vector2i(800, 500))

func _on_browse_out() -> void:
	_out_dialog.current_dir = _out_input.text
	_out_dialog.popup_centered(Vector2i(800, 500))

func _on_browse_split_file() -> void:
	var dir: String = _split_input.text.get_base_dir()
	if dir.is_empty():
		dir = "res://"
	_split_file_dialog.current_dir = dir
	_split_file_dialog.popup_centered(Vector2i(800, 500))

func _on_browse_split_out() -> void:
	_split_out_dialog.current_dir = _split_out_input.text
	_split_out_dialog.popup_centered(Vector2i(800, 500))


func _on_batch_process() -> void:
	_batch_log.clear()
	_batch_log.append_text("[b]Asset Forge — Batch Processing...[/b]\n\n")

	if _src_input.text.strip_edges().is_empty():
		_batch_log.append_text("[color=red]✗ Source folder is empty[/color]\n")
		return
	if _out_input.text.strip_edges().is_empty():
		_batch_log.append_text("[color=red]✗ Output folder is empty[/color]\n")
		return

	var config := {
		"source_folder": _src_input.text.strip_edges(),
		"output_folder": _out_input.text.strip_edges(),
		"scenes_subdir": _scenes_input.text.strip_edges(),
		"materials_subdir": _mats_input.text.strip_edges(),
		"meshlib_subdir": _meshlib_input.text.strip_edges(),
		"extract_materials": _extract_mats_cb.button_pressed,
		"generate_meshlib": _gen_meshlib_cb.button_pressed,
		"recursive": _recursive_cb.button_pressed,
		"spacing_x": _spacing_spin.value,
	}

	var proc: RefCounted = BatchProcessor.new()
	proc.process(config)
	for msg: String in proc.log_messages:
		_batch_log.append_text(msg + "\n")
	_batch_log.append_text("\n[b]Done.[/b]\n")
	EditorInterface.get_resource_filesystem().scan()


func _on_split_process() -> void:
	_split_log.clear()
	_split_log.append_text("[b]Asset Forge — Mesh Splitter...[/b]\n\n")

	var src: String = _split_input.text.strip_edges()
	var out: String = _split_out_input.text.strip_edges()

	if src.is_empty():
		_split_log.append_text("[color=red]✗ No source file selected[/color]\n")
		return
	if out.is_empty():
		_split_log.append_text("[color=red]✗ No output folder set[/color]\n")
		return

	var splitter: RefCounted = MeshSplitter.new()
	splitter.split(src, out)
	for msg: String in splitter.log_messages:
		_split_log.append_text(msg + "\n")
	_split_log.append_text("\n[b]Done.[/b]\n")
	EditorInterface.get_resource_filesystem().scan()


# ══════════════════════════════════════════════════════════════
# UI HELPERS
# ══════════════════════════════════════════════════════════════

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _path_row(input: LineEdit, callback_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var btn := Button.new()
	btn.text = "..."
	btn.custom_minimum_size = Vector2(40, 0)
	btn.pressed.connect(Callable(self, callback_name))
	row.add_child(btn)
	return row


func _setting_row(parent: Control, label_text: String, default_val: String) -> LineEdit:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(lbl)
	var input := LineEdit.new()
	input.text = default_val
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	parent.add_child(row)
	return input


func _make_log() -> RichTextLabel:
	var log_box := RichTextLabel.new()
	log_box.custom_minimum_size = Vector2(0, 180)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.selection_enabled = true
	return log_box
