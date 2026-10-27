#ifndef GODOT_APPLOVIN_MAX_H
#define GODOT_APPLOVIN_MAX_H

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/variant/dictionary.h"

// Engine singleton "GodotAppLovinMax". Method names, arguments and signals mirror the
// Android plugin (android/plugin/.../GodotAppLovinMax.java) so the GDScript wrapper
// (addons/applovin_max/applovin_max.gd) can treat both platforms the same way.
class GodotAppLovinMax : public Object {
	GDCLASS(GodotAppLovinMax, Object);

	static GodotAppLovinMax *singleton;

protected:
	static void _bind_methods();

public:
	static GodotAppLovinMax *get_singleton();

	// SDK
	void initialize(const String &p_sdk_key, const Dictionary &p_config);
	bool is_initialized() const;
	Dictionary get_sdk_configuration() const;
	String get_sdk_version() const;
	String get_plugin_version() const;
	void show_mediation_debugger();
	void show_creative_debugger();
	void set_muted(bool p_muted);
	bool is_muted() const;
	void set_verbose_logging(bool p_enabled);
	void set_creative_debugger_enabled(bool p_enabled);
	void set_user_id(const String &p_user_id);
	void set_extra_parameter(const String &p_key, const String &p_value);

	// Privacy
	void set_has_user_consent(bool p_consent);
	bool has_user_consent() const;
	bool is_user_consent_set() const;
	void set_do_not_sell(bool p_do_not_sell);
	bool is_do_not_sell() const;
	bool has_supported_cmp() const;
	void show_cmp_for_existing_user();
	void request_tracking_authorization();

	// Interstitials
	void load_interstitial(const String &p_ad_unit_id);
	bool is_interstitial_ready(const String &p_ad_unit_id) const;
	void show_interstitial(const String &p_ad_unit_id, const String &p_placement, const String &p_custom_data);
	void set_interstitial_extra_parameter(const String &p_ad_unit_id, const String &p_key, const String &p_value);

	// Rewarded
	void load_rewarded_ad(const String &p_ad_unit_id);
	bool is_rewarded_ad_ready(const String &p_ad_unit_id) const;
	void show_rewarded_ad(const String &p_ad_unit_id, const String &p_placement, const String &p_custom_data);
	void set_rewarded_ad_extra_parameter(const String &p_ad_unit_id, const String &p_key, const String &p_value);

	// App open
	void load_app_open_ad(const String &p_ad_unit_id);
	bool is_app_open_ad_ready(const String &p_ad_unit_id) const;
	void show_app_open_ad(const String &p_ad_unit_id, const String &p_placement, const String &p_custom_data);
	void set_app_open_ad_extra_parameter(const String &p_ad_unit_id, const String &p_key, const String &p_value);

	// Banners / leaders / MRECs
	void create_ad_view(const String &p_ad_unit_id, const String &p_format, const String &p_position, bool p_adaptive);
	void load_ad_view(const String &p_ad_unit_id);
	void show_ad_view(const String &p_ad_unit_id);
	void hide_ad_view(const String &p_ad_unit_id);
	void destroy_ad_view(const String &p_ad_unit_id);
	void set_ad_view_position(const String &p_ad_unit_id, const String &p_position);
	void set_ad_view_background_color(const String &p_ad_unit_id, const String &p_color);
	void set_ad_view_placement(const String &p_ad_unit_id, const String &p_placement);
	void set_ad_view_custom_data(const String &p_ad_unit_id, const String &p_custom_data);
	void set_ad_view_extra_parameter(const String &p_ad_unit_id, const String &p_key, const String &p_value);
	void start_ad_view_auto_refresh(const String &p_ad_unit_id);
	void stop_ad_view_auto_refresh(const String &p_ad_unit_id);
	Dictionary get_ad_view_size(const String &p_ad_unit_id) const;

	GodotAppLovinMax();
	~GodotAppLovinMax();
};

#endif // GODOT_APPLOVIN_MAX_H
