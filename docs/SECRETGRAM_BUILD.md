# SecretGram для iOS

Исходники из предоставленного архива Jerkgram переработаны в SecretGram. Это исходный код, **не собранный и не проверенный IPA**.

## Изменения

- Название SecretGram в приложении, настройках, разрешениях iOS, основных модулях и ресурсах.
- Приложенная иконка с самолётом и замком; подготовлены размеры ресурсов и превью.
- Настройки → SecretGram → Плагины: импорт `.plugin`/`.dex`, сведения о формате, хранение по аккаунтам, удаление. **Выполнение Android-плагинов отсутствует.** [Подробности](SECRETGRAM_PLUGINS.md).
- Удалены обращения к серверу аналитики и каналам исходного приложения.

## Сборка на Mac

Версии, указанные исходным проектом в `versions.json`: macOS 26, Xcode 26.2, Bazel 8.4.2, Telegram 12.9.2. Сборка iOS и Swift-тесты в текущей Windows-среде не выполнялись.

1. Распакуйте `SecretGram-iOS-source.zip` на Mac. Архив сохраняет Unix-ссылки и режимы исходных файлов.
2. Скопируйте `build-system/secretgram-configuration.example.json` в `build-system/secretgram-configuration.json`. Заполните собственные `api_id`/`api_hash` с [my.telegram.org](https://my.telegram.org/apps), Apple Team ID и уникальный Bundle ID. `app.secretgram.ios` — пример, не зарегистрированная идентичность.
3. Создайте Xcode-проект для симулятора:

   ```sh
   python3 build-system/Make/Make.py --cacheDir "$HOME/secretgram-bazel-cache" generateProject \
     --configurationPath build-system/secretgram-configuration.json \
     --xcodeManagedCodesigning --disableProvisioningProfiles
   ```

4. Откройте созданный проект, выберите симулятор и выполните Build. Зависимости сборки требуют сети. Для устройства создайте проект без `--disableProvisioningProfiles`, настройте подпись приложения и расширений/App Groups своим Apple-аккаунтом. Затем соберите Archive и экспортируйте IPA через Xcode.
5. Выполните `sh scripts/test-secretgram-plugins.sh` и ручные проверки из [документации плагинов](SECRETGRAM_PLUGINS.md).

Проект использует новую конфигурацию и пространство имён SecretGram. Перенос локальных данных/резервных копий установленного Jerkgram не реализован; используйте отдельную установку. Протокольные модули Telegram оставлены под своими именами для совместимости с системой сборки.

## Происхождение

Сохранены лицензия, авторство зависимостей, UPSTREAM.md и [оригинальные сведения Jerkgram](upstream/README_RU.md). Остальные унаследованные документы релизов и разработки описывают историю исходного проекта, а не подтверждённые релизы SecretGram. Старые SHA-256 релизов не относятся к этому изменённому коду.
