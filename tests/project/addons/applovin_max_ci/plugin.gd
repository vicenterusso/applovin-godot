@tool
extends EditorPlugin
## When the editor is started with APPLOVIN_CI_INSTALL_IOS_SDK=<version>, installs the
## AppLovin iOS SDK with the same installer used by the "Download iOS SDK" menu, then
## quits with exit code 0 (success) or 1 (failure).

const IosSdkInstaller := preload("res://addons/applovin_max/ios_sdk_installer.gd")


func _enter_tree() -> void:
	var version := OS.get_environment("APPLOVIN_CI_INSTALL_IOS_SDK")
	if version.is_empty():
		return
	var installer: IosSdkInstaller = IosSdkInstaller.new()
	add_child(installer)
	installer.finished.connect(_on_finished)
	installer.install(version)


func _on_finished(error_message: String) -> void:
	if error_message.is_empty():
		print("[ALCI] iOS SDK installed")
		get_tree().quit(0)
	else:
		printerr("[ALCI] iOS SDK installation failed: " + error_message)
		get_tree().quit(1)
