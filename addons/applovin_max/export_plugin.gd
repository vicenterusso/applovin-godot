@tool
extends EditorExportPlugin
## Wires the AppLovin MAX plugin into Android and iOS exports.
##
## Android: adds the plugin AAR (Godot Android plugin v2), the AppLovin SDK and any
## mediation adapters as Gradle dependencies. Requires "Use Gradle Build".
## iOS: the native part is a regular Godot iOS plugin (res://ios/plugins/applovin_max/
## applovin_max.gdip, enabled in the export preset under "Plugins"). This script adds
## AppLovinSDK.xcframework, optional adapter frameworks and the Info.plist entries.

const PLUGIN_NAME := "AppLovinMax"
const IOS_PLUGIN_DIR := "res://ios/plugins/applovin_max"
const IOS_EXTRA_FRAMEWORKS_DIR := IOS_PLUGIN_DIR + "/frameworks"
const ANDROID_AAR_DEBUG := "res://addons/applovin_max/bin/android/applovin_max-debug.aar"
const ANDROID_AAR_RELEASE := "res://addons/applovin_max/bin/android/applovin_max-release.aar"

const DEFAULT_ANDROID_SDK_VERSION := "13.6.4"
const DEFAULT_IOS_SDK_VERSION := "13.6.4"
const DEFAULT_TRACKING_DESCRIPTION := "This identifier will be used to deliver personalized ads to you."
# AppLovin's own SKAdNetwork ID. Add the IDs of your mediated networks in the export preset.
const DEFAULT_SKADNETWORK_IDS := ["ludvb6z3bs.skadnetwork"]

const OPT_ANDROID_ENABLED := "applovin_max/android/enabled"
const OPT_ANDROID_SDK_VERSION := "applovin_max/android/sdk_version"
const OPT_ANDROID_DEPENDENCIES := "applovin_max/android/mediation_dependencies"
const OPT_ANDROID_MAVEN_REPOS := "applovin_max/android/maven_repositories"
const OPT_ANDROID_ADMOB_APP_ID := "applovin_max/android/admob_app_id"
const OPT_IOS_TRACKING_DESCRIPTION := "applovin_max/ios/user_tracking_usage_description"
const OPT_IOS_SKADNETWORK_IDS := "applovin_max/ios/skadnetwork_ids"
const OPT_IOS_ADMOB_APP_ID := "applovin_max/ios/admob_app_id"


func _get_name() -> String:
	return PLUGIN_NAME


func _supports_platform(platform: EditorExportPlatform) -> bool:
	var os_name := platform.get_os_name()
	return os_name == "Android" or os_name == "iOS"


func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	match platform.get_os_name():
		"Android":
			options.append(_option(OPT_ANDROID_ENABLED, TYPE_BOOL, true))
			options.append(_option(OPT_ANDROID_SDK_VERSION, TYPE_STRING, DEFAULT_ANDROID_SDK_VERSION))
			options.append(_option(OPT_ANDROID_DEPENDENCIES, TYPE_PACKED_STRING_ARRAY, PackedStringArray()))
			options.append(_option(OPT_ANDROID_MAVEN_REPOS, TYPE_PACKED_STRING_ARRAY, PackedStringArray()))
			options.append(_option(OPT_ANDROID_ADMOB_APP_ID, TYPE_STRING, ""))
		"iOS":
			options.append(_option(OPT_IOS_TRACKING_DESCRIPTION, TYPE_STRING, DEFAULT_TRACKING_DESCRIPTION))
			options.append(_option(OPT_IOS_SKADNETWORK_IDS, TYPE_PACKED_STRING_ARRAY, PackedStringArray(DEFAULT_SKADNETWORK_IDS)))
			options.append(_option(OPT_IOS_ADMOB_APP_ID, TYPE_STRING, ""))
	return options


