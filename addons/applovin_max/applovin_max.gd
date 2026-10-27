extends Node
## AppLovin MAX for Godot (autoload "AppLovinMax").
##
## Thin wrapper over the native "GodotAppLovinMax" singleton provided by the Android
## (AAR) and iOS (.gdip) plugins. On other platforms (editor, desktop, web) every call
## is a no-op and is_available() returns false, so game code needs no platform checks.

signal sdk_initialized(sdk_configuration: Dictionary)
signal ad_loaded(ad_unit_id: String, ad_info: Dictionary)
signal ad_load_failed(ad_unit_id: String, error_info: Dictionary)
signal ad_displayed(ad_unit_id: String, ad_info: Dictionary)
signal ad_display_failed(ad_unit_id: String, error_info: Dictionary, ad_info: Dictionary)
signal ad_clicked(ad_unit_id: String, ad_info: Dictionary)
signal ad_hidden(ad_unit_id: String, ad_info: Dictionary)
signal ad_revenue_paid(ad_unit_id: String, ad_info: Dictionary)
signal ad_received_reward(ad_unit_id: String, reward: Dictionary, ad_info: Dictionary)
signal ad_expanded(ad_unit_id: String, ad_info: Dictionary)
signal ad_collapsed(ad_unit_id: String, ad_info: Dictionary)
## Emitted after show_cmp_for_existing_user(); error_info is empty on success.
signal cmp_flow_completed(error_info: Dictionary)
## iOS only. status: "authorized", "denied", "restricted", "not_determined" or "unavailable".
signal tracking_authorization_completed(status: String)

enum AdViewPosition {
	TOP_LEFT,
	TOP_CENTER,
	TOP_RIGHT,
	CENTER_LEFT,
	CENTERED,
	CENTER_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_CENTER,
	BOTTOM_RIGHT,
}

const NATIVE_SINGLETON := "GodotAppLovinMax"

const _POSITION_NAMES := [
	"top_left", "top_center", "top_right",
	"center_left", "centered", "center_right",
	"bottom_left", "bottom_center", "bottom_right",
]

# Native signal name -> number of arguments.
const _NATIVE_SIGNALS := {
	"sdk_initialized": 1,
	"ad_loaded": 2,
	"ad_load_failed": 2,
	"ad_displayed": 2,
	"ad_display_failed": 3,
	"ad_clicked": 2,
	"ad_hidden": 2,
	"ad_revenue_paid": 2,
	"ad_received_reward": 3,
	"ad_expanded": 2,
	"ad_collapsed": 2,
	"cmp_flow_completed": 1,
	"tracking_authorization_completed": 1,
}

var _native: Object
var _warned := false


func _init() -> void:
	if not Engine.has_singleton(NATIVE_SINGLETON):
		return
	_native = Engine.get_singleton(NATIVE_SINGLETON)
	for signal_name: String in _NATIVE_SIGNALS:
		if not _native.has_signal(signal_name):
			continue
		match _NATIVE_SIGNALS[signal_name]:
			1:
				_native.connect(signal_name, _forward_1.bind(signal_name))
			2:
				_native.connect(signal_name, _forward_2.bind(signal_name))
			3:
				_native.connect(signal_name, _forward_3.bind(signal_name))


## True when the native plugin is present (exported Android/iOS build with the plugin enabled).
func is_available() -> bool:
	return _native != null


# region SDK

## Initializes the SDK. Listen to sdk_initialized before loading ads.
##
## Supported config keys (all optional):
## - test_device_advertising_ids: Array[String] (GAID / IDFA of test devices)
## - ad_unit_ids: Array[String] (only initialize these ad units' networks)
## - verbose_logging, muted, creative_debugger_enabled: bool
## - user_id: String
## - has_user_consent, do_not_sell: bool (only applied when present)
## - terms_and_privacy_policy_flow: bool (MAX consent flow; also handles UMP/CMP and ATT)
## - privacy_policy_url, terms_of_service_url: String
## - debug_user_geography: "gdpr" or "other" (testing the consent flow)
## - extra_parameters: Dictionary[String, String]
func initialize(sdk_key: String, config: Dictionary = {}) -> void:
	if _check():
		_native.initialize(sdk_key, config)


func is_initialized() -> bool:
	return _native != null and _native.is_initialized()


## Keys: country_code, consent_flow_user_geography ("gdpr", "other", "unknown"),
## is_test_mode_enabled, app_tracking_status (iOS).
func get_sdk_configuration() -> Dictionary:
	return _native.get_sdk_configuration() if _native else {}


