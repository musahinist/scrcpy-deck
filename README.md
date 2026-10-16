# ScrcpyDeck

Menü çubuğundan scrcpy ve adb komutlarını çalıştıran kısayol uygulaması.
Telefon: Galaxy A17 5G (SM-A176B).

## Nerede ne var

| Ne | Nerede |
|---|---|
| Komut listesi (düzenlenebilir) | `~/Documents/scrcpy-deck/commands.json` |
| Kaynak kod | `~/Documents/scrcpy-deck/main.swift` |
| Kurulu uygulama | `~/Applications/ScrcpyDeck.app` |
| Girişte başlatan tanım | `~/Library/LaunchAgents/local.scrcpydeck.plist` |
| Ayrıntılı komut notları | `~/Documents/scrcpy-komutlari.md` |

## Kullanım

Sağ üstteki telefon ikonu. İkon üç durumu gösterir:

- `iphone` — cihaz bağlı, çalışan yok
- `iphone.slash` — cihaz bağlı değil
- `play.rectangle` + sayı — o kadar komut çalışıyor

Menüde dört grup var: DeX / sanal ekran, Kablosuz bağlantı, Ekran yansıtma,
adb araçları. Uzun süren bir komuta tıklayınca başlar, yanına `■` gelir;
tekrar tıklayınca durur. Menünün üstündeki "Çalışanlar" bölümünden veya
"Tümünü durdur" ile de kapatabilirsin.

## Komut eklemek

`commands.json` dosyasını düzenle (menüden "Komutları düzenle…"), sonra
menüden "Yeniden yükle" de. Uygulamayı yeniden derlemene gerek yok.

Her komutun `kind` alanı davranışını belirler:

- `run` — uzun sürer, menüden durdurulur (scrcpy pencereleri)
- `once` — kısa sürer, çıktısı bir pencerede gösterilir (adb komutları)
- `terminal` — Terminal'de açılır (uzun çıktılar için)

Yer tutucular:

- `{dev}` — `-s <seri no>`, menüde seçili cihaz. **Önemli:** telefon USB ve
  kablosuz olarak aynı anda bağlıyken scrcpy ve adb "Multiple ADB devices"
  hatası verir. Cihaz hedefleyen her komutta `{dev}` olmalı. Cihaz seçmeyen
  komutlarda (`adb devices`, `adb disconnect`, `adb kill-server`,
  `scrcpy --tcpip=`) olmamalı.
- `{ip}` — telefonun IP'si. Uygulama önce `swlan0` (hotspot), sonra `wlan0`,
  en son Mac'in ağ geçidini dener. Elle yazmana gerek yok.
- `{file}` — dosya seçme penceresi açar
- `{save}` — kaydetme penceresi açar
- `{fit}` — telefonun genişliği korunup boyu Mac'in ana ekranının oranına
  uydurulmuş çözünürlük. Dik TV'de (1080x1920) `1080x1920` olur. Ekran
  yataysa telefonun kendi çözünürlüğünü verir, yani hiçbir şey değişmez.

`cleanup` alanı (yalnızca `run`): komut nasıl biterse bitsin (menüden
durdurma, scrcpy penceresini kapatma, uygulamadan çıkış) ardından çalışır.

`confirm` alanı eklersen çalıştırmadan önce onay sorar (telefonu yeniden
başlatmada kullanılıyor).

## Kurulum / kaldırma

    bash ~/Documents/scrcpy-deck/install.sh      # root gerekmez
    bash ~/Documents/scrcpy-deck/uninstall.sh

Kaynak kodu ya da `commands.json`'ı değiştirdiysen tek komut:

    bash ~/Documents/scrcpy-deck/deploy.sh          # bu Mac + Mac mini
    bash ~/Documents/scrcpy-deck/deploy.sh --here   # yalnızca bu Mac

Derler, imzalar, kurar; sonra Mac mini'ye (`ssh mshns-mac-mini.local`)
kopyalayıp orada da aynısını yapar. `commands.json` iki Mac'te birebir
aynıdır. Yansıtma açık olan Mac'te uygulama yeniden başlatılmaz; bitince
menüden "Yeniden yükle" (yalnızca komutlar değiştiyse) ya da `install.sh`.

Proje git'te. Asıl kopya MacBook'taki; Mac mini'ye `deploy.sh` ile gider,
orada elle değişiklik yapma (bir sonraki deploy üzerine yazar).

## Telefon kilitliyken çalışmak — DeX kullan

Bu telefonda **kilit ekranı hiçbir şekilde yansıtılmıyor.** Samsung hem
`screencap`'i hem scrcpy'nin ekran yakalamasını engelliyor; Mac'te siyah
pencere görürsün. Yani deseni Mac'ten çizmek de mümkün değil.

Çözüm kilit ekranını geçmeye çalışmak değil, ona hiç uğramamak:
**`--new-display` ile açılan sanal ekran kilide tabi değildir.**

`dumpsys display` çıktısında sanal ekran şu bayrakla oluşuyor:

    type VIRTUAL ... FLAG_ALWAYS_UNLOCKED

Telefon `deviceLocked=1` iken bile DeX masaüstü
(`com.honeyspace.dexservice.SecondaryLauncher`) bu ekranda açılıyor — ölçüldü.

Yani "telefon ekranı kapalı, ben Mac'ten çalışayım" senaryosunun doğru yolu
`-S -w` yansıtma değil, **DeX komutları**. Telefon kilitli ve ekranı kapalı
kalır, sen Mac'te tam masaüstü kullanırsın.

