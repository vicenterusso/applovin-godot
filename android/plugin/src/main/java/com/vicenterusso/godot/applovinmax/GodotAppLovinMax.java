package com.vicenterusso.godot.applovinmax;

import android.app.Activity;
import android.net.Uri;
import android.os.Build;
import android.util.Log;
import android.view.DisplayCutout;
import android.view.View;
import android.view.WindowInsets;
import android.widget.FrameLayout;

import com.applovin.mediation.MaxAd;
import com.applovin.mediation.MaxAdFormat;
import com.applovin.mediation.MaxAdRevenueListener;
import com.applovin.mediation.MaxAdViewAdListener;
import com.applovin.mediation.MaxError;
import com.applovin.mediation.MaxReward;
import com.applovin.mediation.MaxRewardedAdListener;
import com.applovin.mediation.ads.MaxAppOpenAd;
import com.applovin.mediation.ads.MaxInterstitialAd;
import com.applovin.mediation.ads.MaxRewardedAd;
import com.applovin.sdk.AppLovinMediationProvider;
import com.applovin.sdk.AppLovinPrivacySettings;
import com.applovin.sdk.AppLovinSdk;
import com.applovin.sdk.AppLovinSdkConfiguration;
import com.applovin.sdk.AppLovinSdkInitializationConfiguration;
import com.applovin.sdk.AppLovinSdkSettings;
import com.applovin.sdk.AppLovinSdkUtils;
import com.applovin.sdk.AppLovinTermsAndPrivacyPolicyFlowSettings;

import org.godotengine.godot.Dictionary;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Godot Android plugin (v2) exposing AppLovin MAX.
 *
 * Accessed from GDScript through {@code Engine.get_singleton("GodotAppLovinMax")}; the
 * addon's {@code AppLovinMax} autoload wraps it with the same API used on iOS.
 */
