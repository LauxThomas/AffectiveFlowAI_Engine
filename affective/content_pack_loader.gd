# Knowledge Pack loader/merger. Bundled packs (res://content/) are listed via
# a committed manifest.json rather than DirAccess, since listing plain
# non-resource files inside an exported PCK/Web build is unreliable across
# Godot versions - reading exact known paths via FileAccess is not. Authored
# packs (user://content/) use real DirAccess, which is reliable/OS-backed
# (IDBFS-persisted on Web too).
#
# Merge semantics: merge key = pack id, whole-pack replace (not item-level
# merge). An authored pack sharing a bundled pack's id fully overrides it;
# a new id simply extends the set.
extends RefCounted
class_name ContentPackLoader

const MANIFEST_PATH := "res://content/manifest.json"
const BUNDLED_DIR := "res://content/"
const USER_CONTENT_DIR := "user://content/"

static func load_merged_packs() -> Dictionary:
	var packs: Dictionary = {}
	for path in _list_bundled_paths():
		var pack: Dictionary = _load_pack_file(path)
		if not pack.is_empty():
			packs[String(pack.get("id", ""))] = pack
	for path in _list_user_paths():
		var pack: Dictionary = _load_pack_file(path)
		if not pack.is_empty():
			packs[String(pack.get("id", ""))] = pack   # override/extend
	return packs

static func save_user_pack(pack: Dictionary) -> bool:
	var pack_id: String = String(pack.get("id", ""))
	if pack_id.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(USER_CONTENT_DIR)
	var file := FileAccess.open(USER_CONTENT_DIR + pack_id + ".json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(pack, "\t"))
	file.close()
	return true

# existing_ids is the set of OTHER packs' ids (exclude the pack's own prior
# id when re-validating an edit) - used for the "unique pack id" rule.
static func validate_pack(pack: Dictionary, lane_count: int, existing_ids: Array[String] = []) -> Array[String]:
	var errors: Array[String] = []
	var pack_id: String = String(pack.get("id", ""))
	if pack_id.is_empty():
		errors.append("Pack id must not be empty.")
	elif existing_ids.has(pack_id):
		errors.append("Pack id '%s' is already in use." % pack_id)

	var subject: String = String(pack.get("subject", ""))
	if subject.is_empty():
		errors.append("Subject must not be empty.")

	var items: Variant = pack.get("items", [])
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		errors.append("Pack must have at least one question.")
		return errors

	var index := 0
	for item_variant in (items as Array):
		index += 1
		if typeof(item_variant) != TYPE_DICTIONARY:
			errors.append("Question %d is malformed." % index)
			continue
		var item: Dictionary = item_variant as Dictionary
		var question: String = String(item.get("question", ""))
		if question.is_empty():
			errors.append("Question %d text must not be empty." % index)

		var answers: Variant = item.get("answers", [])
		if typeof(answers) != TYPE_ARRAY or (answers as Array).size() != lane_count:
			errors.append("Question %d must have exactly %d answers." % [index, lane_count])
		else:
			for answer in (answers as Array):
				if String(answer).is_empty():
					errors.append("Question %d has an empty answer." % index)
					break

		var correct_index: int = int(item.get("correct_index", -1))
		if correct_index < 0 or correct_index >= lane_count:
			errors.append("Question %d must mark exactly one correct answer." % index)

	return errors

static func _list_bundled_paths() -> Array[String]:
	var text: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var manifest: Dictionary = parsed as Dictionary
	var pack_ids: Variant = manifest.get("packs", [])
	var out: Array[String] = []
	if typeof(pack_ids) == TYPE_ARRAY:
		for pid in (pack_ids as Array):
			out.append(BUNDLED_DIR + String(pid) + ".json")
	return out

static func _list_user_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(USER_CONTENT_DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(USER_CONTENT_DIR)
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			out.append(USER_CONTENT_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return out

static func _load_pack_file(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary
