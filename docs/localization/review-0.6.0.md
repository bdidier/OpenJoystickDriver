# Localization review 0.6.0

Task H11 of `openspec/changes/platform-neutral-redesign`. The 20 non-English locales were reviewed by the AI agent against `LOCALIZATION.md` (Meaning, Punctuation), Apple's localized macOS terms, CLDR plural categories and the English source with its translator comment. Native speakers have not reviewed them.

## Scope

- Keys reviewed per locale: 373: 348 keys under the task prefixes plus 25 controller-serving keys of 12.4 (server, serving, claim, release).
- The 12 `.stringsdict` entries of 22.3 were read in all 20 locales against the CLDR categories of `Resources/Localization/PluralCategories.json`. No plural form needed a change.
- Multi-specifier values were read for natural numbered-specifier order. No order change was needed.

## Kept English

`LocalizationCatalogAudit` keeps a key in English where the locale uses the same word as the source. The reviewed reasons:

- Keyboard key names (`term.key.*`) that macOS prints in English in the locale (Escape, Return, Shift, Alt, Control, Caps Lock).
- Product and protocol names (`term.protocolFamily.*`, `term.protocolVariant.usb`, `term.app.name`) and identifiers (HID, USB ID, Y/Triangle).
- `ui.menu.window.zoom`, `ui.menu.app.services`, `ui.settings.notifications.title`, `ui.menu.controller.title`, `ui.menu.file.title`, `ui.menu.help.title`: the system menu title in that locale is the same word as English (for example fr "Services", "Zoom", "Notifications"; nl "Help", "Controller").
- Dutch `Controllers` keys: Dutch uses the loanword "controller" and Apple's Dutch game-controller settings use it.
- Socket (`ui.access.socket`, `ui.access.transport.socket`) in it-IT, nl-NL and vi-VN: the networking term "Socket" is the established word, as it already is in de-DE and the Spanish locales.
- `ui.controllers.server.ojd` in es-ES, es-MX, pt-BR and id-ID: "OpenJoystickDriver (virtual)", where "virtual" is the native word.

## Per locale

### ar-SA

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 2.
- Scope keys equal to the English source: 4.

Fixes (key: before -> after):

- `ui.library.validate`: تحقق… -> تحقّق من الصحة…
- `ui.controllers.server.label`: يخدمه -> يُخدَم بواسطة

### de-DE

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 3.
- Scope keys equal to the English source: 26.

Fixes (key: before -> after):

- `ui.access.enable.message`: Programme, denen du Zugriff erteilst, können dann den Controller-Status lesen und ihn mit dem Bereich control ändern. -> Programme, denen du Zugriff erteilst, können dann den Controller-Status lesen und ihn mit dem Bereich „Steuern“ ändern.
- `ui.access.grant.controlWarning`: Mit dem Bereich control kann das Programm Ausgaben an deine Controller senden, etwa Vibration und Lichter. -> Mit dem Bereich „Steuern“ kann das Programm Ausgaben an deine Controller senden, etwa Vibration und Lichter.
- `ui.access.token.originControl`: Ein Token für Webseiten darf den Bereich control nicht haben. -> Ein Token für Webseiten darf den Bereich „Steuern“ nicht haben.

### es-ES

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 5.
- Scope keys equal to the English source: 19.

Fixes (key: before -> after):

- `ui.settings.advanced.discardAction`: No guardar cambios -> Descartar cambios
- `ui.settings.advanced.enableDeveloperTools`: Activar herramientas de desarrollo -> Activar herramientas para desarrolladores
- `ui.settings.advanced.developerToolsOff`: Activa las herramientas de desarrollo para ver la entrada del mando y los paquetes USB. -> Activa las herramientas para desarrolladores para ver la entrada del mando y los paquetes USB.
- `ui.activity.showInFinder.failed`: No se pudo abrir la carpeta de registros. -> No se ha podido abrir la carpeta de registros.
- `ui.controllers.server.ojd`: OpenJoystickDriver (mando virtual) -> OpenJoystickDriver (virtual)

### es-MX

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 18.
- Scope keys equal to the English source: 19.

Fixes (key: before -> after):

- `ui.settings.advanced.discardAction`: No guardar cambios -> Descartar cambios
- `ui.settings.advanced.enableDeveloperTools`: Activar herramientas de desarrollo -> Activar herramientas para desarrolladores
- `ui.settings.advanced.developerToolsOff`: Activa las herramientas de desarrollo para ver la entrada del control y los paquetes USB. -> Activa las herramientas para desarrolladores para ver la entrada del control y los paquetes USB.
- `ui.menu.app.settings`: Ajustes… -> Configuración…
- `ui.settings.general.openNotificationSettings`: Abrir ajustes de notificaciones -> Abrir configuración de notificaciones
- `a11y.settingsPane.general`: Ajustes generales -> Configuración general
- `a11y.settingsPane.notifications`: Ajustes de notificaciones -> Configuración de notificaciones
- `a11y.settingsPane.advanced`: Ajustes avanzados -> Configuración avanzada
- `ui.access.loading`: Leyendo los ajustes de acceso… -> Leyendo la configuración de acceso…
- `ui.access.error.serviceUnavailable`: OpenJoystickDriver no se está ejecutando, así que no se pueden leer ni cambiar los ajustes de acceso. -> OpenJoystickDriver no se está ejecutando, así que no se puede leer ni cambiar la configuración de acceso.
- `a11y.access.tryAgain`: Leer de nuevo los ajustes de acceso -> Leer de nuevo la configuración de acceso
- `ui.settings.advanced.errorDamaged`: El archivo de ajustes %@ está dañado. Corrígelo o muévelo a la Papelera con `ojd setting reset`. -> El archivo de configuración %@ está dañado. Corrígelo o muévelo a la Papelera con `ojd setting reset`.
- `ui.settings.advanced.errorUnsupported`: El archivo de ajustes %@ no es compatible. Reescribe el archivo para la apiVersion compatible o muévelo a la Papelera con `ojd setting reset`. -> El archivo de configuración %@ no es compatible. Reescribe el archivo para la apiVersion compatible o muévelo a la Papelera con `ojd setting reset`.
- `ui.settings.advanced.errorUnwritable`: No se puede escribir el archivo de ajustes %@. -> No se puede escribir el archivo de configuración %@.
- `ui.settings.advanced.errorCannotReset`: No se puede mover el archivo de ajustes %@ a la Papelera. -> No se puede mover el archivo de configuración %@ a la Papelera.
- `ui.settings.advanced.unreadableTitle`: No se pueden leer los ajustes -> No se puede leer la configuración
- `ui.settings.advanced.unreadableResetSettings`: Restablecer ajustes -> Restablecer configuración
- `ui.controllers.server.ojd`: OpenJoystickDriver (control virtual) -> OpenJoystickDriver (virtual)

