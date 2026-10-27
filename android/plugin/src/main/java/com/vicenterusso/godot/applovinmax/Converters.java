package com.vicenterusso.godot.applovinmax;

import com.applovin.mediation.MaxAd;
import com.applovin.mediation.MaxAdFormat;
import com.applovin.mediation.MaxError;
import com.applovin.mediation.MaxReward;
import com.applovin.sdk.AppLovinCmpError;
import com.applovin.sdk.AppLovinSdkConfiguration;

import org.godotengine.godot.Dictionary;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Converts AppLovin SDK objects into Godot dictionaries.
 * Keys are kept identical to the iOS implementation (ios/src/applovin_max.mm).
 */
final class Converters {
    private Converters() {}

    static Dictionary adInfo(MaxAd ad) {
        Dictionary info = new Dictionary();
        if (ad == null) {
            return info;
        }
        info.put("ad_unit_id", str(ad.getAdUnitId()));
        info.put("format", formatName(ad.getFormat()));
        info.put("network_name", str(ad.getNetworkName()));
        info.put("network_placement", str(ad.getNetworkPlacement()));
        info.put("placement", str(ad.getPlacement()));
        info.put("creative_id", str(ad.getCreativeId()));
        info.put("revenue", ad.getRevenue());
        info.put("revenue_precision", str(ad.getRevenuePrecision()));
        info.put("dsp_name", str(ad.getDspName()));
        info.put("latency_millis", (int) ad.getRequestLatencyMillis());
        return info;
    }

    static Dictionary error(MaxError error) {
        Dictionary info = new Dictionary();
        if (error == null) {
            return info;
        }
        info.put("code", error.getCode());
        info.put("message", str(error.getMessage()));
        info.put("mediated_network_error_code", error.getMediatedNetworkErrorCode());
        info.put("mediated_network_error_message", str(error.getMediatedNetworkErrorMessage()));
        info.put("latency_millis", (int) error.getRequestLatencyMillis());
        return info;
    }

    static Dictionary cmpError(AppLovinCmpError error) {
        Dictionary info = new Dictionary();
        if (error == null) {
            return info;
        }
        info.put("code", error.getCode() != null ? error.getCode().ordinal() : -1);
        info.put("code_name", error.getCode() != null ? error.getCode().name() : "");
        info.put("message", str(error.getMessage()));
        info.put("cmp_code", error.getCmpCode());
        info.put("cmp_message", str(error.getCmpMessage()));
        return info;
    }

    static Dictionary reward(MaxReward reward) {
        Dictionary info = new Dictionary();
        info.put("label", reward != null ? str(reward.getLabel()) : "");
        info.put("amount", reward != null ? reward.getAmount() : 0);
        return info;
    }

    static Dictionary sdkConfiguration(AppLovinSdkConfiguration configuration) {
        Dictionary info = new Dictionary();
        if (configuration == null) {
            return info;
        }
        info.put("country_code", str(configuration.getCountryCode()));
        AppLovinSdkConfiguration.ConsentFlowUserGeography geography = configuration.getConsentFlowUserGeography();
        info.put("consent_flow_user_geography", geography != null ? geography.name().toLowerCase(Locale.ROOT) : "unknown");
        info.put("is_test_mode_enabled", configuration.isTestModeEnabled());
        // iOS only; kept for a uniform dictionary layout.
        info.put("app_tracking_status", "unavailable");
        return info;
    }

    static String formatName(MaxAdFormat format) {
        if (format == null) {
            return "";
        }
        if (format == MaxAdFormat.BANNER) return "banner";
        if (format == MaxAdFormat.MREC) return "mrec";
        if (format == MaxAdFormat.LEADER) return "leader";
        if (format == MaxAdFormat.INTERSTITIAL) return "interstitial";
        if (format == MaxAdFormat.REWARDED) return "rewarded";
        if (format == MaxAdFormat.APP_OPEN) return "app_open";
        if (format == MaxAdFormat.NATIVE) return "native";
        return format.getLabel().toLowerCase(Locale.ROOT);
    }

    /** Accepts the shapes Godot uses to pass arrays to Java (Object[], String[]). */
    static List<String> stringList(Object value) {
        List<String> result = new ArrayList<>();
        if (value instanceof Object[]) {
            for (Object item : (Object[]) value) {
                if (item != null) {
                    result.add(item.toString());
                }
            }
        } else if (value instanceof Iterable) {
            for (Object item : (Iterable<?>) value) {
                if (item != null) {
                    result.add(item.toString());
                }
            }
        } else if (value instanceof String && !((String) value).isEmpty()) {
            result.add((String) value);
        }
        return result;
    }

    static boolean bool(Object value, boolean fallback) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        if (value instanceof Number) {
            return ((Number) value).intValue() != 0;
        }
        return fallback;
    }

    static String str(Object value) {
        return value != null ? value.toString() : "";
    }
}
