# Educator-facing pack authoring tool - a first-class feature (marketplace/
# revenue-share path), not a dev tool. Robust-but-not-pretty: validation
# reuses ContentPackLoader.validate_pack() (same rules the game itself
# enforces at load time), and Play-test saves first so scene changes never
# lose in-progress edits.
extends Control

const LANE_COUNT := 3
const MAX_DIFFICULTY := 4

@onready var pack_list: ItemList = $Scroll/VBox/PackList
@onready var pack_id_edit: LineEdit = $Scroll/VBox/PackIdEdit
@onready var subject_edit: LineEdit = $Scroll/VBox/SubjectEdit
@onready var grade_spin: SpinBox = $Scroll/VBox/GradeRow/GradeSpin
@onready var question_list: ItemList = $Scroll/VBox/QuestionList
@onready var question_text_edit: LineEdit = $Scroll/VBox/QuestionTextEdit
@onready var difficulty_spin: SpinBox = $Scroll/VBox/DifficultyRow/DifficultySpin
@onready var validation_label: Label = $Scroll/VBox/ValidationLabel
@onready var import_dialog: FileDialog = $ImportDialog
@onready var export_dialog: FileDialog = $ExportDialog
@onready var back_button: Button = $BackButton
@onready var new_button: Button = $Scroll/VBox/PackButtons/NewButton
@onready var duplicate_button: Button = $Scroll/VBox/PackButtons/DuplicateButton
@onready var delete_button: Button = $Scroll/VBox/PackButtons/DeleteButton
@onready var add_question_button: Button = $Scroll/VBox/QuestionButtons/AddButton
@onready var remove_question_button: Button = $Scroll/VBox/QuestionButtons/RemoveButton
@onready var save_button: Button = $Scroll/VBox/ActionButtons/SaveButton
@onready var play_test_button: Button = $Scroll/VBox/ActionButtons/PlayTestButton
@onready var import_button: Button = $Scroll/VBox/ActionButtons/ImportButton
@onready var export_button: Button = $Scroll/VBox/ActionButtons/ExportButton

var _answer_edits: Array[LineEdit] = []
var _answer_checks: Array[CheckBox] = []
var _correct_button_group := ButtonGroup.new()

var _packs: Dictionary = {}
var _current_pack: Dictionary = {}
var _current_question_index: int = -1
var _editing_pack_id: String = ""

func _ready() -> void:
	for i in LANE_COUNT:
		var row: Node = get_node("Scroll/VBox/AnswerRow%d" % i)
		var edit := row.get_node("AnswerEdit") as LineEdit
		var check := row.get_node("CorrectCheck") as CheckBox
		check.button_group = _correct_button_group
		_answer_edits.append(edit)
		_answer_checks.append(check)

	grade_spin.min_value = 0
	grade_spin.max_value = 12
	difficulty_spin.min_value = 0
	difficulty_spin.max_value = MAX_DIFFICULTY

	back_button.pressed.connect(_on_back_pressed)
	pack_list.item_selected.connect(_on_pack_selected)
	new_button.pressed.connect(_on_new_pack_pressed)
	duplicate_button.pressed.connect(_on_duplicate_pack_pressed)
	delete_button.pressed.connect(_on_delete_pack_pressed)
	question_list.item_selected.connect(_on_question_selected)
	add_question_button.pressed.connect(_on_add_question_pressed)
	remove_question_button.pressed.connect(_on_remove_question_pressed)
	save_button.pressed.connect(_on_save_pressed)
	play_test_button.pressed.connect(_on_play_test_pressed)
	import_button.pressed.connect(_on_import_pressed)
	export_button.pressed.connect(_on_export_pressed)

	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
	import_dialog.file_selected.connect(_on_import_file_selected)
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.json ; JSON Files"])
	export_dialog.file_selected.connect(_on_export_file_selected)

	# FileDialog still runs on Web, but can only browse the sandboxed
	# user:// virtual filesystem there, not the visitor's real disk - a
	# confusing, semantically-wrong "import" if left enabled.
	if OS.get_name() == "Web":
		import_button.disabled = true
		import_button.tooltip_text = "Needs a browser file API (JavaScriptBridge) - TODO"
		export_button.disabled = true
		export_button.tooltip_text = "Needs a browser file API (JavaScriptBridge) - TODO"

	_refresh_pack_list()
	_new_pack()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _refresh_pack_list() -> void:
	_packs = ContentPackLoader.load_merged_packs()
	pack_list.clear()
	var ids: Array = _packs.keys()
	ids.sort()
	for pack_id in ids:
		pack_list.add_item(String(pack_id))

