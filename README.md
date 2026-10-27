# AppLovin MAX para Godot 4 (Android + iOS)

Plugin de anúncios **AppLovin MAX** para **Godot 4.3+**, construído sobre os **SDKs oficiais da AppLovin**
(Android e iOS 13.6.4). Substitui os plugins antigos que pararam de funcionar nas versões recentes do Godot.

- **Android**: plugin Android v2 do Godot (AAR + Gradle). O SDK da AppLovin e os adaptadores de mediação são
  baixados pelo Gradle no momento do export, então trocar de versão é só mudar uma opção do preset.
- **iOS**: plugin `.gdip` oficial do Godot, compilado **com as mesmas flags do engine** para cada versão do
  Godot suportada (4.3, 4.4, 4.5, 4.6 e 4.7).
- **Mesma API GDScript** nas duas plataformas, via autoload `AppLovinMax`. No editor/desktop todas as chamadas
  viram no-op, então o jogo roda normalmente sem `if OS.get_name() == ...`.

## Recursos

| Formato / recurso | Android | iOS |
| --- | --- | --- |
| Interstitial | ✅ | ✅ |
| Rewarded | ✅ | ✅ |
| App Open | ✅ | ✅ |
| Banner (adaptativo) / Leaderboard | ✅ | ✅ |
| MREC (300x250) | ✅ | ✅ |
| Fluxo de consentimento MAX (Termos e Política de Privacidade, UMP/CMP) | ✅ | ✅ |
| `has_user_consent` / `do_not_sell` | ✅ | ✅ |
| App Tracking Transparency (ATT) + SKAdNetwork | — | ✅ |
| Mediation Debugger / Creative Debugger | ✅ | ✅ |
| Callback de receita (impression-level revenue) | ✅ | ✅ |

## Instalação

1. Baixe o zip da [release](../../releases) **correspondente à sua versão do Godot**
   (ex.: `godot-applovin-max-v1.0.0-godot-4.5.2.zip` para Godot 4.5.x).
2. Extraia na raiz do projeto. Você terá:
   ```
   addons/applovin_max/          # editor plugin, autoload e AARs Android
   ios/plugins/applovin_max/     # plugin iOS (.gdip + xcframeworks)
   ```
3. Em **Projeto > Configurações do Projeto > Plugins**, ative **AppLovin MAX**.
   Isso registra o autoload `AppLovinMax`.
4. Só para iOS: **Projeto > Ferramentas > AppLovin MAX: Download iOS SDK**. Isso baixa o
   `AppLovinSDK.xcframework` oficial para `res://ios/plugins/applovin_max/`.

> O plugin iOS é compilado contra os headers de uma versão específica do Godot. Use sempre o zip da mesma
> versão *minor* (4.3, 4.4, ...) do editor/templates que você usa para exportar.

### Android

No preset de exportação Android:

- Marque **Gradle Build > Use Gradle Build** e instale o template de build Android
  (**Projeto > Instalar Template de Build Android**).
- **Min SDK** precisa ser **24** ou maior (exigência do SDK AppLovin 13).
- Opções em **applovin_max/android**:
  - `enabled` — inclui o plugin neste preset.
  - `sdk_version` — versão do `com.applovin:applovin-sdk` (padrão `13.6.4`).
  - `mediation_dependencies` — adaptadores de mediação, ex.:
    `com.applovin.mediation:google-adapter:+`, `com.applovin.mediation:unityads-adapter:+`.
  - `maven_repositories` — repositórios extras que alguns adaptadores exigem
    (ex.: `https://artifact.bytedance.com/repository/pangle` para Pangle).
  - `admob_app_id` — obrigatório se usar o adaptador do Google (AdMob); vira o meta-data
    `com.google.android.gms.ads.APPLICATION_ID`.

### iOS

No preset de exportação iOS:

