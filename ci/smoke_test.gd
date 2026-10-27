extends SceneTree
## Desktop smoke test: without the native plugin every AppLovinMax call must be a
## harmless no-op. Run with: godot --headless --path <project> -s res://smoke_test.gd

func _init() -> void:
	var failures := PackedStringArray()
	var ads: Node = load("res://addons/applovin_max/applovin_max.gd").new()

	if ads.is_available():
		failures.append("is_available() should be false on desktop")
	ads.initialize("sdk-key", {"verbose_logging": true, "test_device_advertising_ids": ["a", "b"]})
	ads.load_interstitial("inter")
	ads.show_interstitial("inter")
	ads.load_rewarded_ad("rewarded")
	ads.show_rewarded_ad("rewarded", "placement", "data")
	ads.load_app_open_ad("app_open")
	ads.create_banner("banner")
	ads.create_mrec("mrec", ads.AdViewPosition.TOP_LEFT)
	ads.set_ad_view_background_color("banner", Color.RED)
	ads.set_ad_view_position("banner", ads.AdViewPosition.TOP_CENTER)
	ads.show_banner("banner")
	ads.hide_mrec("mrec")
	if ads.is_interstitial_ready("inter") or ads.is_rewarded_ad_ready("rewarded") or ads.is_app_open_ad_ready("app_open"):
		failures.append("ads must never be ready without the native plugin")
	if ads.get_ad_view_size("banner") != Vector2i.ZERO:
		failures.append("get_ad_view_size() should be zero without the native plugin")
	if not ads.get_sdk_configuration().is_empty():
		failures.append("get_sdk_configuration() should be empty without the native plugin")
	ads.free()

	if failures.is_empty():
		print("SMOKE TEST OK")
		quit(0)
	else:
		for failure in failures:
			printerr("SMOKE TEST FAILED: " + failure)
		quit(1)
