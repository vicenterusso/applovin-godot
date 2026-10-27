extends Node
## On-device integration test for the AppLovin MAX plugin.
##
## Exercises the whole chain GDScript -> AppLovinMax autoload -> native plugin -> AppLovin
## SDK -> native callbacks -> Godot signals. Every line is printed with the "[ALTEST]"
## prefix and appended to user://applovin_test_result.txt; the last line is
## "[ALTEST] RESULT PASS" or "[ALTEST] RESULT FAIL (<n>)". CI scripts wait for it.
##
## Values come from res://test_config.json (written by tests/prepare_project.sh). With a
## placeholder SDK key AppLovin answers ad requests with load errors, which still proves
## the callback path; with a real key and test devices ads may actually load.

const RESULT_FILE := "user://applovin_test_result.txt"
const SDK_INIT_TIMEOUT := 120.0
const AD_CALLBACK_TIMEOUT := 120.0

const COMMON_SIGNALS := [
	"sdk_initialized", "ad_loaded", "ad_load_failed", "ad_displayed", "ad_display_failed",
	"ad_clicked", "ad_hidden", "ad_revenue_paid", "ad_received_reward", "ad_expanded",
	"ad_collapsed", "cmp_flow_completed",
]
const IOS_ONLY_SIGNALS := ["tracking_authorization_completed"]
const NATIVE_METHODS := [
	"initialize", "is_initialized", "get_sdk_configuration", "get_sdk_version", "get_plugin_version",
	"show_mediation_debugger", "show_creative_debugger", "set_muted", "is_muted", "set_verbose_logging",
	"set_creative_debugger_enabled", "set_user_id", "set_extra_parameter", "set_has_user_consent",
	"has_user_consent", "is_user_consent_set", "set_do_not_sell", "is_do_not_sell", "has_supported_cmp",
	"show_cmp_for_existing_user", "request_tracking_authorization", "load_interstitial",
	"is_interstitial_ready", "show_interstitial", "set_interstitial_extra_parameter", "load_rewarded_ad",
	"is_rewarded_ad_ready", "show_rewarded_ad", "set_rewarded_ad_extra_parameter", "load_app_open_ad",
	"is_app_open_ad_ready", "show_app_open_ad", "set_app_open_ad_extra_parameter", "create_ad_view",
	"load_ad_view", "show_ad_view", "hide_ad_view", "destroy_ad_view", "set_ad_view_position",
	"set_ad_view_background_color", "set_ad_view_placement", "set_ad_view_custom_data",
	"set_ad_view_extra_parameter", "start_ad_view_auto_refresh", "stop_ad_view_auto_refresh",
	"get_ad_view_size",
]

var _config := {}
var _ids := {}
var _failures := 0
var _checks := 0
var _events: Array[Dictionary] = []


func _ready() -> void:
	var file := FileAccess.open(RESULT_FILE, FileAccess.WRITE)
	if file:
		file.close()
	_load_config()
	_record_signals()
	await _run()
	_log("SUMMARY %d checks, %d failed" % [_checks, _failures])
	_log("RESULT " + ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))


func _run() -> void:
	_log("platform=%s godot=%s" % [OS.get_name(), Engine.get_version_info().string])
	if not _check("native plugin singleton is available", AppLovinMax.is_available()):
		return

	_test_native_api()
	_test_settings()
	await _test_initialization()
	await _test_fullscreen("interstitial", "load_interstitial", "is_interstitial_ready", "set_interstitial_extra_parameter")
	await _test_fullscreen("rewarded", "load_rewarded_ad", "is_rewarded_ad_ready", "set_rewarded_ad_extra_parameter")
	await _test_fullscreen("app_open", "load_app_open_ad", "is_app_open_ad_ready", "set_app_open_ad_extra_parameter")
	await _test_ad_view("banner")
	await _test_ad_view("mrec")


func _test_native_api() -> void:
	var native := Engine.get_singleton(AppLovinMax.NATIVE_SINGLETON)
	var signals: Array = COMMON_SIGNALS.duplicate()
	if OS.get_name() == "iOS":
		signals.append_array(IOS_ONLY_SIGNALS)
	for signal_name in signals:
		_check("native signal '%s' is registered" % signal_name, native.has_signal(signal_name))
	# ClassDB-bound methods (iOS) are visible to has_method(); Android plugin methods are
	# resolved through JNI and are exercised by the calls below instead.
	if OS.get_name() == "iOS":
		for method in NATIVE_METHODS:
			_check("native method '%s' is bound" % method, native.has_method(method))

	var sdk_version := AppLovinMax.get_sdk_version()
	_log("AppLovin SDK version: " + sdk_version)
	_check("SDK version is 13.x or newer", sdk_version.split(".")[0].to_int() >= 13)
	_check("plugin version is reported", not AppLovinMax.get_plugin_version().is_empty())