func _on_pack_selected(index: int) -> void:
	var pack_id: String = pack_list.get_item_text(index)
	var pack: Variant = _packs.get(pack_id, {})
	if typeof(pack) != TYPE_DICTIONARY:
		return
	_load_pack_into_ui((pack as Dictionary).duplicate(true), pack_id)

func _on_new_pack_pressed() -> void:
	_new_pack()

func _new_pack() -> void:
	_load_pack_into_ui({"id": "", "subject": "", "grade": 0, "items": []}, "")

func _on_duplicate_pack_pressed() -> void:
	_save_question_from_ui()
	var copy: Dictionary = _collect_pack_from_ui().duplicate(true)
	var base_id: String = String(copy.get("id", "pack"))
	if base_id.is_empty():
		base_id = "pack"
	var new_id: String = base_id + "_copy"
	var suffix := 2
	while _packs.has(new_id):
		new_id = "%s_copy%d" % [base_id, suffix]
		suffix += 1
	copy["id"] = new_id
	_load_pack_into_ui(copy, "")

func _on_delete_pack_pressed() -> void:
	var pack_id: String = String(_current_pack.get("id", ""))
	if pack_id.is_empty() or not ContentPackLoader.is_user_pack(pack_id):
		validation_label.text = "Only authored packs can be deleted (bundled packs can only be overridden)."
		validation_label.visible = true
		return
	ContentPackLoader.delete_user_pack(pack_id)
	_refresh_pack_list()
	_new_pack()

func _load_pack_into_ui(pack: Dictionary, editing_id: String) -> void:
	_current_pack = pack
	_editing_pack_id = editing_id
	pack_id_edit.text = String(pack.get("id", ""))
	subject_edit.text = String(pack.get("subject", ""))
	grade_spin.value = float(int(pack.get("grade", 0)))
	_current_question_index = -1
	_refresh_question_list()
	var items: Array = _current_pack_items()
	if not items.is_empty():
		question_list.select(0)
		_on_question_selected(0)
	else:
		_clear_question_ui()
	validation_label.visible = false

func _current_pack_items() -> Array:
	var items: Variant = _current_pack.get("items", [])
	if typeof(items) != TYPE_ARRAY:
		items = []
		_current_pack["items"] = items
	return items as Array

func _refresh_question_list() -> void:
	question_list.clear()
	for item_variant in _current_pack_items():
		var text := "(empty)"
		if typeof(item_variant) == TYPE_DICTIONARY:
			var question: String = String((item_variant as Dictionary).get("question", ""))
			text = question if not question.is_empty() else "(empty)"
		question_list.add_item(text)

func _on_question_selected(index: int) -> void:
	_save_question_from_ui()
	_current_question_index = index
	var items: Array = _current_pack_items()
	if index < 0 or index >= items.size() or typeof(items[index]) != TYPE_DICTIONARY:
		_clear_question_ui()
		return
	var item: Dictionary = items[index] as Dictionary
	question_text_edit.text = String(item.get("question", ""))
	var answers: Variant = item.get("answers", [])
	var answer_array: Array = answers as Array if typeof(answers) == TYPE_ARRAY else []
	var correct_index: int = int(item.get("correct_index", -1))
	for i in LANE_COUNT:
		_answer_edits[i].text = String(answer_array[i]) if i < answer_array.size() else ""
		_answer_checks[i].button_pressed = (i == correct_index)
	difficulty_spin.value = float(int(item.get("difficulty", 0)))