### fr-CA

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 6.
- Scope keys equal to the English source: 21.

Fixes (key: before -> after):

- `ui.settings.advanced.discardAction`: Annuler les modifications -> Ignorer les modifications
- `ui.settings.advanced.enableDeveloperTools`: Activer les outils développeur -> Activer les outils de développement
- `ui.settings.general.openSystemSettings`: Ouvrir les réglages -> Ouvrir les réglages
- `ui.access.enable.message`: Les programmes auxquels vous accordez l’accès peuvent alors lire l’état des manettes et, avec la portée control, le modifier. -> Les programmes auxquels vous accordez l’accès peuvent alors lire l’état des manettes et, avec la portée « Contrôle », le modifier.
- `ui.access.grant.controlWarning`: La portée control permet au programme d’envoyer des sorties à vos manettes, comme les vibrations et les lumières. -> La portée « Contrôle » permet au programme d’envoyer des sorties à vos manettes, comme les vibrations et les lumières.
- `ui.access.token.originControl`: Un jeton pour des pages web ne peut pas avoir la portée control. -> Un jeton pour des pages web ne peut pas avoir la portée « Contrôle ».

### fr-FR

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 6.
- Scope keys equal to the English source: 21.

Fixes (key: before -> after):

- `ui.settings.advanced.discardAction`: Annuler les modifications -> Ignorer les modifications
- `ui.settings.advanced.enableDeveloperTools`: Activer les outils développeur -> Activer les outils de développement
- `ui.settings.general.openSystemSettings`: Ouvrir Réglages -> Ouvrir les réglages
- `ui.access.enable.message`: Les programmes auxquels vous accordez l’accès peuvent alors lire l’état des manettes et, avec la portée control, le modifier. -> Les programmes auxquels vous accordez l’accès peuvent alors lire l’état des manettes et, avec la portée « Contrôle », le modifier.
- `ui.access.grant.controlWarning`: La portée control permet au programme d’envoyer des sorties à vos manettes, comme les vibrations et les lumières. -> La portée « Contrôle » permet au programme d’envoyer des sorties à vos manettes, comme les vibrations et les lumières.
- `ui.access.token.originControl`: Un jeton pour des pages web ne peut pas avoir la portée control. -> Un jeton pour des pages web ne peut pas avoir la portée « Contrôle ».

### hi-IN

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 3.
- Scope keys equal to the English source: 9.

Fixes (key: before -> after):

- `ui.library.mod.install.message`: OpenJoystickDriver आपके इंस्टॉल किए मॉड में %1$@ %2$@ (निर्माता: %3$@) जोड़ता है। -> OpenJoystickDriver आपके इंस्टॉल किए मॉड में %3$@ द्वारा बनाया गया %1$@ %2$@ जोड़ता है।
- `cli.controller.claim.abstract`: किसी कंट्रोलर मॉडल को OpenJoystickDriver से चलवाएँ। -> किसी कंट्रोलर मॉडल को संभालने का काम OpenJoystickDriver को सौंपें।
- `ui.activity.column.details`: विवरण -> ब्योरा

### id-ID

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 32.
- Scope keys equal to the English source: 18.

Fixes (key: before -> after):