func _test_settings() -> void:
	AppLovinMax.set_has_user_consent(true)
	_check("has_user_consent() after set_has_user_consent(true)", AppLovinMax.has_user_consent())
	_check("is_user_consent_set()", AppLovinMax.is_user_consent_set())
	AppLovinMax.set_has_user_consent(false)
	_check("has_user_consent() after set_has_user_consent(false)", not AppLovinMax.has_user_consent())

	AppLovinMax.set_do_not_sell(true)
	_check("is_do_not_sell() after set_do_not_sell(true)", AppLovinMax.is_do_not_sell())
	AppLovinMax.set_do_not_sell(false)
	_check("is_do_not_sell() after set_do_not_sell(false)", not AppLovinMax.is_do_not_sell())

	AppLovinMax.set_muted(true)
	_check("is_muted() after set_muted(true)", AppLovinMax.is_muted())
	AppLovinMax.set_muted(false)
	_check("is_muted() after set_muted(false)", not AppLovinMax.is_muted())

	AppLovinMax.set_verbose_logging(true)
	AppLovinMax.set_creative_debugger_enabled(false)
	AppLovinMax.set_user_id("ci-user")
	AppLovinMax.set_extra_parameter("ci_extra_key", "ci_extra_value")
	_check("has_supported_cmp() returns a bool", typeof(AppLovinMax.has_supported_cmp()) == TYPE_BOOL)


func _test_initialization() -> void:
	_check("is_initialized() is false before initialize()", not AppLovinMax.is_initialized())
	AppLovinMax.initialize(str(_config.get("sdk_key", "")), {
		"verbose_logging": true,
		"has_user_consent": true,
		"do_not_sell": false,
		"user_id": "ci-user",
		"test_device_advertising_ids": _config.get("test_device_advertising_ids", []),
		"extra_parameters": {"ci_init_key": "ci_init_value"},
	})
	var event := await _wait_event(["sdk_initialized"], "", SDK_INIT_TIMEOUT)
	if not _check("sdk_initialized signal received", not event.is_empty()):
		return
	var sdk_configuration: Dictionary = event["args"][0]
	_log("sdk_configuration: " + str(sdk_configuration))
	for key in ["country_code", "consent_flow_user_geography", "is_test_mode_enabled", "app_tracking_status"]:
		_check("sdk_configuration has '%s'" % key, sdk_configuration.has(key))
	_check("is_initialized() is true after sdk_initialized", AppLovinMax.is_initialized())
	_check("get_sdk_configuration() is filled", AppLovinMax.get_sdk_configuration().has("country_code"))
	_check("initialize() kept has_user_consent", AppLovinMax.has_user_consent())

	# A second initialize() must not re-initialize, but report the existing configuration.
	_events.clear()
	AppLovinMax.initialize(str(_config.get("sdk_key", "")))
	event = await _wait_event(["sdk_initialized"], "", 15.0)
	_check("second initialize() re-emits sdk_initialized", not event.is_empty())


func _test_fullscreen(kind: String, load_method: String, ready_method: String, extra_method: String) -> void:
	var ad_unit_id: String = _ids[kind]
	_events.clear()
	AppLovinMax.call(extra_method, ad_unit_id, "ci_key", "ci_value")
	_check("%s is not ready before loading" % kind, not AppLovinMax.call(ready_method, ad_unit_id))
	AppLovinMax.call(load_method, ad_unit_id)
	var event := await _wait_event(["ad_loaded", "ad_load_failed"], ad_unit_id, AD_CALLBACK_TIMEOUT)
	if not _check("%s load callback received" % kind, not event.is_empty()):
		return
	_check_callback(kind, event)
	_check("%s readiness matches the callback" % kind, AppLovinMax.call(ready_method, ad_unit_id) == (event["name"] == "ad_loaded"))


