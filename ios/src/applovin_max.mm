#include "applovin_max.h"

#import <AppLovinSDK/AppLovinSDK.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <UIKit/UIKit.h>

#ifndef APPLOVIN_MAX_PLUGIN_VERSION
#define APPLOVIN_MAX_PLUGIN_VERSION "1.0.0"
#endif

GodotAppLovinMax *GodotAppLovinMax::singleton = nullptr;

// region Helpers

static NSString *gdal_ns(const String &p_string) {
	return [NSString stringWithUTF8String:p_string.utf8().get_data()];
}

static NSString *gdal_ns_or_nil(const String &p_string) {
	return p_string.is_empty() ? nil : gdal_ns(p_string);
}

static String gdal_gd(NSString *p_string) {
	return p_string ? String::utf8([p_string UTF8String]) : String();
}

static void gdal_emit(const char *p_signal, const Variant &p_arg1) {
	GodotAppLovinMax *plugin = GodotAppLovinMax::get_singleton();
	if (plugin) {
		plugin->emit_signal(StringName(p_signal), p_arg1);
	}
}

static void gdal_emit(const char *p_signal, const Variant &p_arg1, const Variant &p_arg2) {
	GodotAppLovinMax *plugin = GodotAppLovinMax::get_singleton();
	if (plugin) {
		plugin->emit_signal(StringName(p_signal), p_arg1, p_arg2);
	}
}

static void gdal_emit(const char *p_signal, const Variant &p_arg1, const Variant &p_arg2, const Variant &p_arg3) {
	GodotAppLovinMax *plugin = GodotAppLovinMax::get_singleton();
	if (plugin) {
		plugin->emit_signal(StringName(p_signal), p_arg1, p_arg2, p_arg3);
	}
}

static String gdal_format_name(MAAdFormat *p_format) {
	if (!p_format) {
		return String();
	}
	if (p_format == MAAdFormat.banner) {
		return "banner";
	}
	if (p_format == MAAdFormat.mrec) {
		return "mrec";
	}
	if (p_format == MAAdFormat.leader) {
		return "leader";
	}
	if (p_format == MAAdFormat.interstitial) {
		return "interstitial";
	}
	if (p_format == MAAdFormat.rewarded) {
		return "rewarded";
	}
	if (p_format == MAAdFormat.appOpen) {
		return "app_open";
	}
	if (p_format == MAAdFormat.native) {
		return "native";
	}
	return gdal_gd(p_format.label).to_lower();
}

static Dictionary gdal_ad_info(MAAd *p_ad) {
	Dictionary info;
	if (!p_ad) {
		return info;
	}
	info["ad_unit_id"] = gdal_gd(p_ad.adUnitIdentifier);
	info["format"] = gdal_format_name(p_ad.format);
	info["network_name"] = gdal_gd(p_ad.networkName);
	info["network_placement"] = gdal_gd(p_ad.networkPlacement);
	info["placement"] = gdal_gd(p_ad.placement);
	info["creative_id"] = gdal_gd(p_ad.creativeIdentifier);
	info["revenue"] = p_ad.revenue;
	info["revenue_precision"] = gdal_gd(p_ad.revenuePrecision);
	info["dsp_name"] = gdal_gd(p_ad.DSPName);
	info["latency_millis"] = (int)(p_ad.requestLatency * 1000.0);
	return info;
}

static Dictionary gdal_error_info(MAError *p_error) {
	Dictionary info;
	if (!p_error) {
		return info;
	}
	info["code"] = (int)p_error.code;
	info["message"] = gdal_gd(p_error.message);
	info["mediated_network_error_code"] = (int)p_error.mediatedNetworkErrorCode;
	info["mediated_network_error_message"] = gdal_gd(p_error.mediatedNetworkErrorMessage);
	info["latency_millis"] = (int)(p_error.requestLatency * 1000.0);
	return info;
}

static Dictionary gdal_cmp_error_info(ALCMPError *p_error) {
	Dictionary info;
	if (!p_error) {
		return info;
	}
	info["code"] = (int)p_error.code;
	info["code_name"] = String();
	info["message"] = gdal_gd(p_error.message);
	info["cmp_code"] = (int)p_error.cmpCode;
	info["cmp_message"] = gdal_gd(p_error.cmpMessage);
	return info;
}

static String gdal_geography_name(ALConsentFlowUserGeography p_geography) {
	switch (p_geography) {
		case ALConsentFlowUserGeographyGDPR:
			return "gdpr";
		case ALConsentFlowUserGeographyOther:
			return "other";
		default:
			return "unknown";
	}
}

static String gdal_tracking_status_name(NSInteger p_status) {
	// Values shared by ALAppTrackingTransparencyStatus and ATTrackingManagerAuthorizationStatus
	// (the AppLovin enum adds -1 for "unavailable").
	switch (p_status) {
		case 0:
			return "not_determined";
		case 1:
			return "restricted";
		case 2:
			return "denied";
		case 3:
			return "authorized";
		default:
			return "unavailable";
	}
}