func _get_export_option_warning(platform: EditorExportPlatform, option: String) -> String:
	if platform.get_os_name() == "Android" and option == OPT_ANDROID_ENABLED:
		if _android_enabled() and not bool(_get_opt("gradle_build/use_gradle_build", false)):
			return "AppLovin MAX requires \"Use Gradle Build\" (gradle_build/use_gradle_build)."
	if platform.get_os_name() == "iOS" and option == OPT_IOS_TRACKING_DESCRIPTION:
		if _ios_enabled() and not DirAccess.dir_exists_absolute(IOS_PLUGIN_DIR.path_join("AppLovinSDK.xcframework")):
			return "AppLovinSDK.xcframework is missing. Use Project > Tools > \"AppLovin MAX: Download iOS SDK\"."
	return ""


# region Android

func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _android_enabled():
		return PackedStringArray()
	return PackedStringArray([ANDROID_AAR_DEBUG if debug else ANDROID_AAR_RELEASE])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not _android_enabled():
		return PackedStringArray()
	var version := str(_get_opt(OPT_ANDROID_SDK_VERSION, DEFAULT_ANDROID_SDK_VERSION)).strip_edges()
	if version.is_empty():
		version = DEFAULT_ANDROID_SDK_VERSION
	var dependencies := PackedStringArray(["com.applovin:applovin-sdk:" + version])
	for dependency in _get_opt(OPT_ANDROID_DEPENDENCIES, PackedStringArray()):
		if not str(dependency).strip_edges().is_empty():
			dependencies.append(str(dependency).strip_edges())
	return dependencies


func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not _android_enabled():
		return PackedStringArray()
	var repos := PackedStringArray()
	for repo in _get_opt(OPT_ANDROID_MAVEN_REPOS, PackedStringArray()):
		if not str(repo).strip_edges().is_empty():
			repos.append(str(repo).strip_edges())
	return repos


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	if not _android_enabled():
		return ""
	var admob_app_id := str(_get_opt(OPT_ANDROID_ADMOB_APP_ID, "")).strip_edges()
	if admob_app_id.is_empty():
		return ""
	return "<meta-data android:name=\"com.google.android.gms.ads.APPLICATION_ID\" android:value=\"%s\" />\n" % admob_app_id.xml_escape(true)


func _android_enabled() -> bool:
	return bool(_get_opt(OPT_ANDROID_ENABLED, true))

# endregion

# region iOS

func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not features.has("ios") or not _ios_enabled():
		return

	var sdk_path := IOS_PLUGIN_DIR.path_join("AppLovinSDK.xcframework")
	if not DirAccess.dir_exists_absolute(sdk_path):
		push_error("[AppLovin MAX] %s not found. Use Project > Tools > \"AppLovin MAX: Download iOS SDK\"." % sdk_path)
	else:
		_add_ios_framework(sdk_path)

	# Mediation adapters and their network SDKs (.xcframework / .framework).
	if DirAccess.dir_exists_absolute(IOS_EXTRA_FRAMEWORKS_DIR):
		for entry in DirAccess.get_directories_at(IOS_EXTRA_FRAMEWORKS_DIR):
			if entry.ends_with(".xcframework") or entry.ends_with(".framework"):
				_add_ios_framework(IOS_EXTRA_FRAMEWORKS_DIR.path_join(entry))

	var plist := ""
	var tracking_description := str(_get_opt(OPT_IOS_TRACKING_DESCRIPTION, DEFAULT_TRACKING_DESCRIPTION)).strip_edges()
	if not tracking_description.is_empty():
		plist += "<key>NSUserTrackingUsageDescription</key>\n<string>%s</string>\n" % tracking_description.xml_escape()

	var skadnetwork_ids := PackedStringArray()
	for id in _get_opt(OPT_IOS_SKADNETWORK_IDS, PackedStringArray(DEFAULT_SKADNETWORK_IDS)):
		var clean := str(id).strip_edges().to_lower()
		if not clean.is_empty() and not skadnetwork_ids.has(clean):
			skadnetwork_ids.append(clean)
	if not skadnetwork_ids.is_empty():
		plist += "<key>SKAdNetworkItems</key>\n<array>\n"
		for id in skadnetwork_ids:
			plist += "\t<dict>\n\t\t<key>SKAdNetworkIdentifier</key>\n\t\t<string>%s</string>\n\t</dict>\n" % id.xml_escape()
		plist += "</array>\n"

	var admob_app_id := str(_get_opt(OPT_IOS_ADMOB_APP_ID, "")).strip_edges()
	if not admob_app_id.is_empty():
		plist += "<key>GADApplicationIdentifier</key>\n<string>%s</string>\n" % admob_app_id.xml_escape()

	if not plist.is_empty():
		_ios_call("plist_content", plist)


