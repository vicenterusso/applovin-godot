#include "applovin_max_plugin.h"

#include "applovin_max.h"

#include "core/config/engine.h"

static GodotAppLovinMax *applovin_max = nullptr;

void applovin_max_plugin_init() {
	applovin_max = memnew(GodotAppLovinMax);
	Engine::get_singleton()->add_singleton(Engine::Singleton("GodotAppLovinMax", applovin_max));
}

void applovin_max_plugin_deinit() {
	if (applovin_max) {
		memdelete(applovin_max);
		applovin_max = nullptr;
	}
}