static Dictionary gdal_sdk_configuration(ALSdkConfiguration *p_configuration) {
	Dictionary info;
	if (!p_configuration) {
		return info;
	}
	info["country_code"] = gdal_gd(p_configuration.countryCode);
	info["consent_flow_user_geography"] = gdal_geography_name(p_configuration.consentFlowUserGeography);
	info["is_test_mode_enabled"] = (bool)p_configuration.testModeEnabled;
	info["app_tracking_status"] = gdal_tracking_status_name((NSInteger)p_configuration.appTrackingTransparencyStatus);
	return info;
}

static NSArray<NSString *> *gdal_string_array(const Variant &p_value) {
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	if (p_value.get_type() == Variant::STRING) {
		String value = p_value;
		if (!value.is_empty()) {
			[result addObject:gdal_ns(value)];
		}
		return result;
	}
	if (p_value.get_type() != Variant::ARRAY && p_value.get_type() != Variant::PACKED_STRING_ARRAY) {
		return result;
	}
	Array array = p_value;
	for (int i = 0; i < array.size(); i++) {
		String item = array[i];
		if (!item.is_empty()) {
			[result addObject:gdal_ns(item)];
		}
	}
	return result;
}

static UIColor *gdal_parse_color(NSString *p_color) {
	// Accepts "#RRGGBB" and "#AARRGGBB" (Android's Color.parseColor format).
	NSString *hex = [p_color stringByReplacingOccurrencesOfString:@"#" withString:@""];
	unsigned long long value = 0;
	if (![[NSScanner scannerWithString:hex] scanHexLongLong:&value]) {
		return nil;
	}
	CGFloat alpha = 1.0;
	if (hex.length == 8) {
		alpha = ((value >> 24) & 0xFF) / 255.0;
	} else if (hex.length != 6) {
		return nil;
	}
	return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
						   green:((value >> 8) & 0xFF) / 255.0
							blue:(value & 0xFF) / 255.0
						   alpha:alpha];
}

static UIViewController *gdal_root_view_controller() {
	UIWindow *window = nil;
	if (@available(iOS 13.0, *)) {
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if (![scene isKindOfClass:UIWindowScene.class]) {
				continue;
			}
			for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
				if (candidate.isKeyWindow) {
					window = candidate;
					break;
				}
			}
			if (window) {
				break;
			}
		}
	}
	if (!window) {
		id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
		if ([delegate respondsToSelector:@selector(window)]) {
			window = delegate.window;
		}
	}
	return window.rootViewController;
}

// endregion

// region Ad view holder

@interface GDALAdViewHolder : NSObject
@property(nonatomic, strong) MAAdView *adView;
@property(nonatomic, strong) MAAdFormat *format;
@property(nonatomic, copy) NSString *position;
@property(nonatomic, assign) BOOL adaptive;
@property(nonatomic, assign) BOOL autoRefreshEnabled;
@property(nonatomic, assign) BOOL visible;
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *constraints;
@end

@implementation GDALAdViewHolder

- (BOOL)stretchesHorizontally {
	if (self.format == MAAdFormat.mrec) {
		return NO;
	}
	return [self.position isEqualToString:@"top_center"] || [self.position isEqualToString:@"bottom_center"] ||
			[self.position isEqualToString:@"centered"] || [self.position isEqualToString:@"center"];
}

- (CGSize)sizeInPoints {
	CGSize size = self.format.size;
	if (self.adaptive && self.format != MAAdFormat.mrec) {
		size.height = self.format.adaptiveSize.height;
	}
	return size;
}

- (void)layoutInView:(UIView *)parent {
	if (self.constraints) {
		[NSLayoutConstraint deactivateConstraints:self.constraints];
	}

	UILayoutGuide *safe = parent.safeAreaLayoutGuide;
	MAAdView *view = self.adView;
	CGSize size = [self sizeInPoints];
	NSString *position = self.position;
	NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];

	[constraints addObject:[view.heightAnchor constraintEqualToConstant:size.height]];

	// Horizontal placement.
	if ([position hasSuffix:@"_left"]) {
		[constraints addObject:[view.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor]];
		[constraints addObject:[view.widthAnchor constraintEqualToConstant:size.width]];
	} else if ([position hasSuffix:@"_right"]) {
		[constraints addObject:[view.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor]];
		[constraints addObject:[view.widthAnchor constraintEqualToConstant:size.width]];
	} else if ([self stretchesHorizontally]) {
		[constraints addObject:[view.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor]];
		[constraints addObject:[view.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor]];
	} else {
		[constraints addObject:[view.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor]];
		[constraints addObject:[view.widthAnchor constraintEqualToConstant:size.width]];
	}

	// Vertical placement.
	if ([position hasPrefix:@"top_"]) {
		[constraints addObject:[view.topAnchor constraintEqualToAnchor:safe.topAnchor]];
	} else if ([position hasPrefix:@"bottom_"]) {
		[constraints addObject:[view.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]];
	} else {
		[constraints addObject:[view.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor]];
	}

	self.constraints = constraints;
	[NSLayoutConstraint activateConstraints:constraints];
}

@end

// endregion

// region Delegate

