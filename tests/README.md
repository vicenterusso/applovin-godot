# Testes de integração (ponta a ponta)

Rodam no CI (`.github/workflows/build.yml`) para **cada versão suportada do Godot** (4.3, 4.4.1, 4.5.2,
4.6.3, 4.7.2), sempre com o **editor e os export templates oficiais** baixados do GitHub do Godot.

| Job | O que prova |
| --- | --- |
| `GDScript` | Todos os scripts do addon carregam no editor 4.3 e 4.7 sem erro; no desktop a API é no-op. |
| `Android E2E` | O Godot exporta um APK com Gradle usando o plugin (v2); o manifest final contém o plugin, o SDK da AppLovin e o AdMob App ID; o app roda num **emulador Android** e passa no teste em aparelho. |
| `iOS E2E` | O instalador do editor baixa o SDK iOS oficial; o Godot exporta o projeto Xcode com o `.gdip`; o projeto tem SDK embutido, flags de link e Info.plist corretos; o `xcodebuild` **linka contra o template oficial** (onde o plugin oficial da AppLovin falha com "Undefined symbols"); o app roda no **Simulador iOS** e passa no teste em aparelho. |

## Teste em aparelho (`project/test_runner.gd`)

O app de teste percorre a cadeia inteira GDScript → autoload `AppLovinMax` → plugin nativo → SDK da
AppLovin → callbacks nativos → sinais do Godot:

- singleton nativo presente, todos os sinais registrados (e, no iOS, todos os métodos);
- versão do SDK (13.x) e do plugin;
- privacidade (`has_user_consent`, `do_not_sell`), `muted` e demais setters;
- `initialize()` → sinal `sdk_initialized` com a configuração; segundo `initialize()` reemite o sinal;
- interstitial, rewarded e app open: `load_*` → `ad_loaded` **ou** `ad_load_failed` com os campos esperados,
  e `is_*_ready()` coerente com o callback;
- banner e MREC: criação, tamanho/proporção na tela, cor, posição, placement, auto refresh, callback de
  carregamento, `hide` e `destroy`.

O resultado vai para o log (`[ALTEST] ...`) e para `user://applovin_test_result.txt`; a última linha é
`[ALTEST] RESULT PASS` ou `[ALTEST] RESULT FAIL (n)`.

### Chave real (opcional)

Sem configuração, o teste usa uma SDK key fictícia: a AppLovin responde aos pedidos com erro de carregamento,
o que ainda exercita todos os callbacks. Para testar com a sua conta (anúncios de teste de verdade), crie estes
*secrets* no repositório:

- `APPLOVIN_SDK_KEY`
- `APPLOVIN_TEST_DEVICE_IDS` (opcional, separados por vírgula)
- `APPLOVIN_ANDROID_{INTERSTITIAL,REWARDED,APP_OPEN,BANNER,MREC}_ID`
- `APPLOVIN_IOS_{INTERSTITIAL,REWARDED,APP_OPEN,BANNER,MREC}_ID`

## Rodando localmente

```sh
# Android (Linux/macOS, com Android SDK e um emulador/aparelho conectado)
tests/ci/install_godot.sh linux 4.5.2-stable android_source.zip   # ou use seu Godot: export GODOT=...
(cd android && ./gradlew assemble)
tests/prepare_project.sh
tests/ci/export_android.sh
tests/ci/run_android_test.sh tests/project/build/android/applovin_max_test.apk

# iOS (macOS com Xcode)
ios/scripts/build.sh 4.5.2-stable
tests/ci/install_godot.sh macos 4.5.2-stable ios.zip
tests/prepare_project.sh ios/bin/4.5.2-stable
(cd tests/project && APPLOVIN_CI_INSTALL_IOS_SDK=13.6.4 "$GODOT" --headless --editor --path . \
  && "$GODOT" --headless --import \
  && "$GODOT" --headless --export-debug iOS "$PWD/build/ios/AppLovinMaxTest.ipa")
tests/ci/run_ios_test.sh
```