- `platform.macos.ui.settings.notifications.notificationBannersOffDetail`: Spanduk pemberitahuan dinonaktifkan di Pengaturan Sistem. -> Spanduk notifikasi dinonaktifkan di Pengaturan Sistem.
- `ui.settings.notifications.notificationDeliveryAllowed`: Pengiriman pemberitahuan diizinkan. -> Pengiriman notifikasi diizinkan.
- `ui.settings.notifications.notificationDeliveryReady`: Spanduk, Pusat Pemberitahuan, dan bunyi diaktifkan. -> Spanduk, Pusat Notifikasi, dan bunyi diaktifkan.
- `ui.settings.notifications.notificationPermissionRequired`: Izin diperlukan sebelum pemberitahuan dapat dikirim. -> Izin diperlukan sebelum notifikasi dapat dikirim.
- `platform.macos.ui.settings.notifications.notificationSoundOffDetail`: Bunyi pemberitahuan dinonaktifkan di Pengaturan Sistem. -> Bunyi notifikasi dinonaktifkan di Pengaturan Sistem.
- `ui.settings.notifications.notifications`: Pemberitahuan -> Notifikasi
- `platform.macos.ui.settings.notifications.notificationsDenied`: Pemberitahuan dinonaktifkan untuk OpenJoystickDriver di Pengaturan Sistem. -> Notifikasi dinonaktifkan untuk OpenJoystickDriver di Pengaturan Sistem.
- `ui.settings.general.openNotificationSettings`: Buka Pengaturan Pemberitahuan -> Buka Pengaturan Notifikasi
- `ui.settings.notifications.testNotification`: Kirim Pemberitahuan Tes -> Kirim Notifikasi Tes
- `notify.testTitle`: Pemberitahuan siap -> Notifikasi siap
- `ui.settings.notifications.noNotificationCenter`: Pemberitahuan tidak tersedia karena OpenJoystickDriver tidak berjalan dari bundel app-nya. Buka app OpenJoystickDriver, lalu coba lagi. -> Notifikasi tidak tersedia karena OpenJoystickDriver tidak berjalan dari bundel app-nya. Buka app OpenJoystickDriver, lalu coba lagi.
- `ui.settings.notifications.testReportLost`: Permintaan ojd berakhir atau waktu jawabnya habis sebelum laporan tentang pemberitahuan tes tiba. -> Permintaan ojd berakhir atau waktu jawabnya habis sebelum laporan tentang notifikasi tes tiba.
- `ui.settings.notifications.testReportNoAnswer`: Laporan pemberitahuan tes harus shown, denied, atau failed; hanya layanan yang menentukan noAnswer. -> Laporan notifikasi tes harus shown, denied, atau failed; hanya layanan yang menentukan noAnswer.
- `cli.setting.group.notificationSounds`: Putar bunyi dengan pemberitahuan. -> Putar bunyi dengan notifikasi.
- `cli.setting.group.notifyControllerConnected`: Beri pemberitahuan saat pengontrol terhubung atau perlu perhatian. -> Beri notifikasi saat pengontrol terhubung atau perlu perhatian.
- `cli.setting.group.notifyControllerDisconnected`: Beri pemberitahuan saat pengontrol terputus. -> Beri notifikasi saat pengontrol terputus.
- `cli.setting.group.notifyProfileActivated`: Beri pemberitahuan saat profil diaktifkan atau dialihkan. -> Beri notifikasi saat profil diaktifkan atau dialihkan.
- `cli.setting.group.notifyProfileDeactivated`: Beri pemberitahuan saat profil aktif dimatikan. -> Beri notifikasi saat profil aktif dimatikan.
- `error.E2036.message`: Tidak ada app OpenJoystickDriver yang menjawab pemberitahuan tes tepat waktu. Pastikan app berjalan, lalu coba lagi. -> Tidak ada app OpenJoystickDriver yang menjawab notifikasi tes tepat waktu. Pastikan app berjalan, lalu coba lagi.
- `error.E2037.message`: Pemberitahuan tidak diizinkan untuk OpenJoystickDriver. Izinkan di pengaturan pemberitahuan sistem, lalu coba lagi. -> Notifikasi tidak diizinkan untuk OpenJoystickDriver. Izinkan di pengaturan notifikasi sistem, lalu coba lagi.
- `cli.setting.testNotification.abstract`: Tampilkan pemberitahuan tes di app. -> Tampilkan notifikasi tes di app.
- `cli.setting.testNotification.discussion`: Meminta layanan mengumumkan pemberitahuan tes ke app OpenJoystickDriver yang terbuka dan menunggu app menampilkannya. Gagal dengan galat bernama jika pemberitahuan ditolak, pengiriman gagal, atau tidak ada app yang menjawab tepat waktu. Default --timeout di sini adalah %@ detik. -> Meminta layanan mengumumkan notifikasi tes ke app OpenJoystickDriver yang terbuka dan menunggu app menampilkannya. Gagal dengan galat bernama jika notifikasi ditolak, pengiriman gagal, atau tidak ada app yang menjawab tepat waktu. Default --timeout di sini adalah %@ detik.
- `cli.setting.testNotification.success`: App menampilkan pemberitahuan tes. -> App menampilkan notifikasi tes.
- `ui.library.installed`: Terpasang -> Terinstal
- `ui.settings.commandLine.toolUninstall`: Copot -> Copot Pemasangan
- `ui.settings.commandLine.toolBlocked`: %@ adalah file, bukan tautan. Hapus, lalu instal lagi. -> %@ adalah berkas, bukan tautan. Hapus, lalu instal lagi.
- `ui.activity.check.configFiles`: File konfigurasi -> Berkas konfigurasi
- `ui.settings.advanced.errorDamaged`: File pengaturan %@ rusak. Perbaiki, atau pindahkan ke Tong Sampah dengan `ojd setting reset`. -> Berkas pengaturan %@ rusak. Perbaiki, atau pindahkan ke Tong Sampah dengan `ojd setting reset`.
- `ui.settings.advanced.errorUnsupported`: File pengaturan %@ tidak didukung. Tulis ulang file untuk apiVersion yang didukung, atau pindahkan ke Tong Sampah dengan `ojd setting reset`. -> Berkas pengaturan %@ tidak didukung. Tulis ulang berkas untuk apiVersion yang didukung, atau pindahkan ke Tong Sampah dengan `ojd setting reset`.
- `ui.settings.advanced.errorUnwritable`: File pengaturan %@ tidak dapat ditulis. -> Berkas pengaturan %@ tidak dapat ditulis.
- `ui.settings.advanced.errorCannotReset`: File pengaturan %@ tidak dapat dipindahkan ke Tong Sampah. -> Berkas pengaturan %@ tidak dapat dipindahkan ke Tong Sampah.
- `ui.controllers.server.ojd`: OpenJoystickDriver (pengontrol virtual) -> OpenJoystickDriver (virtual)