@interface GDALDelegate : NSObject <MAAdDelegate, MARewardedAdDelegate, MAAdViewAdDelegate, MAAdRevenueDelegate>
@property(nonatomic, strong) NSMutableDictionary<NSString *, MAInterstitialAd *> *interstitials;
@property(nonatomic, strong) NSMutableDictionary<NSString *, MARewardedAd *> *rewardedAds;
@property(nonatomic, strong) NSMutableDictionary<NSString *, MAAppOpenAd *> *appOpenAds;
@property(nonatomic, strong) NSMutableDictionary<NSString *, GDALAdViewHolder *> *adViews;
@property(nonatomic, assign) BOOL initializing;
@end

@implementation GDALDelegate

- (instancetype)init {
	self = [super init];
	if (self) {
		_interstitials = [NSMutableDictionary dictionary];
		_rewardedAds = [NSMutableDictionary dictionary];
		_appOpenAds = [NSMutableDictionary dictionary];
		_adViews = [NSMutableDictionary dictionary];
	}
	return self;
}

- (MAInterstitialAd *)interstitialFor:(NSString *)adUnitId {
	MAInterstitialAd *ad = self.interstitials[adUnitId];
	if (!ad) {
		ad = [[MAInterstitialAd alloc] initWithAdUnitIdentifier:adUnitId];
		ad.delegate = self;
		ad.revenueDelegate = self;
		self.interstitials[adUnitId] = ad;
	}
	return ad;
}

- (MARewardedAd *)rewardedFor:(NSString *)adUnitId {
	MARewardedAd *ad = self.rewardedAds[adUnitId];
	if (!ad) {
		ad = [MARewardedAd sharedWithAdUnitIdentifier:adUnitId];
		ad.delegate = self;
		ad.revenueDelegate = self;
		self.rewardedAds[adUnitId] = ad;
	}
	return ad;
}

- (MAAppOpenAd *)appOpenFor:(NSString *)adUnitId {
	MAAppOpenAd *ad = self.appOpenAds[adUnitId];
	if (!ad) {
		ad = [[MAAppOpenAd alloc] initWithAdUnitIdentifier:adUnitId];
		ad.delegate = self;
		ad.revenueDelegate = self;
		self.appOpenAds[adUnitId] = ad;
	}
	return ad;
}

- (GDALAdViewHolder *)adViewFor:(NSString *)adUnitId {
	GDALAdViewHolder *holder = self.adViews[adUnitId];
	if (!holder) {
		NSLog(@"[GodotAppLovinMax] Ad view %@ does not exist; call create_ad_view() first", adUnitId);
	}
	return holder;
}

// MAAdDelegate

- (void)didLoadAd:(MAAd *)ad {
	gdal_emit("ad_loaded", gdal_gd(ad.adUnitIdentifier), gdal_ad_info(ad));
}

- (void)didFailToLoadAdForAdUnitIdentifier:(NSString *)adUnitIdentifier withError:(MAError *)error {
	gdal_emit("ad_load_failed", gdal_gd(adUnitIdentifier), gdal_error_info(error));
}

- (void)didDisplayAd:(MAAd *)ad {
	gdal_emit("ad_displayed", gdal_gd(ad.adUnitIdentifier), gdal_ad_info(ad));
}

- (void)didHideAd:(MAAd *)ad {
	gdal_emit("ad_hidden", gdal_gd(ad.adUnitIdentifier), gdal_ad_info(ad));
}

- (void)didClickAd:(MAAd *)ad {
	gdal_emit("ad_clicked", gdal_gd(ad.adUnitIdentifier), gdal_ad_info(ad));
}

- (void)didFailToDisplayAd:(MAAd *)ad withError:(MAError *)error {
	gdal_emit("ad_display_failed", gdal_gd(ad.adUnitIdentifier), gdal_error_info(error), gdal_ad_info(ad));
}

// MARewardedAdDelegate

- (void)didRewardUserForAd:(MAAd *)ad withReward:(MAReward *)reward {
	Dictionary reward_info;
	reward_info["label"] = gdal_gd(reward.label);
	reward_info["amount"] = (int)reward.amount;
	gdal_emit("ad_received_reward", gdal_gd(ad.adUnitIdentifier), reward_info, gdal_ad_info(ad));
}

// MAAdViewAdDelegate

- (void)didExpandAd:(MAAd *)ad {
	gdal_emit("ad_expanded", gdal_gd(ad.adUnitIdentifier), gdal_ad_info(ad));
}

- (void)didCollapseAd:(MAAd *)ad {
	gdal_emit("ad_collapsed", gdal_gd(ad.adUnitIdentifier), gdal_ad_info(ad));
}

// MAAdRevenueDelegate

- (void)didPayRevenueForAd:(MAAd *)ad {
	gdal_emit("ad_revenue_paid", gdal_gd(ad.adUnitIdentifier), gdal_ad_info(ad));
}

@end

static GDALDelegate *gdal_delegate = nil;

// endregion

GodotAppLovinMax *GodotAppLovinMax::get_singleton() {
	return singleton;
}

// region SDK