func _ios_enabled() -> bool:
	return bool(_get_opt("plugins/" + PLUGIN_NAME, false))


## Links static frameworks (copying their resource bundles into the app) and embeds
## dynamic ones. Godot cannot tell a static .framework from a dynamic one by itself.
func _add_ios_framework(framework_path: String) -> void:
	var binary := _find_device_binary(framework_path)
	if binary.is_empty():
		push_warning("[AppLovin MAX] Could not inspect %s; linking it without embedding." % framework_path)
		_ios_call("framework", framework_path)
		return

	if binary.ends_with(".a") or _is_static_binary(binary):
		_ios_call("framework", framework_path)
		var framework_dir := binary.get_base_dir()
		if framework_dir.ends_with(".framework"):
			for entry in DirAccess.get_directories_at(framework_dir):
				if entry.ends_with(".bundle"):
					_ios_call("bundle_file", framework_dir.path_join(entry))
	else:
		_ios_call("embedded_framework", framework_path)


## Returns the binary of the device (non-simulator) slice of a framework / xcframework.
func _find_device_binary(framework_path: String) -> String:
	var framework_dir := framework_path
	if framework_path.ends_with(".xcframework"):
		framework_dir = ""
		for slice in DirAccess.get_directories_at(framework_path):
			if slice.begins_with("ios-") and not slice.contains("simulator"):
				var slice_path := framework_path.path_join(slice)
				for entry in DirAccess.get_directories_at(slice_path):
					if entry.ends_with(".framework"):
						framework_dir = slice_path.path_join(entry)
				if framework_dir.is_empty():
					for file in DirAccess.get_files_at(slice_path):
						if file.ends_with(".a"):
							return slice_path.path_join(file)
				break
	if framework_dir.is_empty():
		return ""
	var binary := framework_dir.path_join(framework_dir.get_file().get_basename())
	return binary if FileAccess.file_exists(binary) else ""


func _is_static_binary(binary_path: String) -> bool:
	var file := FileAccess.open(binary_path, FileAccess.READ)
	if file == null:
		return false
	var header := file.get_buffer(32)
	if header.size() < 16:
		return false
	# Static library archive: "!<arch>\n".
	if header.slice(0, 8).get_string_from_ascii() == "!<arch>\n":
		return true
	# Universal binary (big-endian header): inspect the first architecture.
	if header[0] == 0xCA and header[1] == 0xFE and header[2] == 0xBA and header[3] == 0xBE:
		var offset := (header[16] << 24) | (header[17] << 16) | (header[18] << 8) | header[19]
		file.seek(offset)
		header = file.get_buffer(16)
		if header.size() < 16:
			return false
		if header.slice(0, 8).get_string_from_ascii() == "!<arch>\n":
			return true
	# Thin Mach-O (little-endian): file type 6 is MH_DYLIB, anything else is linked statically.
	var file_type := header.decode_u32(12)
	return file_type != 6


func _ios_call(kind: String, value: String) -> void:
	var method := "add_apple_embedded_platform_" + kind  # Godot 4.5+
	if not has_method(method):
		method = "add_ios_" + kind
	call(method, value)

# endregion


func _get_opt(name: String, default_value: Variant) -> Variant:
	if has_method("get_export_preset") and call("get_export_preset") == null:
		return default_value
	var value: Variant = get_option(name)
	return default_value if value == null else value


static func _option(name: String, type: int, default_value: Variant) -> Dictionary:
	return {
		"option": {"name": name, "type": type},
		"default_value": default_value,
	}