func get_sdk_version() -> String:
	return _native.get_sdk_version() if _native else ""


func get_plugin_version() -> String:
	return _native.get_plugin_version() if _native else ""


func show_mediation_debugger() -> void:
	if _check():
		_native.show_mediation_debugger()


func show_creative_debugger() -> void:
	if _check():
		_native.show_creative_debugger()


func set_muted(muted: bool) -> void:
	if _check():
		_native.set_muted(muted)


func is_muted() -> bool:
	return _native != null and _native.is_muted()


func set_verbose_logging(enabled: bool) -> void:
	if _check():
		_native.set_verbose_logging(enabled)


func set_creative_debugger_enabled(enabled: bool) -> void:
	if _check():
		_native.set_creative_debugger_enabled(enabled)


func set_user_id(user_id: String) -> void:
	if _check():
		_native.set_user_id(user_id)


func set_extra_parameter(key: String, value: String) -> void:
	if _check():
		_native.set_extra_parameter(key, value)

# endregion

# region Privacy

func set_has_user_consent(consent: bool) -> void:
	if _check():
		_native.set_has_user_consent(consent)


func has_user_consent() -> bool:
	return _native != null and _native.has_user_consent()


func is_user_consent_set() -> bool:
	return _native != null and _native.is_user_consent_set()


func set_do_not_sell(do_not_sell: bool) -> void:
	if _check():
		_native.set_do_not_sell(do_not_sell)


func is_do_not_sell() -> bool:
	return _native != null and _native.is_do_not_sell()


## True when a CMP (e.g. Google UMP) is integrated and can be shown again via show_cmp_for_existing_user().
func has_supported_cmp() -> bool:
	return _native != null and _native.has_supported_cmp()


## Shows the CMP again so existing users can change their consent. Emits cmp_flow_completed.
func show_cmp_for_existing_user() -> void:
	if _check():
		_native.show_cmp_for_existing_user()


## iOS 14+: shows the App Tracking Transparency prompt (not needed when the MAX
## terms and privacy policy flow is enabled). Emits tracking_authorization_completed.
func request_tracking_authorization() -> void:
	if _native and OS.get_name() == "iOS":
		_native.request_tracking_authorization()
	else:
		call_deferred("emit_signal", "tracking_authorization_completed", "unavailable")

# endregion

# region Interstitials

func load_interstitial(ad_unit_id: String) -> void:
	if _check():
		_native.load_interstitial(ad_unit_id)


func is_interstitial_ready(ad_unit_id: String) -> bool:
	return _native != null and _native.is_interstitial_ready(ad_unit_id)


func show_interstitial(ad_unit_id: String, placement: String = "", custom_data: String = "") -> void:
	if _check():
		_native.show_interstitial(ad_unit_id, placement, custom_data)


func set_interstitial_extra_parameter(ad_unit_id: String, key: String, value: String) -> void:
	if _check():
		_native.set_interstitial_extra_parameter(ad_unit_id, key, value)

# endregion

# region Rewarded

func load_rewarded_ad(ad_unit_id: String) -> void:
	if _check():
		_native.load_rewarded_ad(ad_unit_id)


func is_rewarded_ad_ready(ad_unit_id: String) -> bool:
	return _native != null and _native.is_rewarded_ad_ready(ad_unit_id)


func show_rewarded_ad(ad_unit_id: String, placement: String = "", custom_data: String = "") -> void:
	if _check():
		_native.show_rewarded_ad(ad_unit_id, placement, custom_data)


func set_rewarded_ad_extra_parameter(ad_unit_id: String, key: String, value: String) -> void:
	if _check():
		_native.set_rewarded_ad_extra_parameter(ad_unit_id, key, value)

# endregion

# region App open

func load_app_open_ad(ad_unit_id: String) -> void:
	if _check():
		_native.load_app_open_ad(ad_unit_id)


func is_app_open_ad_ready(ad_unit_id: String) -> bool:
	return _native != null and _native.is_app_open_ad_ready(ad_unit_id)


func show_app_open_ad(ad_unit_id: String, placement: String = "", custom_data: String = "") -> void:
	if _check():
		_native.show_app_open_ad(ad_unit_id, placement, custom_data)


func set_app_open_ad_extra_parameter(ad_unit_id: String, key: String, value: String) -> void:
	if _check():
		_native.set_app_open_ad_extra_parameter(ad_unit_id, key, value)

# endregion