void GodotAppLovinMax::initialize(const String &p_sdk_key, const Dictionary &p_config) {
	ALSdk *sdk = [ALSdk shared];
	if (gdal_delegate.initializing || sdk.initialized) {
		WARN_PRINT("AppLovin SDK is already initialized or initializing.");
		if (sdk.initialized) {
			gdal_emit("sdk_initialized", gdal_sdk_configuration(sdk.configuration));
		}
		return;
	}
	gdal_delegate.initializing = YES;

	ALSdkSettings *settings = sdk.settings;
	if (p_config.has("verbose_logging")) {
		settings.verboseLoggingEnabled = (bool)p_config["verbose_logging"];
	}
	if (p_config.has("muted")) {
		settings.muted = (bool)p_config["muted"];
	}
	if (p_config.has("creative_debugger_enabled")) {
		settings.creativeDebuggerEnabled = (bool)p_config["creative_debugger_enabled"];
	}
	if (p_config.has("user_id")) {
		settings.userIdentifier = gdal_ns(p_config["user_id"]);
	}
	if (p_config.has("extra_parameters")) {
		Dictionary extras = p_config["extra_parameters"];
		Array keys = extras.keys();
		for (int i = 0; i < keys.size(); i++) {
			String key = keys[i];
			String value = extras[keys[i]];
			[settings setExtraParameterForKey:gdal_ns(key) value:gdal_ns(value)];
		}
	}

	if (p_config.has("has_user_consent")) {
		[ALPrivacySettings setHasUserConsent:(bool)p_config["has_user_consent"]];
	}
	if (p_config.has("do_not_sell")) {
		[ALPrivacySettings setDoNotSell:(bool)p_config["do_not_sell"]];
	}

	// MAX Terms and Privacy Policy flow (also drives the Google UMP / CMP flow and the ATT prompt).
	if (p_config.has("terms_and_privacy_policy_flow") && (bool)p_config["terms_and_privacy_policy_flow"]) {
		ALTermsAndPrivacyPolicyFlowSettings *flow = settings.termsAndPrivacyPolicyFlowSettings;
		flow.enabled = YES;
		String privacy_policy = p_config.get("privacy_policy_url", String());
		if (!privacy_policy.is_empty()) {
			flow.privacyPolicyURL = [NSURL URLWithString:gdal_ns(privacy_policy)];
		}
		String terms_of_service = p_config.get("terms_of_service_url", String());
		if (!terms_of_service.is_empty()) {
			flow.termsOfServiceURL = [NSURL URLWithString:gdal_ns(terms_of_service)];
		}
		String geography = String(p_config.get("debug_user_geography", String())).to_lower();
		if (geography == "gdpr") {
			flow.debugUserGeography = ALConsentFlowUserGeographyGDPR;
		} else if (geography == "other") {
			flow.debugUserGeography = ALConsentFlowUserGeographyOther;
		}
	}

	NSArray<NSString *> *test_devices = gdal_string_array(p_config.get("test_device_advertising_ids", Variant()));
	NSArray<NSString *> *ad_unit_ids = gdal_string_array(p_config.get("ad_unit_ids", Variant()));

	ALSdkInitializationConfiguration *configuration =
			[ALSdkInitializationConfiguration configurationWithSdkKey:gdal_ns(p_sdk_key)
														 builderBlock:^(ALSdkInitializationConfigurationBuilder *builder) {
															 builder.mediationProvider = ALMediationProviderMAX;
															 builder.pluginVersion = [@"Godot-" stringByAppendingString:@APPLOVIN_MAX_PLUGIN_VERSION];
															 if (test_devices.count > 0) {
																 builder.testDeviceAdvertisingIdentifiers = test_devices;
															 }
															 if (ad_unit_ids.count > 0) {
																 builder.adUnitIdentifiers = ad_unit_ids;
															 }
														 }];

	[sdk initializeWithConfiguration:configuration
				   completionHandler:^(ALSdkConfiguration *sdk_configuration) {
					   gdal_delegate.initializing = NO;
					   gdal_emit("sdk_initialized", gdal_sdk_configuration(sdk_configuration));
				   }];
}

bool GodotAppLovinMax::is_initialized() const {
	return [ALSdk shared].initialized;
}

Dictionary GodotAppLovinMax::get_sdk_configuration() const {
	if (!is_initialized()) {
		return Dictionary();
	}
	return gdal_sdk_configuration([ALSdk shared].configuration);
}

String GodotAppLovinMax::get_sdk_version() const {
	return gdal_gd([ALSdk version]);
}

String GodotAppLovinMax::get_plugin_version() const {
	return APPLOVIN_MAX_PLUGIN_VERSION;
}

void GodotAppLovinMax::show_mediation_debugger() {
	[[ALSdk shared] showMediationDebugger];
}

void GodotAppLovinMax::show_creative_debugger() {
	[[ALSdk shared] showCreativeDebugger];
}

void GodotAppLovinMax::set_muted(bool p_muted) {
	[ALSdk shared].settings.muted = p_muted;
}

bool GodotAppLovinMax::is_muted() const {
	return [ALSdk shared].settings.muted;
}

void GodotAppLovinMax::set_verbose_logging(bool p_enabled) {
	[ALSdk shared].settings.verboseLoggingEnabled = p_enabled;
}

void GodotAppLovinMax::set_creative_debugger_enabled(bool p_enabled) {
	[ALSdk shared].settings.creativeDebuggerEnabled = p_enabled;
}

void GodotAppLovinMax::set_user_id(const String &p_user_id) {
	[ALSdk shared].settings.userIdentifier = gdal_ns_or_nil(p_user_id);
}

