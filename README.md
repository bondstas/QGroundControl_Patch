# QGroundControl Chupacabra GStreamer Patch

Патч обновляет GStreamer/RTSP в кастомной сборке **3 Assault Brigade / NOVA – Chupacabra Squad QGroundControl**, сохраняя кастомный `QGroundControl.exe` и функции управления камерой.

Исправленная проблема: старый GStreamer 1.22.12 не завершает Digest-аутентификацию RTSP с некоторыми камерами Dahua и не получает SDP. Проверенный новый runtime позволяет воспроизводить тот же поток.

## Однокомандная установка

Запустите PowerShell **от имени администратора**:

```powershell
irm https://raw.githubusercontent.com/bondstas/QGroundControl_Patch/main/install.ps1 | iex
```

Установщик:

- требует закрыть все процессы QGroundControl;
- скачивает Release-архив;
- проверяет SHA-256 архива и каждого файла;
- делает полную резервную копию в `C:\QGC-Backups`;
- заменяет только файлы из подписанного хешами манифеста;
- проверяет, что кастомный `QGroundControl.exe` не изменился;
- автоматически откатывается при ошибке.

## Публикация Release

На ПК, где установлен проверенный QGC 5.1 runtime:

```powershell
winget install GitHub.cli
gh auth login
powershell -ExecutionPolicy Bypass -File .\build-release.ps1
```

Скрипт создаст `v1.0.0` Release с ZIP-архивом и SHA-256. Бинарные DLL не хранятся непосредственно в истории Git.

## Пути по умолчанию

- Chupacabra: `C:\Program Files\QGroundControl`
- источник нового runtime: `C:\Program Files\QGroundContro_workl`
- резервные копии: `C:\QGC-Backups`