### it-IT

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 7.
- Scope keys equal to the English source: 16.

Fixes (key: before -> after):

- `ui.library.detail.empty`: Scegli un record o una mod. -> Scegli un record o un mod.
- `ui.library.mod.remove.message`: OpenJoystickDriver elimina il mod insieme ai record, ai profili e alle persona che ha aggiunto. -> OpenJoystickDriver elimina il mod insieme ai record, ai profili e alle persone che ha aggiunto.
- `ui.library.claim.claimed`: Rileva questo controller -> Gestisce questo controller
- `ui.library.claim.unclaimed`: Non rileva questo controller -> Non gestisce questo controller
- `ui.access.socket`: Socket locale: %@ -> Socket: %@
- `ui.access.transport.socket`: Socket locale -> Socket
- `ui.settings.general.updateAhead`: Più recente dell'ultima release -> Più recente dell’ultima release

### ja-JP

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 4.
- Scope keys equal to the English source: 8.

Fixes (key: before -> after):

- `ui.library.record.patchedBy`: %@ が変更 -> %@ によるパッチ
- `ui.settings.advanced.enableDeveloperTools`: 開発者ツールを有効にする -> デベロッパツールを有効にする
- `ui.settings.advanced.developerToolsOff`: コントローラの入力とUSBパケットを表示するには、開発者ツールをオンにしてください。 -> コントローラの入力とUSBパケットを表示するには、デベロッパツールをオンにしてください。
- `ui.controllers.serving.withReason`: %1$@ (%2$@) -> %1$@（%2$@）

### ko-KR

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 4.
- Scope keys equal to the English source: 9.

Fixes (key: before -> after):

- `ui.settings.commandLine.toolBlocked`: %@은(는) 링크가 아니라 파일입니다. 삭제한 다음 다시 설치하십시오. -> %@은(는) 링크가 아니라 파일입니다. 삭제한 다음 다시 설치하세요.
- `ui.library.record.patchedBy`: %@에서 수정함 -> %@이(가) 패치함
- `ui.activity.column.details`: 세부 사항 -> 세부사항
- `ui.settings.commandLine.uninstallTitle`: 명령 행 도구를 제거하시겠습니까? -> 명령줄 도구를 제거하시겠습니까?

### nl-NL

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 4.
- Scope keys equal to the English source: 28.

Fixes (key: before -> after):

- `ui.access.socket`: Lokale socket: %@ -> Socket: %@
- `ui.access.transport.socket`: Lokale socket -> Socket
- `ui.settings.commandLine.uninstallConfirm`: Verwijder -> Verwijder installatie
- `ui.activity.search`: Zoek -> Zoeken

### pt-BR

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 1.
- Scope keys equal to the English source: 16.

Fixes (key: before -> after):

- `ui.controllers.server.ojd`: OpenJoystickDriver (controle virtual) -> OpenJoystickDriver (virtual)

### ru-RU

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 3.
- Scope keys equal to the English source: 9.

Fixes (key: before -> after):

- `ui.library.claim.claimed`: Берёт этот контроллер -> Обслуживает этот контроллер
- `ui.library.claim.unclaimed`: Не берёт этот контроллер -> Не обслуживает этот контроллер
- `ui.library.recordUnreadable`: Текст записи %@ невозможно прочитать, поэтому его нельзя показать. -> Текст записи «%@» невозможно прочитать, поэтому его нельзя показать.

### th-TH

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 50.
- Scope keys equal to the English source: 9.

Fixes (key: before -> after):