void GodotAppLovinMax::set_extra_parameter(const String &p_key, const String &p_value) {
	[[ALSdk shared].settings setExtraParameterForKey:gdal_ns(p_key) value:gdal_ns_or_nil(p_value)];
}

// endregion

// region Privacy

void GodotAppLovinMax::set_has_user_consent(bool p_consent) {
	[ALPrivacySettings setHasUserConsent:p_consent];
}

bool GodotAppLovinMax::has_user_consent() const {
	return [ALPrivacySettings hasUserConsent];
}

bool GodotAppLovinMax::is_user_consent_set() const {
	return [ALPrivacySettings isUserConsentSet];
}

void GodotAppLovinMax::set_do_not_sell(bool p_do_not_sell) {
	[ALPrivacySettings setDoNotSell:p_do_not_sell];
}

bool GodotAppLovinMax::is_do_not_sell() const {
	return [ALPrivacySettings isDoNotSell];
}

bool GodotAppLovinMax::has_supported_cmp() const {
	return [[ALSdk shared].cmpService hasSupportedCMP];
}

void GodotAppLovinMax::show_cmp_for_existing_user() {
	[[ALSdk shared].cmpService showCMPForExistingUserWithCompletion:^(ALCMPError *_Nullable error) {
		gdal_emit("cmp_flow_completed", gdal_cmp_error_info(error));
	}];
}

void GodotAppLovinMax::request_tracking_authorization() {
	if (@available(iOS 14.0, *)) {
		[ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
			dispatch_async(dispatch_get_main_queue(), ^{
				gdal_emit("tracking_authorization_completed", gdal_tracking_status_name((NSInteger)status));
			});
		}];
	} else {
		gdal_emit("tracking_authorization_completed", String("authorized"));
	}
}

// endregion

// region Interstitials

void GodotAppLovinMax::load_interstitial(const String &p_ad_unit_id) {
	[[gdal_delegate interstitialFor:gdal_ns(p_ad_unit_id)] loadAd];
}

bool GodotAppLovinMax::is_interstitial_ready(const String &p_ad_unit_id) const {
	MAInterstitialAd *ad = gdal_delegate.interstitials[gdal_ns(p_ad_unit_id)];
	return ad != nil && ad.ready;
}

void GodotAppLovinMax::show_interstitial(const String &p_ad_unit_id, const String &p_placement, const String &p_custom_data) {
	MAInterstitialAd *ad = gdal_delegate.interstitials[gdal_ns(p_ad_unit_id)];
	ERR_FAIL_NULL_MSG(ad, "show_interstitial(): ad unit " + p_ad_unit_id + " was never loaded.");
	[ad showAdForPlacement:gdal_ns_or_nil(p_placement) customData:gdal_ns_or_nil(p_custom_data)];
}

void GodotAppLovinMax::set_interstitial_extra_parameter(const String &p_ad_unit_id, const String &p_key, const String &p_value) {
	[[gdal_delegate interstitialFor:gdal_ns(p_ad_unit_id)] setExtraParameterForKey:gdal_ns(p_key) value:gdal_ns_or_nil(p_value)];
}

// endregion

// region Rewarded

void GodotAppLovinMax::load_rewarded_ad(const String &p_ad_unit_id) {
	[[gdal_delegate rewardedFor:gdal_ns(p_ad_unit_id)] loadAd];
}

bool GodotAppLovinMax::is_rewarded_ad_ready(const String &p_ad_unit_id) const {
	MARewardedAd *ad = gdal_delegate.rewardedAds[gdal_ns(p_ad_unit_id)];
	return ad != nil && ad.ready;
}

void GodotAppLovinMax::show_rewarded_ad(const String &p_ad_unit_id, const String &p_placement, const String &p_custom_data) {
	MARewardedAd *ad = gdal_delegate.rewardedAds[gdal_ns(p_ad_unit_id)];
	ERR_FAIL_NULL_MSG(ad, "show_rewarded_ad(): ad unit " + p_ad_unit_id + " was never loaded.");
	[ad showAdForPlacement:gdal_ns_or_nil(p_placement) customData:gdal_ns_or_nil(p_custom_data)];
}

void GodotAppLovinMax::set_rewarded_ad_extra_parameter(const String &p_ad_unit_id, const String &p_key, const String &p_value) {
	[[gdal_delegate rewardedFor:gdal_ns(p_ad_unit_id)] setExtraParameterForKey:gdal_ns(p_key) value:gdal_ns_or_nil(p_value)];
}

// endregion

// region App open

void GodotAppLovinMax::load_app_open_ad(const String &p_ad_unit_id) {
	[[gdal_delegate appOpenFor:gdal_ns(p_ad_unit_id)] loadAd];
}

bool GodotAppLovinMax::is_app_open_ad_ready(const String &p_ad_unit_id) const {
	MAAppOpenAd *ad = gdal_delegate.appOpenAds[gdal_ns(p_ad_unit_id)];
	return ad != nil && ad.ready;
}

void GodotAppLovinMax::show_app_open_ad(const String &p_ad_unit_id, const String &p_placement, const String &p_custom_data) {
	MAAppOpenAd *ad = gdal_delegate.appOpenAds[gdal_ns(p_ad_unit_id)];
	ERR_FAIL_NULL_MSG(ad, "show_app_open_ad(): ad unit " + p_ad_unit_id + " was never loaded.");
	[ad showAdForPlacement:gdal_ns_or_nil(p_placement) customData:gdal_ns_or_nil(p_custom_data)];
}