- Em **Plugins**, marque **AppLovinMax**.
- Opções em **applovin_max/ios**:
  - `user_tracking_usage_description` — texto do prompt do ATT (`NSUserTrackingUsageDescription`).
    Deixe vazio para não adicionar.
  - `skadnetwork_ids` — `SKAdNetworkItems`. Já vem com o ID da AppLovin (`ludvb6z3bs.skadnetwork`);
    adicione os IDs das redes que você usa na mediação (a AppLovin publica a lista completa no dashboard/documentação).
  - `admob_app_id` — `GADApplicationIdentifier`, obrigatório se usar o adaptador do Google.
- Adaptadores de mediação: coloque os `.xcframework` em `res://ios/plugins/applovin_max/frameworks/`
  (veja [`ios/plugin/frameworks/README.md`](ios/plugin/frameworks/README.md)). Frameworks estáticos são
  linkados (e seus `.bundle` copiados) e dinâmicos são embutidos automaticamente.

## Uso

```gdscript
extends Node

const SDK_KEY := "SUA_SDK_KEY"

var INTERSTITIAL_ID := "ID_ANDROID" if OS.get_name() == "Android" else "ID_IOS"
var REWARDED_ID := "ID_ANDROID" if OS.get_name() == "Android" else "ID_IOS"
var BANNER_ID := "ID_ANDROID" if OS.get_name() == "Android" else "ID_IOS"


func _ready() -> void:
	AppLovinMax.sdk_initialized.connect(_on_sdk_initialized)
	AppLovinMax.ad_loaded.connect(func(id, info): print("carregou ", id, " via ", info.network_name))
	AppLovinMax.ad_load_failed.connect(_on_ad_load_failed)
	AppLovinMax.ad_hidden.connect(_on_ad_hidden)
	AppLovinMax.ad_received_reward.connect(_on_reward)

	AppLovinMax.initialize(SDK_KEY, {
		"verbose_logging": OS.is_debug_build(),
		# Fluxo de consentimento da AppLovin (GDPR/UMP + ATT no iOS):
		"terms_and_privacy_policy_flow": true,
		"privacy_policy_url": "https://seusite.com/privacidade",
		"terms_of_service_url": "https://seusite.com/termos",
	})


func _on_sdk_initialized(config: Dictionary) -> void:
	print("AppLovin pronto, país: ", config.country_code)
	AppLovinMax.load_interstitial(INTERSTITIAL_ID)
	AppLovinMax.load_rewarded_ad(REWARDED_ID)
	AppLovinMax.create_banner(BANNER_ID, AppLovinMax.AdViewPosition.BOTTOM_CENTER)
	AppLovinMax.set_ad_view_background_color(BANNER_ID, Color.BLACK)
	AppLovinMax.show_banner(BANNER_ID)


func show_interstitial() -> void:
	if AppLovinMax.is_interstitial_ready(INTERSTITIAL_ID):
		AppLovinMax.show_interstitial(INTERSTITIAL_ID)


func show_rewarded() -> void:
	if AppLovinMax.is_rewarded_ad_ready(REWARDED_ID):
		AppLovinMax.show_rewarded_ad(REWARDED_ID, "continue_level")


func _on_reward(ad_unit_id: String, reward: Dictionary, _ad_info: Dictionary) -> void:
	print("Recompensa: ", reward.amount, " ", reward.label)


func _on_ad_hidden(ad_unit_id: String, _ad_info: Dictionary) -> void:
	# Pré-carrega o próximo anúncio.
	if ad_unit_id == INTERSTITIAL_ID:
		AppLovinMax.load_interstitial(INTERSTITIAL_ID)
	elif ad_unit_id == REWARDED_ID:
		AppLovinMax.load_rewarded_ad(REWARDED_ID)


func _on_ad_load_failed(ad_unit_id: String, error: Dictionary) -> void:
	# A AppLovin recomenda tentar de novo com backoff exponencial.
	push_warning("Falha ao carregar %s: %s" % [ad_unit_id, error.message])
	await get_tree().create_timer(5.0).timeout
	if ad_unit_id == INTERSTITIAL_ID:
		AppLovinMax.load_interstitial(ad_unit_id)
	elif ad_unit_id == REWARDED_ID:
		AppLovinMax.load_rewarded_ad(ad_unit_id)
```