- `ui.settings.general.prereleaseUpdates`: รวมการอัพเดทรุ่นก่อนเผยแพร่ -> รวมการอัปเดตรุ่นก่อนเผยแพร่
- `ui.settings.general.updateAvailable`: มีรายการที่พร้อมให้อัพเดท -> มีรายการที่พร้อมให้อัปเดต
- `ui.settings.general.updates`: รายการอัพเดท -> รายการอัปเดต
- `ui.settings.general.viewUpdate`: ดูรายการอัพเดท -> ดูรายการอัปเดต
- `ui.virtualProfile.updating`: กำลังอัพเดทโปรไฟล์ HID เสมือน… -> กำลังอัปเดตโปรไฟล์ HID เสมือน…
- `ui.profiles.appID`: รหัสแอพ -> รหัสแอป
- `ui.profiles.creationValidation`: ตรวจสอบชื่อโปรไฟล์และเป้าหมายแอพพลิเคชัน -> ตรวจสอบชื่อโปรไฟล์และเป้าหมายแอปพลิเคชัน
- `ui.profiles.targetApplication`: หนึ่งแอพพลิเคชัน -> หนึ่งแอปพลิเคชัน
- `ui.profiles.targetGlobal`: ทุกแอพพลิเคชัน -> ทุกแอปพลิเคชัน
- `ui.mapping.allApps`: ทุกแอพ -> ทุกแอป
- `ui.mapping.specificApp`: แอพที่ระบุ -> แอปที่ระบุ
- `ui.setup.invalidDetail`: ไดรเวอร์ Xbox USB ที่ฝังอยู่ไม่ถูกต้อง ซ่อมแซมโดยติดตั้งแอพนี้ใหม่ -> ไดรเวอร์ Xbox USB ที่ฝังอยู่ไม่ถูกต้อง ซ่อมแซมโดยติดตั้งแอปนี้ใหม่
- `ui.setup.missingDetail`: แอพนี้ไม่มีไดรเวอร์ Xbox USB ติดตั้งแอพที่ลงนามแล้วใหม่ -> แอปนี้ไม่มีไดรเวอร์ Xbox USB ติดตั้งแอปที่ลงนามแล้วใหม่
- `ui.profiles.joyConPairSessionHint`: การจับคู่ใช้คอนโทรลเลอร์เหล่านี้โดยเฉพาะสำหรับเซสชั่นแอพปัจจุบัน -> การจับคู่ใช้คอนโทรลเลอร์เหล่านี้โดยเฉพาะสำหรับเซสชั่นแอปปัจจุบัน
- `notify.controllerNeedsAttentionBody`: อินพุตของ %@ หยุดอัพเดท ปล่อยตัวควบคุมของมัน หรือเลิกเชื่อมต่อ -> อินพุตของ %@ หยุดอัปเดต ปล่อยตัวควบคุมของมัน หรือเลิกเชื่อมต่อ
- `cli.shared.error.peerRejected`: บริการปฏิเสธ ojd นี้ เพราะไม่ได้ลงนามเหมือนแอพ ให้เรียกใช้ ojd ที่มาพร้อมกับ OpenJoystickDriver.app -> บริการปฏิเสธ ojd นี้ เพราะไม่ได้ลงนามเหมือนแอป ให้เรียกใช้ ojd ที่มาพร้อมกับ OpenJoystickDriver.app
- `cli.service.start.abstract`: เปิดแอพในพื้นหลังและรอจนกว่าบริการของแอพจะรับคำขอ -> เปิดแอปในพื้นหลังและรอจนกว่าบริการของแอปจะรับคำขอ
- `cli.service.start.noBundle`: ojd นี้ไม่ได้อยู่ใน OpenJoystickDriver.app จึงไม่สามารถเริ่มบริการได้ เปิดแอพที่ติดตั้งไว้ หรือเรียกใช้ ojd ที่อยู่ในแอพนั้น -> ojd นี้ไม่ได้อยู่ใน OpenJoystickDriver.app จึงไม่สามารถเริ่มบริการได้ เปิดแอปที่ติดตั้งไว้ หรือเรียกใช้ ojd ที่อยู่ในแอปนั้น
- `cli.service.stop.signalFailed`: ไม่สามารถหยุดบริการได้: %@ ออกจาก OpenJoystickDriver จากเมนูของแอพ -> ไม่สามารถหยุดบริการได้: %@ ออกจาก OpenJoystickDriver จากเมนูของแอป
- `cli.access.group.clientUnsigned`: %@ ไม่มีโปรแกรมที่ลงนาม ให้สิทธิ์แก่บันเดิลแอพหรือไฟล์ที่เรียกใช้งานได้ของโปรแกรม -> %@ ไม่มีโปรแกรมที่ลงนาม ให้สิทธิ์แก่บันเดิลแอปหรือไฟล์ที่เรียกใช้งานได้ของโปรแกรม
- `cli.access.grant.controlWarning`: ขอบเขต control ให้โปรแกรมกดปุ่มบนเกมแพดเสมือนได้ ซึ่งเกมและแอพจะถือเป็นอินพุตของคุณ -> ขอบเขต control ให้โปรแกรมกดปุ่มบนเกมแพดเสมือนได้ ซึ่งเกมและแอปจะถือเป็นอินพุตของคุณ
- `cli.access.grant.discussion`: CLIENT คือพาธของโปรแกรม หรือ ID จาก “ojd access list” สิทธิ์ที่ให้ระบุลายเซ็นของโปรแกรม จึงยังใช้ได้เมื่อโปรแกรมถูกอัพเดทหรือย้าย โปรแกรมที่ลงนามแบบ ad-hoc และที่ไม่ได้ลงนามจะให้สิทธิ์ไม่ได้ เมื่อใช้ --token แทน CLIENT จะสร้างโทเค็นที่ไคลเอนต์ใช้ลงนามความท้าทายของบริการใน hello ของตน ทั้งบนซ็อกเก็ต บน WebSocket จากหน้าเว็บที่อยู่ในค่า --origin ค่าใดค่าหนึ่ง หรือสำหรับโทเค็นที่ไม่มี --origin บน WebSocket จากโปรแกรมที่ไม่ส่งส่วนหัว Origin เช่นแอพที่อยู่ในแซนด์บ็อกซ์ หน้าเว็บใช้ขอบเขต control ไม่ได้ โทเค็นจะแสดงเพียงครั้งเดียว ขอการยืนยันก่อน -> CLIENT คือพาธของโปรแกรม หรือ ID จาก “ojd access list” สิทธิ์ที่ให้ระบุลายเซ็นของโปรแกรม จึงยังใช้ได้เมื่อโปรแกรมถูกอัปเดตหรือย้าย โปรแกรมที่ลงนามแบบ ad-hoc และที่ไม่ได้ลงนามจะให้สิทธิ์ไม่ได้ เมื่อใช้ --token แทน CLIENT จะสร้างโทเค็นที่ไคลเอนต์ใช้ลงนามความท้าทายของบริการใน hello ของตน ทั้งบนซ็อกเก็ต บน WebSocket จากหน้าเว็บที่อยู่ในค่า --origin ค่าใดค่าหนึ่ง หรือสำหรับโทเค็นที่ไม่มี --origin บน WebSocket จากโปรแกรมที่ไม่ส่งส่วนหัว Origin เช่นแอปที่อยู่ในแซนด์บ็อกซ์ หน้าเว็บใช้ขอบเขต control ไม่ได้ โทเค็นจะแสดงเพียงครั้งเดียว ขอการยืนยันก่อน
- `cli.diagnose.group.transportExtensionBundleMissing`: ไม่ได้ฝังไว้ในแอพ ติดตั้ง OpenJoystickDriver ใหม่ -> ไม่ได้ฝังไว้ในแอป ติดตั้ง OpenJoystickDriver ใหม่
- `cli.diagnose.group.transportExtensionBundlePresent`: ฝังไว้ในแอพ -> ฝังไว้ในแอป
- `cli.transportExtension.group.bundleMissing`: แอพไม่มี %@.dext เรียกใช้ “./Scripts/ojd build install dev” แล้วลองอีกครั้งจาก /Applications -> แอปไม่มี %@.dext เรียกใช้ “./Scripts/ojd build install dev” แล้วลองอีกครั้งจาก /Applications
- `platform.macos.cli.transportExtension.group.codesignFailedToRun`: ไม่สามารถเรียกใช้ codesign เพื่อตรวจสอบแอพได้: %@ ตรวจสอบว่ามี /usr/bin/codesign อยู่ -> ไม่สามารถเรียกใช้ codesign เพื่อตรวจสอบแอปได้: %@ ตรวจสอบว่ามี /usr/bin/codesign อยู่
- `cli.transportExtension.group.signatureInvalid`: ลายเซ็นของแอพไม่ถูกต้อง (%@) สร้างใหม่ด้วย “./Scripts/ojd build install-fast dev” แล้วลองอีกครั้ง -> ลายเซ็นของแอปไม่ถูกต้อง (%@) สร้างใหม่ด้วย “./Scripts/ojd build install-fast dev” แล้วลองอีกครั้ง
- `platform.macos.cli.transportExtension.status.abstract`: แสดงว่าส่วนขยายอยู่ในแอพและลงทะเบียนกับ macOS หรือไม่ -> แสดงว่าส่วนขยายอยู่ในแอปและลงทะเบียนกับ macOS หรือไม่
- `cli.setting.group.abstract`: แสดงรายการ อ่าน หรือเปลี่ยนการตั้งค่าแอพ OpenJoystickDriver -> แสดงรายการ อ่าน หรือเปลี่ยนการตั้งค่าแอป OpenJoystickDriver
- `cli.setting.group.includePrereleaseUpdates`: รวมเวอร์ชั่นรุ่นก่อนเผยแพร่เมื่อตรวจสอบรายการอัพเดท -> รวมเวอร์ชั่นรุ่นก่อนเผยแพร่เมื่อตรวจสอบรายการอัปเดต
- `cli.update.check.discussion`: ทำงานเมื่อคุณสั่งเท่านั้น ojd จะไม่ตรวจสอบเอง และไม่ดาวน์โหลดหรือติดตั้งสิ่งใด ออกด้วยรหัส 0 ไม่ว่าจะมีรายการอัพเดทหรือไม่ และรหัส 1 เมื่อการตรวจสอบล้มเหลว -> ทำงานเมื่อคุณสั่งเท่านั้น ojd จะไม่ตรวจสอบเอง และไม่ดาวน์โหลดหรือติดตั้งสิ่งใด ออกด้วยรหัส 0 ไม่ว่าจะมีรายการอัปเดตหรือไม่ และรหัส 1 เมื่อการตรวจสอบล้มเหลว
- `cli.update.check.failed`: ไม่สามารถตรวจสอบรายการอัพเดทได้: %@ ตรวจสอบการเชื่อมต่อเครือข่ายแล้วลองอีกครั้ง -> ไม่สามารถตรวจสอบรายการอัปเดตได้: %@ ตรวจสอบการเชื่อมต่อเครือข่ายแล้วลองอีกครั้ง
- `cli.update.check.failedReason`: ไม่สามารถตรวจสอบรายการอัพเดทได้: %@ -> ไม่สามารถตรวจสอบรายการอัปเดตได้: %@
- `ui.settings.commandLine.toolLinkedElsewhere`: %1$@ ชี้ไปที่ %2$@ การติดตั้งจะเชื่อมโยงกับแอพนี้แทน -> %1$@ ชี้ไปที่ %2$@ การติดตั้งจะเชื่อมโยงกับแอปนี้แทน
- `platform.macos.ui.settings.commandLine.toolNotInstalled`: เชื่อมโยง %@ กับแอพนี้เพื่อให้คุณเรียกใช้ ojd ในเทอร์มินัลได้ macOS จะขอรหัสผ่านผู้ดูแลระบบ -> เชื่อมโยง %@ กับแอปนี้เพื่อให้คุณเรียกใช้ ojd ในเทอร์มินัลได้ macOS จะขอรหัสผ่านผู้ดูแลระบบ
- `cli.profile.activate.discussion`: โปรไฟล์จะแทนที่โปรไฟล์ที่ใช้งานอยู่ของรุ่นคอนโทรลเลอร์และขอบเขตแอพเดียวกัน โปรไฟล์ที่ตั้งเกมแพดเสมือนเป็น mapped และไม่ส่งสิ่งใดไปยังเกมแพด คีย์บอร์ด ตัวชี้ หรือคอนโทรลเลอร์ และไม่ตั้งสีของไฟ จะไม่มีเอาต์พุต การเปิดใช้งานโปรไฟล์เช่นนั้นต้องใช้ --allow-empty -> โปรไฟล์จะแทนที่โปรไฟล์ที่ใช้งานอยู่ของรุ่นคอนโทรลเลอร์และขอบเขตแอปเดียวกัน โปรไฟล์ที่ตั้งเกมแพดเสมือนเป็น mapped และไม่ส่งสิ่งใดไปยังเกมแพด คีย์บอร์ด ตัวชี้ หรือคอนโทรลเลอร์ และไม่ตั้งสีของไฟ จะไม่มีเอาต์พุต การเปิดใช้งานโปรไฟล์เช่นนั้นต้องใช้ --allow-empty
- `cli.profile.create.app`: ใช้โปรไฟล์เฉพาะขณะที่แอพนี้ ตามรหัสแอพ อยู่ด้านหน้า -> ใช้โปรไฟล์เฉพาะขณะที่แอปนี้ ตามรหัสแอป อยู่ด้านหน้า
- `cli.profile.create.discussion`: โปรไฟล์ใช้ได้ในทุกแอพ เว้นแต่ --app ระบุแอพหนึ่ง โดยค่าเริ่มต้น เกมแพดเสมือนจะส่งผ่านตัวควบคุมทุกตัวที่ไม่มีการกำหนดใช้ โปรไฟล์เริ่มต้นเป็นไม่ใช้งาน เปิดใช้งานด้วย “ojd profile activate” -> โปรไฟล์ใช้ได้ในทุกแอป เว้นแต่ --app ระบุแอปหนึ่ง โดยค่าเริ่มต้น เกมแพดเสมือนจะส่งผ่านตัวควบคุมทุกตัวที่ไม่มีการกำหนดใช้ โปรไฟล์เริ่มต้นเป็นไม่ใช้งาน เปิดใช้งานด้วย “ojd profile activate”
- `ui.settings.commandLine.toolLinkTargetUnreadable`: %@ เป็นลิงก์ที่ไม่สามารถอ่านเป้าหมายได้ การติดตั้งจะเชื่อมโยงกับแอพนี้แทน -> %@ เป็นลิงก์ที่ไม่สามารถอ่านเป้าหมายได้ การติดตั้งจะเชื่อมโยงกับแอปนี้แทน
- `ui.shortcuts.action.appVersion.description`: ส่งคืนเวอร์ชั่นของแอพที่ติดตั้ง -> ส่งคืนเวอร์ชั่นของแอปที่ติดตั้ง
- `error.E2007.message`: บริการปฏิเสธ ojd นี้ เพราะไม่ได้ลงนามเหมือนแอพ เรียกใช้ ojd ที่อยู่ใน OpenJoystickDriver.app -> บริการปฏิเสธ ojd นี้ เพราะไม่ได้ลงนามเหมือนแอป เรียกใช้ ojd ที่อยู่ใน OpenJoystickDriver.app
- `error.E2014.message`: OpenJoystickDriver ติดตั้งไม่สมบูรณ์ หรือลายเซ็นไม่ถูกต้อง ติดตั้งแอพใหม่แล้วเรียกใช้ “ojd diagnose” -> OpenJoystickDriver ติดตั้งไม่สมบูรณ์ หรือลายเซ็นไม่ถูกต้อง ติดตั้งแอปใหม่แล้วเรียกใช้ “ojd diagnose”
- `error.E2019.message`: การตรวจสอบรายการอัพเดทไม่เสร็จ ตรวจสอบการเชื่อมต่อเครือข่ายแล้วลองอีกครั้ง -> การตรวจสอบรายการอัปเดตไม่เสร็จ ตรวจสอบการเชื่อมต่อเครือข่ายแล้วลองอีกครั้ง
- `error.E2020.message`: แอพ OpenJoystickDriver ที่ติดตั้งเก่ากว่า ojd นี้ เรียกใช้ “./Scripts/ojd build install-fast dev” หรือตั้ง OJD_RUN_REPOSITORY_CLI=1 เพื่อเรียกใช้บิลด์นี้ -> แอป OpenJoystickDriver ที่ติดตั้งเก่ากว่า ojd นี้ เรียกใช้ “./Scripts/ojd build install-fast dev” หรือตั้ง OJD_RUN_REPOSITORY_CLI=1 เพื่อเรียกใช้บิลด์นี้
- `error.E2021.message`: ojd ที่บิลด์จากที่เก็บส่งคำสั่งให้แอพที่ติดตั้งไม่ได้ ติดตั้ง OpenJoystickDriver.app ใหม่แล้วเรียกใช้คำสั่งอีกครั้ง -> ojd ที่บิลด์จากที่เก็บส่งคำสั่งให้แอปที่ติดตั้งไม่ได้ ติดตั้ง OpenJoystickDriver.app ใหม่แล้วเรียกใช้คำสั่งอีกครั้ง
- `error.E3010.message`: มีโปรไฟล์ที่ใช้ตัวระบุนั้นอยู่แล้ว ใช้ตัวระบุใหม่ หรืออัพเดทโปรไฟล์ที่มีอยู่ -> มีโปรไฟล์ที่ใช้ตัวระบุนั้นอยู่แล้ว ใช้ตัวระบุใหม่ หรืออัปเดตโปรไฟล์ที่มีอยู่
- `ui.menu.file.saveActivityLog`: บันทึกบันทึกกิจกรรมลงไฟล์… -> บันทึกกิจกรรมเป็นไฟล์…
- `ui.settings.advanced.developerToolsOff`: เปิดเครื่องมือสำหรับนักพัฒนาเพื่อดูอินพุตของคอนโทรลเลอร์และแพ็กเก็ต USB -> เปิดเครื่องมือนักพัฒนาเพื่อดูอินพุตของคอนโทรลเลอร์และแพ็กเก็ต USB
- `ui.settings.general.version`: รุ่น -> เวอร์ชัน
- `ui.access.revokeScope.message`: จะนำออกเฉพาะขอบเขต %@ ขอบเขตอื่นยังคงอยู่ และการเชื่อมต่อที่เปิดอยู่ซึ่งใช้ขอบเขตนี้จะถูกปิด -> จะเอาออกเฉพาะขอบเขต %@ ขอบเขตอื่นยังคงอยู่ และการเชื่อมต่อที่เปิดอยู่ซึ่งใช้ขอบเขตนี้จะถูกปิด