void GodotAppLovinMax::set_app_open_ad_extra_parameter(const String &p_ad_unit_id, const String &p_key, const String &p_value) {
	[[gdal_delegate appOpenFor:gdal_ns(p_ad_unit_id)] setExtraParameterForKey:gdal_ns(p_key) value:gdal_ns_or_nil(p_value)];
}

// endregion

// region Banners / leaders / MRECs

void GodotAppLovinMax::create_ad_view(const String &p_ad_unit_id, const String &p_format, const String &p_position, bool p_adaptive) {
	NSString *ad_unit_id = gdal_ns(p_ad_unit_id);
	if (gdal_delegate.adViews[ad_unit_id]) {
		WARN_PRINT("create_ad_view(): ad view " + p_ad_unit_id + " already exists.");
		return;
	}
	UIViewController *root = gdal_root_view_controller();
	ERR_FAIL_NULL_MSG(root, "create_ad_view(): could not find the root view controller.");

	String format_name = p_format.to_lower();
	MAAdFormat *format = MAAdFormat.banner;
	if (format_name == "mrec") {
		format = MAAdFormat.mrec;
	} else if (format_name == "leader" || UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		// Same as AppLovin's own Unity/Flutter plugins: iPads get the 728x90 leaderboard.
		format = MAAdFormat.leader;
	}

	GDALAdViewHolder *holder = [[GDALAdViewHolder alloc] init];
	holder.format = format;
	holder.position = gdal_ns(p_position.to_lower());
	holder.adaptive = p_adaptive && format != MAAdFormat.mrec;
	holder.autoRefreshEnabled = YES;
	holder.visible = NO;

	MAAdView *ad_view = [[MAAdView alloc] initWithAdUnitIdentifier:ad_unit_id adFormat:format];
	ad_view.delegate = gdal_delegate;
	ad_view.revenueDelegate = gdal_delegate;
	ad_view.backgroundColor = UIColor.clearColor;
	ad_view.translatesAutoresizingMaskIntoConstraints = NO;
	ad_view.hidden = YES;
	if (holder.adaptive) {
		[ad_view setExtraParameterForKey:@"adaptive_banner" value:@"true"];
	}
	// Lets stopAutoRefresh take effect right away while the view is hidden.
	[ad_view setExtraParameterForKey:@"allow_pause_auto_refresh_immediately" value:@"true"];
	holder.adView = ad_view;

	[root.view addSubview:ad_view];
	[holder layoutInView:root.view];
	gdal_delegate.adViews[ad_unit_id] = holder;

	[ad_view stopAutoRefresh];
	[ad_view loadAd];
}

void GodotAppLovinMax::load_ad_view(const String &p_ad_unit_id) {
	GDALAdViewHolder *holder = [gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)];
	[holder.adView loadAd];
}

void GodotAppLovinMax::show_ad_view(const String &p_ad_unit_id) {
	GDALAdViewHolder *holder = [gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)];
	if (!holder) {
		return;
	}
	holder.visible = YES;
	holder.adView.hidden = NO;
	[holder.adView.superview bringSubviewToFront:holder.adView];
	if (holder.autoRefreshEnabled) {
		[holder.adView startAutoRefresh];
	}
}

void GodotAppLovinMax::hide_ad_view(const String &p_ad_unit_id) {
	GDALAdViewHolder *holder = [gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)];
	if (!holder) {
		return;
	}
	holder.visible = NO;
	holder.adView.hidden = YES;
	[holder.adView stopAutoRefresh];
}

void GodotAppLovinMax::destroy_ad_view(const String &p_ad_unit_id) {
	NSString *ad_unit_id = gdal_ns(p_ad_unit_id);
	GDALAdViewHolder *holder = gdal_delegate.adViews[ad_unit_id];
	if (!holder) {
		return;
	}
	[gdal_delegate.adViews removeObjectForKey:ad_unit_id];
	if (holder.constraints) {
		[NSLayoutConstraint deactivateConstraints:holder.constraints];
	}
	holder.adView.delegate = nil;
	holder.adView.revenueDelegate = nil;
	[holder.adView removeFromSuperview];
}

void GodotAppLovinMax::set_ad_view_position(const String &p_ad_unit_id, const String &p_position) {
	GDALAdViewHolder *holder = [gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)];
	if (!holder || !holder.adView.superview) {
		return;
	}
	holder.position = gdal_ns(p_position.to_lower());
	[holder layoutInView:holder.adView.superview];
}

void GodotAppLovinMax::set_ad_view_background_color(const String &p_ad_unit_id, const String &p_color) {
	GDALAdViewHolder *holder = [gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)];
	UIColor *color = gdal_parse_color(gdal_ns(p_color));
	ERR_FAIL_NULL_MSG(color, "Invalid ad view background color: " + p_color);
	holder.adView.backgroundColor = color;
}

void GodotAppLovinMax::set_ad_view_placement(const String &p_ad_unit_id, const String &p_placement) {
	[gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)].adView.placement = gdal_ns_or_nil(p_placement);
}