func _clear_question_ui() -> void:
	question_text_edit.text = ""
	for i in LANE_COUNT:
		_answer_edits[i].text = ""
		_answer_checks[i].button_pressed = false
	difficulty_spin.value = 0

func _save_question_from_ui() -> void:
	if _current_question_index < 0:
		return
	var items: Array = _current_pack_items()
	if _current_question_index >= items.size():
		return
	var answers: Array = []
	var correct_index := -1
	for i in LANE_COUNT:
		answers.append(_answer_edits[i].text)
		if _answer_checks[i].button_pressed:
			correct_index = i
	items[_current_question_index] = {
		"question": question_text_edit.text,
		"answers": answers,
		"correct_index": correct_index,
		"difficulty": int(difficulty_spin.value),
	}

func _on_add_question_pressed() -> void:
	_save_question_from_ui()
	var items: Array = _current_pack_items()
	items.append({"question": "", "answers": ["", "", ""], "correct_index": -1, "difficulty": 0})
	_refresh_question_list()
	question_list.select(items.size() - 1)
	_on_question_selected(items.size() - 1)

func _on_remove_question_pressed() -> void:
	var items: Array = _current_pack_items()
	if _current_question_index < 0 or _current_question_index >= items.size():
		return
	items.remove_at(_current_question_index)
	_current_question_index = -1
	_refresh_question_list()
	if not items.is_empty():
		question_list.select(0)
		_on_question_selected(0)
	else:
		_clear_question_ui()

func _collect_pack_from_ui() -> Dictionary:
	_save_question_from_ui()
	_current_pack["id"] = pack_id_edit.text.strip_edges()
	_current_pack["subject"] = subject_edit.text.strip_edges()
	_current_pack["grade"] = int(grade_spin.value)
	return _current_pack

func _existing_ids_excluding_current() -> Array[String]:
	var ids: Array[String] = []
	for pack_id in _packs.keys():
		var id_string: String = String(pack_id)
		if id_string != _editing_pack_id:
			ids.append(id_string)
	return ids

func _validate_and_save() -> bool:
	var pack: Dictionary = _collect_pack_from_ui()
	var errors: Array[String] = ContentPackLoader.validate_pack(pack, LANE_COUNT, _existing_ids_excluding_current())
	if not errors.is_empty():
		validation_label.text = errors[0]
		validation_label.visible = true
		return false
	validation_label.visible = false
	ContentPackLoader.save_user_pack(pack)
	_editing_pack_id = String(pack.get("id", ""))
	return true

func _on_save_pressed() -> void:
	if not _validate_and_save():
		return
	_refresh_pack_list()
	var index: int = _find_pack_index(_editing_pack_id)
	if index >= 0:
		pack_list.select(index)

func _find_pack_index(pack_id: String) -> int:
	for i in pack_list.item_count:
		if pack_list.get_item_text(i) == pack_id:
			return i
	return -1

func _on_play_test_pressed() -> void:
	if not _validate_and_save():
		return
	GameSession.forced_pack_id = _editing_pack_id
	get_tree().change_scene_to_file("res://game/main.tscn")

func _on_import_pressed() -> void:
	import_dialog.popup_centered(Vector2i(480, 400))

func _on_export_pressed() -> void:
	export_dialog.popup_centered(Vector2i(480, 400))

func _on_import_file_selected(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		validation_label.text = "Could not read the selected file."
		validation_label.visible = true
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		validation_label.text = "Selected file is not a valid pack (expected a JSON object)."
		validation_label.visible = true
		return
	_load_pack_into_ui(parsed as Dictionary, "")

func _on_export_file_selected(path: String) -> void:
	var pack: Dictionary = _collect_pack_from_ui()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(pack, "\t"))
	file.close()