### tr-TR

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 4.
- Scope keys equal to the English source: 9.

Fixes (key: before -> after):

- `ui.banner.service.title`: OpenJoystickDriver servisine ulaşamıyor -> OpenJoystickDriver hizmetine ulaşamıyor
- `ui.settings.notifications.testReportNoAnswer`: Test bildirimi raporu shown, denied veya failed olmalıdır; noAnswer yalnızca servis tarafından belirlenir. -> Test bildirimi raporu shown, denied veya failed olmalıdır; noAnswer yalnızca hizmet tarafından belirlenir.
- `a11y.capture.touchSwipeDistance`: En Kısa Kaydırma Mesafesi -> Asgari kaydırma mesafesi
- `ui.activity.filter`: Süz -> Filtre

### vi-VN

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 7.
- Scope keys equal to the English source: 13.

Fixes (key: before -> after):

- `ui.access.socket`: Socket cục bộ: %@ -> Socket: %@
- `ui.library.mod.install.message`: OpenJoystickDriver thêm %1$@ %2$@ của %3$@ vào các mod đã cài của bạn. -> OpenJoystickDriver thêm %1$@ %2$@ do %3$@ tạo vào các mod đã cài của bạn.
- `cli.controller.claim.abstract`: Để OpenJoystickDriver phục vụ một mẫu bộ điều khiển. -> Yêu cầu OpenJoystickDriver phục vụ một mẫu bộ điều khiển.
- `ui.access.web.off`: Đang tắt -> Tắt
- `ui.access.transport.socket`: Socket cục bộ -> Socket
- `ui.activity.fix.showLibrary`: Hiển thị Thư viện -> Hiện thư viện
- `ui.activity.check.configFiles`: Tệp cấu hình -> Tệp thiết lập