void GodotAppLovinMax::set_ad_view_custom_data(const String &p_ad_unit_id, const String &p_custom_data) {
	[gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)].adView.customData = gdal_ns_or_nil(p_custom_data);
}

void GodotAppLovinMax::set_ad_view_extra_parameter(const String &p_ad_unit_id, const String &p_key, const String &p_value) {
	[[gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)].adView setExtraParameterForKey:gdal_ns(p_key) value:gdal_ns_or_nil(p_value)];
}

void GodotAppLovinMax::start_ad_view_auto_refresh(const String &p_ad_unit_id) {
	GDALAdViewHolder *holder = [gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)];
	holder.autoRefreshEnabled = YES;
	if (holder.visible) {
		[holder.adView startAutoRefresh];
	}
}

void GodotAppLovinMax::stop_ad_view_auto_refresh(const String &p_ad_unit_id) {
	GDALAdViewHolder *holder = [gdal_delegate adViewFor:gdal_ns(p_ad_unit_id)];
	holder.autoRefreshEnabled = NO;
	[holder.adView stopAutoRefresh];
}

Dictionary GodotAppLovinMax::get_ad_view_size(const String &p_ad_unit_id) const {
	Dictionary size;
	GDALAdViewHolder *holder = gdal_delegate.adViews[gdal_ns(p_ad_unit_id)];
	if (!holder) {
		return size;
	}
	CGSize points = holder.adView.bounds.size;
	if (points.width <= 0 || points.height <= 0) {
		points = [holder sizeInPoints];
		if ([holder stretchesHorizontally] && holder.adView.superview) {
			points.width = holder.adView.superview.safeAreaLayoutGuide.layoutFrame.size.width;
		}
	}
	CGFloat scale = UIScreen.mainScreen.nativeScale;
	size["width"] = (int)(points.width * scale);
	size["height"] = (int)(points.height * scale);
	return size;
}

// endregion