Yansıtma modları (`-S -w` dahil) yalnızca telefonun kilidi **zaten açıkken**
işe yarar.

## Kilit ekranı ve "ekran kapalı" modu

`-S` (telefon ekranı kapalı) seçeneği ekranı **hemen** kapatır. Telefon o anda
kilitliyse Samsung kilit ekranını çizmez ve Mac'te siyah bir pencere kalır —
kilidi açamazsın. Çözüm sıralamayı ters çevirmek:

1. **"Yansıt — kilit açılabilir"** komutunu çalıştır (`scrcpy -w`, ekran açık).
2. Kilidi Mac'ten aç (fare ve klavyeyle).
3. **Option+O** tuşlarına bas. Telefonun ekranı kapanır, yansıtma sürer.
   Geri açmak için Option+Shift+O.

Kısayol tuşu scrcpy'de MOD olarak geçer; macOS'te Option ya da sol Command.

**"Yansıt — telefonu uyandırıp aç"** komutu ilk iki adımın bir kısmını otomatik
yapar: telefonu uyandırır, kilit ekranını yukarı kaydırıp PIN ekranını getirir,
sonra yansıtmayı başlatır. PIN'i yine sen girersin.

`-S -w` komutunu ("ekran kapalı") telefon **zaten açıkken** kullan.

## Dik TV'ye yansıtma (Mac mini)

**"Yansıt — TV'ye sığdır, ekran kapalı"** komutu, "ekran kapalı" modunun TV
için olanıdır. Telefonun ekran çözünürlüğünü geçici olarak TV'nin oranına
çevirir (`wm size 1080x1920`, telefonun normali 1080x2340), böylece yansıtma
TV'yi kenar boşluğu olmadan doldurur. scrcpy kapanınca `wm size reset` ile
eski hâline döner.

Kablo çekilirse veya Mac uykuya geçerse Mac'in sıfırlaması telefona
ulaşamaz. Bunun için komut başlarken telefona bir bekçi bırakılır
(`phone_cleanup`, `/data/local/tmp/scrcpydeck-watch.sh`): scrcpy'nin telefondaki
sunucusu bitince — bağlantı nasıl koparsa kopsun — `wm size reset`'i telefon
kendisi çalıştırır. Yine de kalırsa kablo takılıyken **adb araçları →
"Telefon çözünürlüğünü sıfırla"** ile düzelir.

Mac'te ekranın dik olduğunu macOS'a da söylemek gerekir: Sistem Ayarları →
Ekranlar → Döndürme 90°. Yoksa `{fit}` ekranı yatay görür ve hiçbir şey
değiştirmez.

## Türkçe karakterler (ç ğ ı İ ö ş ü)

Klavye kullanan bütün scrcpy komutlarında `--keyboard=uhid` var. Varsayılan
`sdk` modu ASCII dışı karakterleri telefona aktaramıyor, bu yüzden harfler
kayboluyordu. `uhid` modunda scrcpy telefona gerçek bir USB klavye gibi
görünür ve harfe çevirmeyi Android yapar.

Bir kez yapılır: yansıtma açıkken **Option+K** ile telefonun fiziksel klavye
ayarı açılır, oradan düzeni **Türkçe (Q)** yap. Mac'in düzeni de Türkçe Q
(Turkish-QWERTY-PC) olduğu için tuşlar birebir eşleşir.

## Kablo takılınca otomatik TV modu

`commands.json`'da `"auto": true` olan komut (TV modu), menüde **"Kablo
takılınca otomatik başlat"** işaretliyse telefon USB ile takıldığı anda
kendiliğinden başlar. Uygulama 5 saniyede bir bakar.

- Bu ayar makineye özeldir: Mac mini'de açık, MacBook'ta kapalı.
- Yalnızca takılma anında çalışır. Elle durdurursan kablo takılı kaldıkça
  yeniden açılmaz; çıkarıp takınca açılır.
- Kablo gevşeyip bağlantı geri gelirse yeniden bağlanır.
- Mac mini açılırken telefon takılıysa da başlar.

## Cihaz seçimi

"Kablosuz bağlan" dedikten sonra telefon **iki kez** bağlı görünür: USB ve
kablosuz. Bu durumda menüde bir "Cihaz" bölümü çıkar ve hangisinin
kullanılacağını seçersin. Seçmezsen uygulama USB olanı kullanır (daha
kararlı). Seçim hatırlanır.

Kabloyu çıkarmak istersen kablosuz bağlantı çalışmaya devam eder; tek bağlantı
kaldığı için "Cihaz" bölümü de kaybolur.

## Bilinmesi gerekenler

- launchd'den başlayan uygulamanın PATH'i dardır. Uygulama `path_extra`
  listesindeki dizinleri kendi ekler; yeni bir araç kurarsan dizinini oraya yaz.
- Uzun süren komutlar, TERM aldığında çocuğunu da öldüren bir sarmalayıcıyla
  çalışır. Bileşik komut (`&&`, `|`) yazsan bile "durdur" gerçekten durdurur.
- Bir `run` komutu ilk 10 saniyede hata verip çıkarsa çıktısı bir pencerede
  gösterilir. Sessizce başarısız olmaz.
- DeX çözünürlüğü ekrana göre hesaplanmıştır (Mac 1800x1169 @2x, çentik payı
  düşülmüş = 3600x2262). Ekran değişirse `scrcpy-komutlari.md` 8. bölüme bak.
