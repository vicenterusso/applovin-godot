package com.vicenterusso.godot.applovinmax;

import android.app.Activity;
import android.graphics.Color;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import com.applovin.mediation.MaxAdFormat;
import com.applovin.mediation.MaxAdRevenueListener;
import com.applovin.mediation.MaxAdViewAdListener;
import com.applovin.mediation.MaxAdViewConfiguration;
import com.applovin.mediation.ads.MaxAdView;
import com.applovin.sdk.AppLovinSdkUtils;

import java.util.Locale;

/**
 * Wraps one banner / leader / MREC {@link MaxAdView} and its placement inside the
 * plugin overlay. All methods must be called on the UI thread.
 */
final class AdViewController {
    private static final String TAG = "GodotAppLovinMax";

    private final Activity activity;
    private final FrameLayout container;
    private final MaxAdFormat format;
    private final MaxAdView adView;
    private final boolean adaptive;

    private String position;
    private boolean autoRefreshEnabled = true;
    private boolean visible = false;

    AdViewController(Activity activity, FrameLayout container, String adUnitId, MaxAdFormat format,
            String position, boolean adaptive, MaxAdViewAdListener listener, MaxAdRevenueListener revenueListener) {
        this.activity = activity;
        this.container = container;
        this.format = format;
        this.position = position;
        this.adaptive = adaptive && format != MaxAdFormat.MREC;

        if (this.adaptive) {
            MaxAdViewConfiguration configuration = MaxAdViewConfiguration.builder()
                    .setAdaptiveType(MaxAdViewConfiguration.AdaptiveType.ANCHORED)
                    .build();
            adView = new MaxAdView(adUnitId, format, configuration);
        } else {
            adView = new MaxAdView(adUnitId, format);
        }
        adView.setListener(listener);
        adView.setRevenueListener(revenueListener);
        adView.setBackgroundColor(Color.TRANSPARENT);
        // Lets stopAutoRefresh() take effect right away while the view is hidden.
        adView.setExtraParameter("allow_pause_auto_refresh_immediately", "true");
        adView.setVisibility(View.GONE);

        container.addView(adView, buildLayoutParams());

        adView.stopAutoRefresh();
        adView.loadAd();
    }

    MaxAdView getAdView() {
        return adView;
    }

    void load() {
        adView.loadAd();
    }

    void show() {
        visible = true;
        adView.setVisibility(View.VISIBLE);
        if (autoRefreshEnabled) {
            adView.startAutoRefresh();
        }
    }

    void hide() {
        visible = false;
        adView.setVisibility(View.GONE);
        adView.stopAutoRefresh();
    }

    void destroy() {
        container.removeView(adView);
        adView.setListener(null);
        adView.setRevenueListener(null);
        adView.destroy();
    }

    void setPosition(String position) {
        this.position = position;
        adView.setLayoutParams(buildLayoutParams());
    }

    void setBackgroundColor(String color) {
        try {
            adView.setBackgroundColor(Color.parseColor(color));
        } catch (IllegalArgumentException e) {
            Log.w(TAG, "Invalid ad view background color: " + color);
        }
    }

    void setAutoRefresh(boolean enabled) {
        autoRefreshEnabled = enabled;
        if (enabled && visible) {
            adView.startAutoRefresh();
        } else {
            adView.stopAutoRefresh();
        }
    }

    /** Width and height of the ad view in physical pixels (same unit as the Godot window). */
    int[] getSizePx() {
        int width = adView.getWidth();
        int height = adView.getHeight();
        if (width <= 0 || height <= 0) {
            ViewGroup.LayoutParams params = buildLayoutParams();
            width = params.width > 0 ? params.width : container.getWidth();
            height = params.height;
        }
        return new int[] { width, height };
    }

    private FrameLayout.LayoutParams buildLayoutParams() {
        int widthDp;
        int heightDp;
        if (format == MaxAdFormat.MREC) {
            widthDp = 300;
            heightDp = 250;
        } else {
            boolean leader = format == MaxAdFormat.LEADER;
            widthDp = leader ? 728 : 320;
            heightDp = leader ? 90 : 50;
            if (adaptive) {
                heightDp = format.getAdaptiveSize(activity).getHeight();
            }
        }

        int gravity = gravityFor(position);
        boolean horizontallyCentered = (gravity & Gravity.HORIZONTAL_GRAVITY_MASK) == Gravity.CENTER_HORIZONTAL;
        // Banners stretch across the screen when centered horizontally, as recommended by AppLovin.
        int width = (format != MaxAdFormat.MREC && horizontallyCentered)
                ? ViewGroup.LayoutParams.MATCH_PARENT
                : AppLovinSdkUtils.dpToPx(activity, widthDp);
        int height = AppLovinSdkUtils.dpToPx(activity, heightDp);

        return new FrameLayout.LayoutParams(width, height, gravity);
    }

    static int gravityFor(String position) {
        switch (position == null ? "" : position.toLowerCase(Locale.ROOT)) {
            case "top_left":
                return Gravity.TOP | Gravity.LEFT;
            case "top_center":
                return Gravity.TOP | Gravity.CENTER_HORIZONTAL;
            case "top_right":
                return Gravity.TOP | Gravity.RIGHT;
            case "center_left":
                return Gravity.CENTER_VERTICAL | Gravity.LEFT;
            case "centered":
            case "center":
                return Gravity.CENTER;
            case "center_right":
                return Gravity.CENTER_VERTICAL | Gravity.RIGHT;
            case "bottom_left":
                return Gravity.BOTTOM | Gravity.LEFT;
            case "bottom_right":
                return Gravity.BOTTOM | Gravity.RIGHT;
            case "bottom_center":
            default:
                return Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        }
    }
}