void GodotAppLovinMax::_bind_methods() {
	// SDK
	ClassDB::bind_method(D_METHOD("initialize", "sdk_key", "config"), &GodotAppLovinMax::initialize);
	ClassDB::bind_method(D_METHOD("is_initialized"), &GodotAppLovinMax::is_initialized);
	ClassDB::bind_method(D_METHOD("get_sdk_configuration"), &GodotAppLovinMax::get_sdk_configuration);
	ClassDB::bind_method(D_METHOD("get_sdk_version"), &GodotAppLovinMax::get_sdk_version);
	ClassDB::bind_method(D_METHOD("get_plugin_version"), &GodotAppLovinMax::get_plugin_version);
	ClassDB::bind_method(D_METHOD("show_mediation_debugger"), &GodotAppLovinMax::show_mediation_debugger);
	ClassDB::bind_method(D_METHOD("show_creative_debugger"), &GodotAppLovinMax::show_creative_debugger);
	ClassDB::bind_method(D_METHOD("set_muted", "muted"), &GodotAppLovinMax::set_muted);
	ClassDB::bind_method(D_METHOD("is_muted"), &GodotAppLovinMax::is_muted);
	ClassDB::bind_method(D_METHOD("set_verbose_logging", "enabled"), &GodotAppLovinMax::set_verbose_logging);
	ClassDB::bind_method(D_METHOD("set_creative_debugger_enabled", "enabled"), &GodotAppLovinMax::set_creative_debugger_enabled);
	ClassDB::bind_method(D_METHOD("set_user_id", "user_id"), &GodotAppLovinMax::set_user_id);
	ClassDB::bind_method(D_METHOD("set_extra_parameter", "key", "value"), &GodotAppLovinMax::set_extra_parameter);

	// Privacy
	ClassDB::bind_method(D_METHOD("set_has_user_consent", "consent"), &GodotAppLovinMax::set_has_user_consent);
	ClassDB::bind_method(D_METHOD("has_user_consent"), &GodotAppLovinMax::has_user_consent);
	ClassDB::bind_method(D_METHOD("is_user_consent_set"), &GodotAppLovinMax::is_user_consent_set);
	ClassDB::bind_method(D_METHOD("set_do_not_sell", "do_not_sell"), &GodotAppLovinMax::set_do_not_sell);
	ClassDB::bind_method(D_METHOD("is_do_not_sell"), &GodotAppLovinMax::is_do_not_sell);
	ClassDB::bind_method(D_METHOD("has_supported_cmp"), &GodotAppLovinMax::has_supported_cmp);
	ClassDB::bind_method(D_METHOD("show_cmp_for_existing_user"), &GodotAppLovinMax::show_cmp_for_existing_user);
	ClassDB::bind_method(D_METHOD("request_tracking_authorization"), &GodotAppLovinMax::request_tracking_authorization);

	// Interstitials
	ClassDB::bind_method(D_METHOD("load_interstitial", "ad_unit_id"), &GodotAppLovinMax::load_interstitial);
	ClassDB::bind_method(D_METHOD("is_interstitial_ready", "ad_unit_id"), &GodotAppLovinMax::is_interstitial_ready);
	ClassDB::bind_method(D_METHOD("show_interstitial", "ad_unit_id", "placement", "custom_data"), &GodotAppLovinMax::show_interstitial);
	ClassDB::bind_method(D_METHOD("set_interstitial_extra_parameter", "ad_unit_id", "key", "value"), &GodotAppLovinMax::set_interstitial_extra_parameter);

	// Rewarded
	ClassDB::bind_method(D_METHOD("load_rewarded_ad", "ad_unit_id"), &GodotAppLovinMax::load_rewarded_ad);
	ClassDB::bind_method(D_METHOD("is_rewarded_ad_ready", "ad_unit_id"), &GodotAppLovinMax::is_rewarded_ad_ready);
	ClassDB::bind_method(D_METHOD("show_rewarded_ad", "ad_unit_id", "placement", "custom_data"), &GodotAppLovinMax::show_rewarded_ad);
	ClassDB::bind_method(D_METHOD("set_rewarded_ad_extra_parameter", "ad_unit_id", "key", "value"), &GodotAppLovinMax::set_rewarded_ad_extra_parameter);

	// App open
	ClassDB::bind_method(D_METHOD("load_app_open_ad", "ad_unit_id"), &GodotAppLovinMax::load_app_open_ad);
	ClassDB::bind_method(D_METHOD("is_app_open_ad_ready", "ad_unit_id"), &GodotAppLovinMax::is_app_open_ad_ready);
	ClassDB::bind_method(D_METHOD("show_app_open_ad", "ad_unit_id", "placement", "custom_data"), &GodotAppLovinMax::show_app_open_ad);
	ClassDB::bind_method(D_METHOD("set_app_open_ad_extra_parameter", "ad_unit_id", "key", "value"), &GodotAppLovinMax::set_app_open_ad_extra_parameter);

	// Banners / leaders / MRECs
	ClassDB::bind_method(D_METHOD("create_ad_view", "ad_unit_id", "format", "position", "adaptive"), &GodotAppLovinMax::create_ad_view);
	ClassDB::bind_method(D_METHOD("load_ad_view", "ad_unit_id"), &GodotAppLovinMax::load_ad_view);
	ClassDB::bind_method(D_METHOD("show_ad_view", "ad_unit_id"), &GodotAppLovinMax::show_ad_view);
	ClassDB::bind_method(D_METHOD("hide_ad_view", "ad_unit_id"), &GodotAppLovinMax::hide_ad_view);
	ClassDB::bind_method(D_METHOD("destroy_ad_view", "ad_unit_id"), &GodotAppLovinMax::destroy_ad_view);
	ClassDB::bind_method(D_METHOD("set_ad_view_position", "ad_unit_id", "position"), &GodotAppLovinMax::set_ad_view_position);
	ClassDB::bind_method(D_METHOD("set_ad_view_background_color", "ad_unit_id", "color"), &GodotAppLovinMax::set_ad_view_background_color);
	ClassDB::bind_method(D_METHOD("set_ad_view_placement", "ad_unit_id", "placement"), &GodotAppLovinMax::set_ad_view_placement);
	ClassDB::bind_method(D_METHOD("set_ad_view_custom_data", "ad_unit_id", "custom_data"), &GodotAppLovinMax::set_ad_view_custom_data);
	ClassDB::bind_method(D_METHOD("set_ad_view_extra_parameter", "ad_unit_id", "key", "value"), &GodotAppLovinMax::set_ad_view_extra_parameter);
	ClassDB::bind_method(D_METHOD("start_ad_view_auto_refresh", "ad_unit_id"), &GodotAppLovinMax::start_ad_view_auto_refresh);
	ClassDB::bind_method(D_METHOD("stop_ad_view_auto_refresh", "ad_unit_id"), &GodotAppLovinMax::stop_ad_view_auto_refresh);
	ClassDB::bind_method(D_METHOD("get_ad_view_size", "ad_unit_id"), &GodotAppLovinMax::get_ad_view_size);

	// Signals (same names and arguments as the Android plugin).
	ADD_SIGNAL(MethodInfo("sdk_initialized", PropertyInfo(Variant::DICTIONARY, "sdk_configuration")));
	ADD_SIGNAL(MethodInfo("ad_loaded", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("ad_load_failed", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "error_info")));
	ADD_SIGNAL(MethodInfo("ad_displayed", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("ad_display_failed", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "error_info"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("ad_clicked", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("ad_hidden", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("ad_revenue_paid", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("ad_received_reward", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "reward"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("ad_expanded", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("ad_collapsed", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::DICTIONARY, "ad_info")));
	ADD_SIGNAL(MethodInfo("cmp_flow_completed", PropertyInfo(Variant::DICTIONARY, "error_info")));
	ADD_SIGNAL(MethodInfo("tracking_authorization_completed", PropertyInfo(Variant::STRING, "status")));
}

GodotAppLovinMax::GodotAppLovinMax() {
	ERR_FAIL_COND(singleton != nullptr);
	singleton = this;
	gdal_delegate = [[GDALDelegate alloc] init];
}

GodotAppLovinMax::~GodotAppLovinMax() {
	if (singleton == this) {
		singleton = nullptr;
	}
	for (GDALAdViewHolder *holder in gdal_delegate.adViews.allValues) {
		[holder.adView removeFromSuperview];
	}
	gdal_delegate = nil;
}
