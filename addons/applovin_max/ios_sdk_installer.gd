@tool
extends Node
## Downloads the official AppLovin iOS SDK into res://ios/plugins/applovin_max/.
## (Project > Tools > "AppLovin MAX: Download iOS SDK")

const DOWNLOAD_URL := "https://artifacts.applovin.com/ios/com/applovin/applovin-sdk/applovin-ios-sdk-%s.zip"
const DESTINATION_DIR := "res://ios/plugins/applovin_max"
const FRAMEWORK_NAME := "AppLovinSDK.xcframework"
const TEMP_ZIP := "user://applovin-ios-sdk.zip"

## Emitted when the installation ends; error_message is empty on success.
signal finished(error_message: String)

var _http: HTTPRequest
var _version := ""


func install(version: String) -> void:
	if _http:
		push_warning("[AppLovin MAX] The iOS SDK download is already in progress.")
		return
	_version = version
	_http = HTTPRequest.new()
	_http.download_file = ProjectSettings.globalize_path(TEMP_ZIP)
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	print("[AppLovin MAX] Downloading AppLovin iOS SDK %s..." % version)
	var err := _http.request(DOWNLOAD_URL % version)
	if err != OK:
		_finish("Could not start the download (error %d)." % err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish("Download failed (result %d, HTTP %d)." % [result, response_code])
		return
	var err := _extract(ProjectSettings.globalize_path(TEMP_ZIP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_ZIP))
	if err != OK:
		_finish("Could not extract %s (error %d)." % [FRAMEWORK_NAME, err])
		return
	_finish("")


func _extract(zip_path: String) -> Error:
	var zip := ZIPReader.new()
	var err := zip.open(zip_path)
	if err != OK:
		return err

	var destination := DESTINATION_DIR.path_join(FRAMEWORK_NAME)
	_remove_recursive(ProjectSettings.globalize_path(destination))

	var marker := "/" + FRAMEWORK_NAME + "/"
	var extracted := 0
	for path in zip.get_files():
		if path.begins_with("__MACOSX") or not path.contains(marker):
			continue
		var relative := path.substr(path.find(marker) + marker.length())
		var target := ProjectSettings.globalize_path(destination.path_join(relative))
		if path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(target)
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			zip.close()
			return FileAccess.get_open_error()
		file.store_buffer(zip.read_file(path))
		file.close()
		extracted += 1
	zip.close()

	if extracted == 0:
		return ERR_FILE_NOT_FOUND
	# Keeps the editor from importing the SDK's resource files (images, etc.).
	FileAccess.open(ProjectSettings.globalize_path(destination.path_join(".gdignore")), FileAccess.WRITE)
	var version_file := FileAccess.open(ProjectSettings.globalize_path(DESTINATION_DIR.path_join("AppLovinSDK.version")), FileAccess.WRITE)
	if version_file:
		version_file.store_line(_version)
	return OK


func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _finish(error_message: String) -> void:
	if _http:
		_http.queue_free()
		_http = null
	if error_message.is_empty():
		print("[AppLovin MAX] AppLovin iOS SDK %s installed in %s." % [_version, DESTINATION_DIR.path_join(FRAMEWORK_NAME)])
	else:
		push_error("[AppLovin MAX] " + error_message)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	finished.emit(error_message)