> **Áudio no iOS**: no iOS o jogo continua rodando enquanto um anúncio em tela cheia está aberto. Use
> `ad_displayed` / `ad_hidden` para pausar o jogo e silenciar o áudio (no Android a activity é pausada
> automaticamente).

## API

Todas as funções estão em `AppLovinMax` (`addons/applovin_max/applovin_max.gd`).

### SDK

| Função | Descrição |
| --- | --- |
| `is_available() -> bool` | `true` em builds Android/iOS com o plugin nativo. |
| `initialize(sdk_key, config = {})` | Inicializa o SDK. Emite `sdk_initialized`. Chaves de `config` abaixo. |
| `is_initialized() -> bool` | |
| `get_sdk_configuration() -> Dictionary` | `country_code`, `consent_flow_user_geography` (`gdpr`/`other`/`unknown`), `is_test_mode_enabled`, `app_tracking_status` (iOS). |
| `get_sdk_version()` / `get_plugin_version()` | |
| `show_mediation_debugger()` / `show_creative_debugger()` | Ferramentas de debug da AppLovin. |
| `set_muted(bool)`, `is_muted()`, `set_verbose_logging(bool)`, `set_creative_debugger_enabled(bool)`, `set_user_id(String)`, `set_extra_parameter(key, value)` | |

Chaves de `config` em `initialize` (todas opcionais): `test_device_advertising_ids` (Array de GAID/IDFA),
`ad_unit_ids` (Array), `verbose_logging`, `muted`, `creative_debugger_enabled`, `user_id`,
`has_user_consent`, `do_not_sell`, `terms_and_privacy_policy_flow`, `privacy_policy_url`,
`terms_of_service_url`, `debug_user_geography` (`"gdpr"`/`"other"`, para testar o fluxo de consentimento),
`extra_parameters` (Dictionary).

### Privacidade

| Função | Descrição |
| --- | --- |
| `set_has_user_consent(bool)`, `has_user_consent()`, `is_user_consent_set()` | GDPR. |
| `set_do_not_sell(bool)`, `is_do_not_sell()` | CCPA. |
| `has_supported_cmp()` / `show_cmp_for_existing_user()` | Reabre o CMP (ex.: Google UMP). Emite `cmp_flow_completed`. |
| `request_tracking_authorization()` | iOS 14+: prompt do ATT (desnecessário se usar o fluxo de consentimento MAX). Emite `tracking_authorization_completed`. |

### Anúncios em tela cheia

| Interstitial | Rewarded | App Open |
| --- | --- | --- |
| `load_interstitial(id)` | `load_rewarded_ad(id)` | `load_app_open_ad(id)` |
| `is_interstitial_ready(id)` | `is_rewarded_ad_ready(id)` | `is_app_open_ad_ready(id)` |
| `show_interstitial(id, placement = "", custom_data = "")` | `show_rewarded_ad(id, placement = "", custom_data = "")` | `show_app_open_ad(id, placement = "", custom_data = "")` |
| `set_interstitial_extra_parameter(id, key, value)` | `set_rewarded_ad_extra_parameter(id, key, value)` | `set_app_open_ad_extra_parameter(id, key, value)` |

### Banners e MRECs

Banners/MRECs são criados uma vez (ocultos, já carregando) e depois exibidos/ocultados. Em tablets, `banner`
usa automaticamente o tamanho leaderboard (728x90), como nos plugins oficiais da AppLovin para Unity/Flutter.

