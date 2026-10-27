@tool
extends EditorPlugin

const AUTOLOAD_NAME := "AppLovinMax"
const AUTOLOAD_PATH := "res://addons/applovin_max/applovin_max.gd"
const INSTALL_IOS_SDK_MENU := "AppLovin MAX: Download iOS SDK"

const ExportPlugin := preload("res://addons/applovin_max/export_plugin.gd")
const IosSdkInstaller := preload("res://addons/applovin_max/ios_sdk_installer.gd")

var _export_plugin: EditorExportPlugin
var _ios_sdk_installer: IosSdkInstaller


func _enter_tree() -> void:
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)

	_ios_sdk_installer = IosSdkInstaller.new()
	add_child(_ios_sdk_installer)
	add_tool_menu_item(INSTALL_IOS_SDK_MENU, _on_install_ios_sdk)


func _exit_tree() -> void:
	remove_tool_menu_item(INSTALL_IOS_SDK_MENU)
	if _ios_sdk_installer:
		_ios_sdk_installer.queue_free()
		_ios_sdk_installer = null
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _on_install_ios_sdk() -> void:
	_ios_sdk_installer.install(ExportPlugin.DEFAULT_IOS_SDK_VERSION)