public class GodotAppLovinMax extends GodotPlugin
        implements MaxRewardedAdListener, MaxAdViewAdListener, MaxAdRevenueListener {

    static final String PLUGIN_NAME = "GodotAppLovinMax";
    private static final String TAG = PLUGIN_NAME;

    private static final SignalInfo SDK_INITIALIZED = new SignalInfo("sdk_initialized", Dictionary.class);
    private static final SignalInfo AD_LOADED = new SignalInfo("ad_loaded", String.class, Dictionary.class);
    private static final SignalInfo AD_LOAD_FAILED = new SignalInfo("ad_load_failed", String.class, Dictionary.class);
    private static final SignalInfo AD_DISPLAYED = new SignalInfo("ad_displayed", String.class, Dictionary.class);
    private static final SignalInfo AD_DISPLAY_FAILED = new SignalInfo("ad_display_failed", String.class, Dictionary.class, Dictionary.class);
    private static final SignalInfo AD_CLICKED = new SignalInfo("ad_clicked", String.class, Dictionary.class);
    private static final SignalInfo AD_HIDDEN = new SignalInfo("ad_hidden", String.class, Dictionary.class);
    private static final SignalInfo AD_REVENUE_PAID = new SignalInfo("ad_revenue_paid", String.class, Dictionary.class);
    private static final SignalInfo AD_RECEIVED_REWARD = new SignalInfo("ad_received_reward", String.class, Dictionary.class, Dictionary.class);
    private static final SignalInfo AD_EXPANDED = new SignalInfo("ad_expanded", String.class, Dictionary.class);
    private static final SignalInfo AD_COLLAPSED = new SignalInfo("ad_collapsed", String.class, Dictionary.class);
    private static final SignalInfo CMP_FLOW_COMPLETED = new SignalInfo("cmp_flow_completed", Dictionary.class);

    private final Map<String, MaxInterstitialAd> interstitials = new ConcurrentHashMap<>();
    private final Map<String, MaxRewardedAd> rewardedAds = new ConcurrentHashMap<>();
    private final Map<String, MaxAppOpenAd> appOpenAds = new ConcurrentHashMap<>();
    private final Map<String, AdViewController> adViews = new ConcurrentHashMap<>();

    private FrameLayout overlay;
    private volatile boolean initializing = false;

    public GodotAppLovinMax(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return PLUGIN_NAME;
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(SDK_INITIALIZED);
        signals.add(AD_LOADED);
        signals.add(AD_LOAD_FAILED);
        signals.add(AD_DISPLAYED);
        signals.add(AD_DISPLAY_FAILED);
        signals.add(AD_CLICKED);
        signals.add(AD_HIDDEN);
        signals.add(AD_REVENUE_PAID);
        signals.add(AD_RECEIVED_REWARD);
        signals.add(AD_EXPANDED);
        signals.add(AD_COLLAPSED);
        signals.add(CMP_FLOW_COMPLETED);
        return signals;
    }

    /** Transparent overlay placed by Godot above its render view; banners and MRECs live here. */
    @Override
    public View onMainCreate(Activity activity) {
        overlay = new FrameLayout(activity);
        overlay.setOnApplyWindowInsetsListener((view, insets) -> {
            applySafeAreaPadding(view, insets);
            return insets;
        });
        return overlay;
    }

    @Override
    public void onMainDestroy() {
        for (AdViewController controller : adViews.values()) {
            controller.destroy();
        }
        adViews.clear();
        for (MaxInterstitialAd ad : interstitials.values()) {
            ad.destroy();
        }
        interstitials.clear();
        for (MaxRewardedAd ad : rewardedAds.values()) {
            ad.destroy();
        }
        rewardedAds.clear();
        for (MaxAppOpenAd ad : appOpenAds.values()) {
            ad.destroy();
        }
        appOpenAds.clear();
    }

    // region SDK

    @UsedByGodot
    public void initialize(String sdkKey, Dictionary config) {
        final Activity activity = getActivity();
        if (activity == null) {
            Log.e(TAG, "initialize() called without an activity");
            return;
        }
        if (initializing || AppLovinSdk.getInstance(activity).isInitialized()) {
            Log.w(TAG, "AppLovin SDK is already initialized or initializing");
            if (AppLovinSdk.getInstance(activity).isInitialized()) {
                emit(SDK_INITIALIZED, Converters.sdkConfiguration(AppLovinSdk.getInstance(activity).getConfiguration()));
            }
            return;
        }
        initializing = true;
        final Dictionary options = config != null ? config : new Dictionary();

        runOnUiThread(() -> {
            AppLovinSdk sdk = AppLovinSdk.getInstance(activity);
            applySettings(sdk, options);

            AppLovinSdkInitializationConfiguration.Builder builder = AppLovinSdkInitializationConfiguration.builder(sdkKey)
                    .setMediationProvider(AppLovinMediationProvider.MAX)
                    .setPluginVersion("Godot-" + BuildConfig.PLUGIN_VERSION);

            List<String> testDevices = Converters.stringList(options.get("test_device_advertising_ids"));
            if (!testDevices.isEmpty()) {
                builder.setTestDeviceAdvertisingIds(testDevices);
            }
            List<String> adUnitIds = Converters.stringList(options.get("ad_unit_ids"));
            if (!adUnitIds.isEmpty()) {
                builder.setAdUnitIds(adUnitIds);
            }

            sdk.initialize(builder.build(), configuration -> {
                initializing = false;
                emit(SDK_INITIALIZED, Converters.sdkConfiguration(configuration));
            });
        });
    }

    private void applySettings(AppLovinSdk sdk, Dictionary options) {
        AppLovinSdkSettings settings = sdk.getSettings();

        if (options.containsKey("verbose_logging")) {
            settings.setVerboseLogging(Converters.bool(options.get("verbose_logging"), false));
        }
        if (options.containsKey("muted")) {
            settings.setMuted(Converters.bool(options.get("muted"), false));
        }
        if (options.containsKey("creative_debugger_enabled")) {
            settings.setCreativeDebuggerEnabled(Converters.bool(options.get("creative_debugger_enabled"), true));
        }
        if (options.containsKey("user_id")) {
            settings.setUserIdentifier(Converters.str(options.get("user_id")));
        }
        Object extras = options.get("extra_parameters");
        if (extras instanceof Map) {
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) extras).entrySet()) {
                settings.setExtraParameter(Converters.str(entry.getKey()), Converters.str(entry.getValue()));
            }
        }

        if (options.containsKey("has_user_consent")) {
            AppLovinPrivacySettings.setHasUserConsent(Converters.bool(options.get("has_user_consent"), false));
        }
        if (options.containsKey("do_not_sell")) {
            AppLovinPrivacySettings.setDoNotSell(Converters.bool(options.get("do_not_sell"), false));
        }

        // MAX Terms and Privacy Policy flow (includes the Google UMP / CMP flow when configured).
        if (Converters.bool(options.get("terms_and_privacy_policy_flow"), false)) {
            AppLovinTermsAndPrivacyPolicyFlowSettings flow = settings.getTermsAndPrivacyPolicyFlowSettings();
            flow.setEnabled(true);
            String privacyPolicy = Converters.str(options.get("privacy_policy_url"));
            if (!privacyPolicy.isEmpty()) {
                flow.setPrivacyPolicyUri(Uri.parse(privacyPolicy));
            }
            String termsOfService = Converters.str(options.get("terms_of_service_url"));
            if (!termsOfService.isEmpty()) {
                flow.setTermsOfServiceUri(Uri.parse(termsOfService));
            }
            String geography = Converters.str(options.get("debug_user_geography")).toLowerCase(Locale.ROOT);
            if (geography.equals("gdpr")) {
                flow.setDebugUserGeography(AppLovinSdkConfiguration.ConsentFlowUserGeography.GDPR);
            } else if (geography.equals("other")) {
                flow.setDebugUserGeography(AppLovinSdkConfiguration.ConsentFlowUserGeography.OTHER);
            }
        }
    }

    @UsedByGodot
    public boolean is_initialized() {
        Activity activity = getActivity();
        return activity != null && AppLovinSdk.getInstance(activity).isInitialized();
    }

    @UsedByGodot
    public Dictionary get_sdk_configuration() {
        if (!is_initialized()) {
            return new Dictionary();
        }
        return Converters.sdkConfiguration(sdk().getConfiguration());
    }

    @UsedByGodot
    public String get_sdk_version() {
        return AppLovinSdk.VERSION;
    }

    @UsedByGodot
    public String get_plugin_version() {
        return BuildConfig.PLUGIN_VERSION;
    }

    @UsedByGodot
    public void show_mediation_debugger() {
        runOnUiThread(() -> sdk().showMediationDebugger());
    }

    @UsedByGodot
    public void show_creative_debugger() {
        runOnUiThread(() -> sdk().showCreativeDebugger());
    }

    @UsedByGodot
    public void set_muted(boolean muted) {
        sdk().getSettings().setMuted(muted);
    }

    @UsedByGodot
    public boolean is_muted() {
        return sdk().getSettings().isMuted();
    }

    @UsedByGodot
    public void set_verbose_logging(boolean enabled) {
        sdk().getSettings().setVerboseLogging(enabled);
    }

    @UsedByGodot
    public void set_creative_debugger_enabled(boolean enabled) {
        sdk().getSettings().setCreativeDebuggerEnabled(enabled);
    }

    @UsedByGodot
    public void set_user_id(String userId) {
        sdk().getSettings().setUserIdentifier(userId);
    }

    @UsedByGodot
    public void set_extra_parameter(String key, String value) {
        sdk().getSettings().setExtraParameter(key, value);
    }

    // endregion

    // region Privacy

    @UsedByGodot
    public void set_has_user_consent(boolean consent) {
        AppLovinPrivacySettings.setHasUserConsent(consent);
    }

    @UsedByGodot
    public boolean has_user_consent() {
        return AppLovinPrivacySettings.hasUserConsent();
    }

    @UsedByGodot
    public boolean is_user_consent_set() {
        return AppLovinPrivacySettings.isUserConsentSet();
    }

    @UsedByGodot
    public void set_do_not_sell(boolean doNotSell) {
        AppLovinPrivacySettings.setDoNotSell(doNotSell);
    }

    @UsedByGodot
    public boolean is_do_not_sell() {
        return AppLovinPrivacySettings.isDoNotSell();
    }

    @UsedByGodot
    public boolean has_supported_cmp() {
        return sdk().getCmpService().hasSupportedCmp();
    }

    @UsedByGodot
    public void show_cmp_for_existing_user() {
        final Activity activity = getActivity();
        runOnUiThread(() -> sdk().getCmpService().showCmpForExistingUser(activity,
                error -> emit(CMP_FLOW_COMPLETED, Converters.cmpError(error))));
    }

    /** App Tracking Transparency only exists on iOS. */
    @UsedByGodot
    public void request_tracking_authorization() {
    }

    // endregion

    // region Interstitials

    @UsedByGodot
    public void load_interstitial(String adUnitId) {
        runOnUiThread(() -> interstitial(adUnitId).loadAd());
    }

    @UsedByGodot
    public boolean is_interstitial_ready(String adUnitId) {
        MaxInterstitialAd ad = interstitials.get(adUnitId);
        return ad != null && ad.isReady();
    }

    @UsedByGodot
    public void show_interstitial(String adUnitId, String placement, String customData) {
        final Activity activity = getActivity();
        runOnUiThread(() -> {
            MaxInterstitialAd ad = interstitials.get(adUnitId);
            if (ad == null) {
                Log.e(TAG, "show_interstitial(): ad unit " + adUnitId + " was never loaded");
                return;
            }
            ad.showAd(emptyToNull(placement), emptyToNull(customData), activity);
        });
    }

    @UsedByGodot
    public void set_interstitial_extra_parameter(String adUnitId, String key, String value) {
        runOnUiThread(() -> interstitial(adUnitId).setExtraParameter(key, value));
    }

    private MaxInterstitialAd interstitial(String adUnitId) {
        MaxInterstitialAd ad = interstitials.get(adUnitId);
        if (ad == null) {
            ad = new MaxInterstitialAd(adUnitId);
            ad.setListener(this);
            ad.setRevenueListener(this);
            interstitials.put(adUnitId, ad);
        }
        return ad;
    }

    // endregion

    // region Rewarded

    @UsedByGodot
    public void load_rewarded_ad(String adUnitId) {
        runOnUiThread(() -> rewarded(adUnitId).loadAd());
    }

    @UsedByGodot
    public boolean is_rewarded_ad_ready(String adUnitId) {
        MaxRewardedAd ad = rewardedAds.get(adUnitId);
        return ad != null && ad.isReady();
    }

    @UsedByGodot
    public void show_rewarded_ad(String adUnitId, String placement, String customData) {
        final Activity activity = getActivity();
        runOnUiThread(() -> {
            MaxRewardedAd ad = rewardedAds.get(adUnitId);
            if (ad == null) {
                Log.e(TAG, "show_rewarded_ad(): ad unit " + adUnitId + " was never loaded");
                return;
            }
            ad.showAd(emptyToNull(placement), emptyToNull(customData), activity);
        });
    }

    @UsedByGodot
    public void set_rewarded_ad_extra_parameter(String adUnitId, String key, String value) {
        runOnUiThread(() -> rewarded(adUnitId).setExtraParameter(key, value));
    }

    private MaxRewardedAd rewarded(String adUnitId) {
        MaxRewardedAd ad = rewardedAds.get(adUnitId);
        if (ad == null) {
            ad = MaxRewardedAd.getInstance(adUnitId);
            ad.setListener(this);
            ad.setRevenueListener(this);
            rewardedAds.put(adUnitId, ad);
        }
        return ad;
    }

    // endregion

    // region App open

    @UsedByGodot
    public void load_app_open_ad(String adUnitId) {
        runOnUiThread(() -> appOpen(adUnitId).loadAd());
    }

    @UsedByGodot
    public boolean is_app_open_ad_ready(String adUnitId) {
        MaxAppOpenAd ad = appOpenAds.get(adUnitId);
        return ad != null && ad.isReady();
    }

    @UsedByGodot
    public void show_app_open_ad(String adUnitId, String placement, String customData) {
        runOnUiThread(() -> {
            MaxAppOpenAd ad = appOpenAds.get(adUnitId);
            if (ad == null) {
                Log.e(TAG, "show_app_open_ad(): ad unit " + adUnitId + " was never loaded");
                return;
            }
            ad.showAd(emptyToNull(placement), emptyToNull(customData));
        });
    }

    @UsedByGodot
    public void set_app_open_ad_extra_parameter(String adUnitId, String key, String value) {
        runOnUiThread(() -> appOpen(adUnitId).setExtraParameter(key, value));
    }

    private MaxAppOpenAd appOpen(String adUnitId) {
        MaxAppOpenAd ad = appOpenAds.get(adUnitId);
        if (ad == null) {
            ad = new MaxAppOpenAd(adUnitId);
            ad.setListener(this);
            ad.setRevenueListener(this);
            appOpenAds.put(adUnitId, ad);
        }
        return ad;
    }

    // endregion

    // region Banners / MRECs

    /**
     * Creates and starts loading a banner ("banner"), leaderboard ("leader") or MREC ("mrec").
     * The view stays hidden until {@link #show_ad_view(String)} is called.
     */
    @UsedByGodot
    public void create_ad_view(String adUnitId, String format, String position, boolean adaptive) {
        final Activity activity = getActivity();
        runOnUiThread(() -> {
            if (overlay == null) {
                Log.e(TAG, "create_ad_view(): plugin overlay is not ready");
                return;
            }
            if (adViews.containsKey(adUnitId)) {
                Log.w(TAG, "create_ad_view(): ad view " + adUnitId + " already exists");
                return;
            }
            MaxAdFormat adFormat = adViewFormat(format);
            // Same as AppLovin's own Unity/Flutter plugins: tablets get the 728x90 leaderboard.
            if (adFormat == MaxAdFormat.BANNER && AppLovinSdkUtils.isTablet(activity)) {
                adFormat = MaxAdFormat.LEADER;
            }
            adViews.put(adUnitId, new AdViewController(activity, overlay, adUnitId, adFormat, position, adaptive, this, this));
        });
    }

    @UsedByGodot
    public void load_ad_view(String adUnitId) {
        withAdView(adUnitId, AdViewController::load);
    }

    @UsedByGodot
    public void show_ad_view(String adUnitId) {
        withAdView(adUnitId, AdViewController::show);
    }

    @UsedByGodot
    public void hide_ad_view(String adUnitId) {
        withAdView(adUnitId, AdViewController::hide);
    }

    @UsedByGodot
    public void destroy_ad_view(String adUnitId) {
        runOnUiThread(() -> {
            AdViewController controller = adViews.remove(adUnitId);
            if (controller != null) {
                controller.destroy();
            }
        });
    }

    @UsedByGodot
    public void set_ad_view_position(String adUnitId, String position) {
        withAdView(adUnitId, controller -> controller.setPosition(position));
    }

    @UsedByGodot
    public void set_ad_view_background_color(String adUnitId, String color) {
        withAdView(adUnitId, controller -> controller.setBackgroundColor(color));
    }

    @UsedByGodot
    public void set_ad_view_placement(String adUnitId, String placement) {
        withAdView(adUnitId, controller -> controller.getAdView().setPlacement(emptyToNull(placement)));
    }

    @UsedByGodot
    public void set_ad_view_custom_data(String adUnitId, String customData) {
        withAdView(adUnitId, controller -> controller.getAdView().setCustomData(emptyToNull(customData)));
    }

    @UsedByGodot
    public void set_ad_view_extra_parameter(String adUnitId, String key, String value) {
        withAdView(adUnitId, controller -> controller.getAdView().setExtraParameter(key, value));
    }

    @UsedByGodot
    public void start_ad_view_auto_refresh(String adUnitId) {
        withAdView(adUnitId, controller -> controller.setAutoRefresh(true));
    }

    @UsedByGodot
    public void stop_ad_view_auto_refresh(String adUnitId) {
        withAdView(adUnitId, controller -> controller.setAutoRefresh(false));
    }

    /** Returns {"width": px, "height": px}; empty if the ad view does not exist. */
    @UsedByGodot
    public Dictionary get_ad_view_size(String adUnitId) {
        Dictionary size = new Dictionary();
        AdViewController controller = adViews.get(adUnitId);
        if (controller != null) {
            int[] px = controller.getSizePx();
            size.put("width", px[0]);
            size.put("height", px[1]);
        }
        return size;
    }

    private interface AdViewAction {
        void run(AdViewController controller);
    }

    private void withAdView(String adUnitId, AdViewAction action) {
        runOnUiThread(() -> {
            AdViewController controller = adViews.get(adUnitId);
            if (controller == null) {
                Log.e(TAG, "Ad view " + adUnitId + " does not exist; call create_ad_view() first");
                return;
            }
            action.run(controller);
        });
    }

    private static MaxAdFormat adViewFormat(String format) {
        switch (format == null ? "" : format.toLowerCase(Locale.ROOT)) {
            case "mrec":
                return MaxAdFormat.MREC;
            case "leader":
                return MaxAdFormat.LEADER;
            default:
                return MaxAdFormat.BANNER;
        }
    }

    // endregion

    // region Listeners (called by the AppLovin SDK on the UI thread)

    @Override
    public void onAdLoaded(MaxAd ad) {
        emit(AD_LOADED, ad.getAdUnitId(), Converters.adInfo(ad));
    }

    @Override
    public void onAdLoadFailed(String adUnitId, MaxError error) {
        emit(AD_LOAD_FAILED, adUnitId, Converters.error(error));
    }

    @Override
    public void onAdDisplayed(MaxAd ad) {
        emit(AD_DISPLAYED, ad.getAdUnitId(), Converters.adInfo(ad));
    }

    @Override
    public void onAdDisplayFailed(MaxAd ad, MaxError error) {
        emit(AD_DISPLAY_FAILED, ad.getAdUnitId(), Converters.error(error), Converters.adInfo(ad));
    }

    @Override
    public void onAdClicked(MaxAd ad) {
        emit(AD_CLICKED, ad.getAdUnitId(), Converters.adInfo(ad));
    }

    @Override
    public void onAdHidden(MaxAd ad) {
        emit(AD_HIDDEN, ad.getAdUnitId(), Converters.adInfo(ad));
    }

    @Override
    public void onUserRewarded(MaxAd ad, MaxReward reward) {
        emit(AD_RECEIVED_REWARD, ad.getAdUnitId(), Converters.reward(reward), Converters.adInfo(ad));
    }

    @Override
    public void onAdExpanded(MaxAd ad) {
        emit(AD_EXPANDED, ad.getAdUnitId(), Converters.adInfo(ad));
    }

    @Override
    public void onAdCollapsed(MaxAd ad) {
        emit(AD_COLLAPSED, ad.getAdUnitId(), Converters.adInfo(ad));
    }

    @Override
    public void onAdRevenuePaid(MaxAd ad) {
        emit(AD_REVENUE_PAID, ad.getAdUnitId(), Converters.adInfo(ad));
    }

    // endregion

    /** Signals are emitted on Godot's render thread so GDScript handlers run on the main loop. */
    private void emit(SignalInfo signal, Object... args) {
        runOnRenderThread(() -> emitSignal(signal.getName(), args));
    }

    private AppLovinSdk sdk() {
        return AppLovinSdk.getInstance(getActivity());
    }

    private static String emptyToNull(String value) {
        return value == null || value.isEmpty() ? null : value;
    }

    @SuppressWarnings("deprecation")
    private static void applySafeAreaPadding(View view, WindowInsets insets) {
        int left = 0, top = 0, right = 0, bottom = 0;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            android.graphics.Insets safe = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            left = safe.left;
            top = safe.top;
            right = safe.right;
            bottom = safe.bottom;
        } else {
            left = insets.getSystemWindowInsetLeft();
            top = insets.getSystemWindowInsetTop();
            right = insets.getSystemWindowInsetRight();
            bottom = insets.getSystemWindowInsetBottom();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                DisplayCutout cutout = insets.getDisplayCutout();
                if (cutout != null) {
                    left = Math.max(left, cutout.getSafeInsetLeft());
                    top = Math.max(top, cutout.getSafeInsetTop());
                    right = Math.max(right, cutout.getSafeInsetRight());
                    bottom = Math.max(bottom, cutout.getSafeInsetBottom());
                }
            }
        }
        view.setPadding(left, top, right, bottom);
    }
}