| Função | Descrição |
| --- | --- |
| `create_banner(id, position = BOTTOM_CENTER, adaptive = true)` | Banner adaptativo ancorado (recomendado). |
| `create_mrec(id, position = CENTERED)` | MREC 300x250. |
| `create_ad_view(id, format, position, adaptive = true)` | `format`: `"banner"`, `"leader"` ou `"mrec"`. |
| `show_ad_view(id)` / `hide_ad_view(id)` / `destroy_ad_view(id)` | Também: `show_banner`, `hide_banner`, `destroy_banner`, `show_mrec`, `hide_mrec`, `destroy_mrec`. |
| `set_ad_view_position(id, position)` | `AppLovinMax.AdViewPosition`: `TOP_LEFT`, `TOP_CENTER`, `TOP_RIGHT`, `CENTER_LEFT`, `CENTERED`, `CENTER_RIGHT`, `BOTTOM_LEFT`, `BOTTOM_CENTER`, `BOTTOM_RIGHT`. |
| `set_ad_view_background_color(id, Color)` | Cor de fundo (banners centralizados ocupam a largura toda). |
| `set_ad_view_placement(id, placement)`, `set_ad_view_custom_data(id, data)`, `set_ad_view_extra_parameter(id, key, value)` | |
| `start_ad_view_auto_refresh(id)` / `stop_ad_view_auto_refresh(id)` / `load_ad_view(id)` | |
| `get_ad_view_size(id) -> Vector2i` | Tamanho em pixels da tela (útil para afastar a UI do banner). |

As posições respeitam a safe area (notch, barra de navegação).

### Sinais

| Sinal | Argumentos |
| --- | --- |
| `sdk_initialized` | `sdk_configuration: Dictionary` |
| `ad_loaded` | `ad_unit_id: String, ad_info: Dictionary` |
| `ad_load_failed` | `ad_unit_id: String, error_info: Dictionary` |
| `ad_displayed` | `ad_unit_id, ad_info` |
| `ad_display_failed` | `ad_unit_id, error_info, ad_info` |
| `ad_clicked` / `ad_hidden` | `ad_unit_id, ad_info` |
| `ad_revenue_paid` | `ad_unit_id, ad_info` (use `ad_info.revenue` para analytics) |
| `ad_received_reward` | `ad_unit_id, reward ({label, amount}), ad_info` |
| `ad_expanded` / `ad_collapsed` | `ad_unit_id, ad_info` (banners/MRECs) |
| `cmp_flow_completed` | `error_info` (vazio se deu certo) |
| `tracking_authorization_completed` | `status`: `authorized`, `denied`, `restricted`, `not_determined`, `unavailable` |

`ad_info`: `ad_unit_id`, `format` (`interstitial`, `rewarded`, `app_open`, `banner`, `leader`, `mrec`),
`network_name`, `network_placement`, `placement`, `creative_id`, `revenue`, `revenue_precision`, `dsp_name`,
`latency_millis`.

`error_info`: `code`, `message`, `mediated_network_error_code`, `mediated_network_error_message`,
`latency_millis`.

## Compilando a partir do código

```
android/   projeto Gradle do plugin Android (Java)
ios/       código Objective-C++ do plugin iOS, .gdip e scripts de build
addons/    editor plugin, export plugin e autoload (GDScript)
ci/        checagem de GDScript usada no CI
```

**Android** (JDK 17 + Android SDK):

```sh
cd android
./gradlew assemble        # gera e copia os AARs para addons/applovin_max/bin/android/
```

**iOS** (macOS + Xcode, `scons` e `python3`):

```sh
ios/scripts/build.sh 4.5.2-stable              # -> ios/bin/4.5.2-stable/
cp -R ios/bin/4.5.2-stable/* <seu_projeto>/ios/plugins/applovin_max/
```

O script clona o Godot na tag pedida, gera o `compile_commands.json` do engine para extrair exatamente as
mesmas flags/defines de compilação dos export templates (debug e release, device e simulator), baixa os headers
do SDK da AppLovin e cria `applovin_max.debug.xcframework` e `applovin_max.release.xcframework`.

O workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) faz tudo isso e, em tags `v*`,
publica uma release com um zip por versão do Godot.

## Licença

MIT. Os SDKs da AppLovin não fazem parte deste repositório e seguem a licença da AppLovin
(<https://www.applovin.com/eula>). Projeto não oficial, sem vínculo com a AppLovin.