# region Banners and MRECs
# Banners, leaderboards and MRECs are "ad views": created once (hidden, loading in the
# background), then shown/hidden as needed. On tablets "banner" uses the 728x90 leader size.

## Creates a banner. adaptive = AppLovin anchored adaptive banner (recommended).
func create_banner(ad_unit_id: String, position: AdViewPosition = AdViewPosition.BOTTOM_CENTER, adaptive: bool = true) -> void:
	create_ad_view(ad_unit_id, "banner", position, adaptive)


## Creates a 300x250 MREC.
func create_mrec(ad_unit_id: String, position: AdViewPosition = AdViewPosition.CENTERED) -> void:
	create_ad_view(ad_unit_id, "mrec", position, false)


## format: "banner", "leader" or "mrec".
func create_ad_view(ad_unit_id: String, format: String, position: AdViewPosition, adaptive: bool = true) -> void:
	if _check():
		_native.create_ad_view(ad_unit_id, format, _POSITION_NAMES[position], adaptive)


func show_ad_view(ad_unit_id: String) -> void:
	if _check():
		_native.show_ad_view(ad_unit_id)


func hide_ad_view(ad_unit_id: String) -> void:
	if _check():
		_native.hide_ad_view(ad_unit_id)


func destroy_ad_view(ad_unit_id: String) -> void:
	if _check():
		_native.destroy_ad_view(ad_unit_id)


## Manually loads a new ad (useful after stop_ad_view_auto_refresh()).
func load_ad_view(ad_unit_id: String) -> void:
	if _check():
		_native.load_ad_view(ad_unit_id)


func set_ad_view_position(ad_unit_id: String, position: AdViewPosition) -> void:
	if _check():
		_native.set_ad_view_position(ad_unit_id, _POSITION_NAMES[position])


func set_ad_view_background_color(ad_unit_id: String, color: Color) -> void:
	if _check():
		_native.set_ad_view_background_color(ad_unit_id, "#%02x%02x%02x%02x" % [color.a8, color.r8, color.g8, color.b8])


func set_ad_view_placement(ad_unit_id: String, placement: String) -> void:
	if _check():
		_native.set_ad_view_placement(ad_unit_id, placement)


func set_ad_view_custom_data(ad_unit_id: String, custom_data: String) -> void:
	if _check():
		_native.set_ad_view_custom_data(ad_unit_id, custom_data)


func set_ad_view_extra_parameter(ad_unit_id: String, key: String, value: String) -> void:
	if _check():
		_native.set_ad_view_extra_parameter(ad_unit_id, key, value)


func start_ad_view_auto_refresh(ad_unit_id: String) -> void:
	if _check():
		_native.start_ad_view_auto_refresh(ad_unit_id)


func stop_ad_view_auto_refresh(ad_unit_id: String) -> void:
	if _check():
		_native.stop_ad_view_auto_refresh(ad_unit_id)


## Size of the ad view in screen pixels (Vector2i.ZERO if it does not exist).
func get_ad_view_size(ad_unit_id: String) -> Vector2i:
	if _native == null:
		return Vector2i.ZERO
	var size: Dictionary = _native.get_ad_view_size(ad_unit_id)
	return Vector2i(int(size.get("width", 0)), int(size.get("height", 0)))


# Banner / MREC aliases, for readability.
func show_banner(ad_unit_id: String) -> void: show_ad_view(ad_unit_id)
func hide_banner(ad_unit_id: String) -> void: hide_ad_view(ad_unit_id)
func destroy_banner(ad_unit_id: String) -> void: destroy_ad_view(ad_unit_id)
func show_mrec(ad_unit_id: String) -> void: show_ad_view(ad_unit_id)
func hide_mrec(ad_unit_id: String) -> void: hide_ad_view(ad_unit_id)
func destroy_mrec(ad_unit_id: String) -> void: destroy_ad_view(ad_unit_id)

# endregion


func _check() -> bool:
	if _native:
		return true
	if not _warned:
		_warned = true
		print_verbose("[AppLovin MAX] Native plugin not available on this platform; ad calls are ignored.")
	return false


func _forward_1(a: Variant, signal_name: StringName) -> void:
	emit_signal(signal_name, a)


func _forward_2(a: Variant, b: Variant, signal_name: StringName) -> void:
	emit_signal(signal_name, a, b)


func _forward_3(a: Variant, b: Variant, c: Variant, signal_name: StringName) -> void:
	emit_signal(signal_name, a, b, c)