func _test_ad_view(format: String) -> void:
	var ad_unit_id: String = _ids[format]
	_events.clear()
	if format == "mrec":
		AppLovinMax.create_mrec(ad_unit_id, AppLovinMax.AdViewPosition.CENTERED)
	else:
		AppLovinMax.create_banner(ad_unit_id, AppLovinMax.AdViewPosition.BOTTOM_CENTER)
	await _wait_seconds(1.0)

	var size := AppLovinMax.get_ad_view_size(ad_unit_id)
	_log("%s size: %s (screen %s)" % [format, size, DisplayServer.screen_get_size()])
	_check("%s has a size after create" % format, size.x > 0 and size.y > 0)
	if format == "mrec":
		_check("mrec keeps the 300x250 aspect ratio", absf(float(size.x) / maxf(size.y, 1) - 1.2) < 0.05)
	else:
		_check("banner is wider than tall", size.x > size.y)

	AppLovinMax.set_ad_view_background_color(ad_unit_id, Color.BLACK)
	AppLovinMax.set_ad_view_placement(ad_unit_id, "ci_placement")
	AppLovinMax.set_ad_view_custom_data(ad_unit_id, "ci_custom_data")
	AppLovinMax.set_ad_view_extra_parameter(ad_unit_id, "ci_key", "ci_value")
	AppLovinMax.show_ad_view(ad_unit_id)
	AppLovinMax.set_ad_view_position(ad_unit_id, AppLovinMax.AdViewPosition.TOP_CENTER)
	AppLovinMax.stop_ad_view_auto_refresh(ad_unit_id)
	AppLovinMax.start_ad_view_auto_refresh(ad_unit_id)

	var event := await _wait_event(["ad_loaded", "ad_load_failed"], ad_unit_id, AD_CALLBACK_TIMEOUT)
	if _check("%s load callback received" % format, not event.is_empty()):
		_check_callback(format, event)

	AppLovinMax.hide_ad_view(ad_unit_id)
	AppLovinMax.destroy_ad_view(ad_unit_id)
	await _wait_seconds(1.0)
	_check("%s is gone after destroy" % format, AppLovinMax.get_ad_view_size(ad_unit_id) == Vector2i.ZERO)


func _check_callback(kind: String, event: Dictionary) -> void:
	_log("%s -> %s %s" % [kind, event["name"], str(event["args"])])
	if event["name"] == "ad_loaded":
		var info: Dictionary = event["args"][1]
		_check("%s ad_info has network_name" % kind, info.has("network_name"))
		_check("%s ad_info has revenue" % kind, info.has("revenue"))
		_check("%s ad_info format is '%s'" % [kind, kind], info.get("format") == kind or (kind == "banner" and info.get("format") == "leader"))
	else:
		var error: Dictionary = event["args"][1]
		_check("%s error_info has code" % kind, error.has("code"))
		_check("%s error_info has message" % kind, error.has("message"))


func _record_signals() -> void:
	AppLovinMax.sdk_initialized.connect(func(a): _record("sdk_initialized", [a]))
	AppLovinMax.ad_loaded.connect(func(a, b): _record("ad_loaded", [a, b]))
	AppLovinMax.ad_load_failed.connect(func(a, b): _record("ad_load_failed", [a, b]))
	AppLovinMax.ad_displayed.connect(func(a, b): _record("ad_displayed", [a, b]))
	AppLovinMax.ad_display_failed.connect(func(a, b, c): _record("ad_display_failed", [a, b, c]))
	AppLovinMax.ad_hidden.connect(func(a, b): _record("ad_hidden", [a, b]))
	AppLovinMax.ad_revenue_paid.connect(func(a, b): _record("ad_revenue_paid", [a, b]))


func _record(signal_name: String, args: Array) -> void:
	_events.append({"name": signal_name, "args": args})


func _wait_event(signal_names: Array, ad_unit_id: String, timeout: float) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for event in _events:
			if signal_names.has(event["name"]) and (ad_unit_id.is_empty() or event["args"][0] == ad_unit_id):
				return event
		await get_tree().process_frame
	return {}


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _load_config() -> void:
	var file := FileAccess.open("res://test_config.json", FileAccess.READ)
	if file:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_config = parsed
	_check("test_config.json loaded", not _config.is_empty())
	var platform_key := "ios" if OS.get_name() == "iOS" else "android"
	_ids = _config.get(platform_key, {})
	for kind in ["interstitial", "rewarded", "app_open", "banner", "mrec"]:
		if not _ids.has(kind):
			_ids[kind] = "0000000000000000"


func _check(description: String, passed: bool) -> bool:
	_checks += 1
	if not passed:
		_failures += 1
	_log(("PASS  " if passed else "FAIL  ") + description)
	return passed


func _log(message: String) -> void:
	var line := "[ALTEST] " + message
	print(line)
	var file := FileAccess.open(RESULT_FILE, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line(line)
		file.close()
