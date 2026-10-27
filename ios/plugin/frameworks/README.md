# Mediation adapters (iOS)

Put the `.xcframework` (or `.framework`) files of your AppLovin mediation adapters and of
the ad network SDKs they depend on in this folder, e.g.:

```
ios/plugins/applovin_max/frameworks/
  AppLovinMediationGoogleAdapter.xcframework
  GoogleMobileAds.xcframework
  UserMessagingPlatform.xcframework
```

Every framework found here is added to the Xcode project on export: static frameworks are
linked (and their `.bundle` resources copied), dynamic frameworks are embedded.

Adapters are published by AppLovin on CocoaPods (`AppLovinMediation<Network>Adapter`);
the podspec of each adapter lists the download URL of the framework and the version of the
network SDK it requires. See the "Mediation" section of the plugin README.