### zh-CN

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 1.
- Scope keys equal to the English source: 8.

Fixes (key: before -> after):

- `ui.access.web.enable.savedPort`: Web 端点保留其已保存的端口。 -> Web 端点保留其已存储的端口。

### zh-HK

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 12.
- Scope keys equal to the English source: 8.

Fixes (key: before -> after):

- `ui.settings.general.openNotificationSettings`: 打開通知設定 -> 開啟通知設定
- `ui.settings.general.startAtLogin`: 登入時打開 -> 登入時開啟
- `ui.settings.general.startAtLoginDescription`: 登入時在選單列打開 OpenJoystickDriver。 -> 登入時在選單列開啟 OpenJoystickDriver。
- `ui.access.revoke.message`: 該程式將失去所有範圍，其已開啟的連接將關閉。 -> 該程式將失去所有範圍，其已開啟的連線將關閉。
- `ui.access.revokeScope.message`: 僅移除 %@ 範圍。其他範圍維持不變，使用此範圍的已開啟連接將關閉。 -> 僅移除 %@ 範圍。其他範圍維持不變，使用此範圍的已開啟連線將關閉。
- `ui.access.revokeToken.message`: 使用該權杖的頁面和程式將失去取用權限，其已開啟的連接將關閉。 -> 使用該權杖的頁面和程式將失去取用權限，其已開啟的連線將關閉。
- `ui.activity.showInFinder.failed`: 無法打開記錄檔資料夾。 -> 無法開啟記錄檔資料夾。
- `ui.activity.check.usbAccess`: USB 存取 -> USB 取用
- `ui.settings.notifications.controllerConnectedShort`: 已連接 -> 已連線
- `ui.settings.notifications.controllerNotifications`: 控制器已連接 -> 控制器已連線
- `ui.banner.service.title`: OpenJoystickDriver 無法連接其服務 -> OpenJoystickDriver 無法連線至其服務
- `ui.access.connections`: 目前已連接 -> 目前已連線

### zh-TW

- Keys reviewed: 373; plural entries reviewed: 12.
- Fixes: 8.
- Scope keys equal to the English source: 8.

Fixes (key: before -> after):

- `ui.settings.notifications.controllerConnectedShort`: 已連接 -> 已連線
- `ui.settings.notifications.controllerNotifications`: 控制器已連接 -> 控制器已連線
- `ui.banner.service.title`: OpenJoystickDriver 無法連接其服務 -> OpenJoystickDriver 無法連線至其服務
- `ui.extra.openWindow`: 開啟視窗 -> 打開視窗
- `ui.activity.showInFinder.failed`: 無法開啟記錄檔資料夾。 -> 無法打開記錄檔資料夾。
- `ui.activity.check.usbAccess`: USB 存取 -> USB 取用
- `ui.settings.notifications.noNotificationCenter`: 通知無法使用，因為 OpenJoystickDriver 不是從其 App 套件執行的。請開啟 OpenJoystickDriver App，然後重試。 -> 通知無法使用，因為 OpenJoystickDriver 不是從其 App 套件執行的。請打開 OpenJoystickDriver App，然後重試。
- `ui.settings.notifications.controllerDisconnectedNotifications`: 控制器已斷線 -> 控制器已中斷連線
