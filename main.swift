import AppKit
import Carbon.HIToolbox

// ScrcpyDeck — scrcpy / adb komutlarını menü çubuğundan çalıştıran kısayol uygulaması.
// Komutlar commands.json dosyasından okunur; uygulamayı yeniden derlemeden düzenlenir.

// Önce ~/.config: Belgeler klasörü TCC izni ister ve launchd'den başlayan
// uygulamaya bu izin sorusu hiç gösterilmeyebilir (Mac mini'de böyle oldu).
let configPath: String = {
    let home = NSHomeDirectory()
    let preferred = home + "/.config/scrcpy-deck/commands.json"
    if FileManager.default.fileExists(atPath: preferred) { return preferred }
    return home + "/Documents/scrcpy-deck/commands.json"
}()

// MARK: - Model

struct Item {
    let title: String
    let kind: String      // run | once | terminal
    let cmd: String
    let confirm: String?
    let cleanup: String?  // komut nasıl biterse bitsin ardından çalışır
    let phoneCleanup: String?  // aynısı ama telefonda, Mac'siz (kablo çekilse de)
    let auto: Bool        // kablo takılınca kendiliğinden başlayacak komut
    var id: String { "\(title)|\(cmd)" }
    var needsIP: Bool   { cmd.contains("{ip}") }
    var needsFit: Bool  { cmd.contains("{fit}") || cmd.contains("{fitdpi}") }
    var needsFile: Bool { cmd.contains("{file}") }
    var needsSave: Bool { cmd.contains("{save}") }
}

struct Group { let name: String; let items: [Item] }

/// Genel kısayol: odak scrcpy penceresinde olmasa da çalışır.
struct HotKey { let key: String; let title: String; let cmd: String }

struct Device {
    let serial: String
    let model: String
    var isWireless: Bool { serial.contains(":") }
    var label: String { "\(model) — \(isWireless ? "kablosuz" : "USB")" }
}

struct Config {
    var groups: [Group] = []
    var hotkeys: [HotKey] = []
    var pathExtra: [String] = ["/opt/homebrew/bin", "/usr/local/bin",
                               NSHomeDirectory() + "/Library/Android/sdk/platform-tools"]
    var error: String?
}

func loadConfig() -> Config {
    var c = Config()
    guard let data = FileManager.default.contents(atPath: configPath) else {
        c.error = "commands.json bulunamadı:\n\(configPath)"; return c
    }
    guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        c.error = "commands.json okunamadı — JSON geçersiz."; return c
    }
    if let p = o["path_extra"] as? [String], !p.isEmpty {
        c.pathExtra = p.map { $0.hasPrefix("~") ? NSHomeDirectory() + String($0.dropFirst()) : $0 }
    }
    for g in (o["groups"] as? [[String: Any]] ?? []) {
        let name = g["name"] as? String ?? "?"
        let items: [Item] = (g["items"] as? [[String: Any]] ?? []).compactMap {
            guard let t = $0["title"] as? String, let cmd = $0["cmd"] as? String else { return nil }
            return Item(title: t, kind: $0["kind"] as? String ?? "once",
                        cmd: cmd, confirm: $0["confirm"] as? String,
                        cleanup: $0["cleanup"] as? String,
                        phoneCleanup: $0["phone_cleanup"] as? String,
                        auto: $0["auto"] as? Bool ?? false)
        }
        c.groups.append(Group(name: name, items: items))
    }
    c.hotkeys = (o["hotkeys"] as? [[String: Any]] ?? []).compactMap {
        guard let k = $0["key"] as? String, let cmd = $0["cmd"] as? String else { return nil }
        return HotKey(key: k, title: $0["title"] as? String ?? k, cmd: cmd)
    }
    if c.groups.isEmpty { c.error = "commands.json içinde grup yok." }
    return c
}

// MARK: - Genel kısayollar

/// Carbon RegisterEventHotKey: Erişilebilirlik izni istemez. (Olay dinleyici
/// izin isterdi ve her derlemede imza değiştiği için izin her deploy'da düşerdi.)
final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var installed = false

    private static let keyCodes: [String: Int] = [
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "space": kVK_Space, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
    ]

    /// "F8", "ctrl+opt+right" gibi. Tanınmazsa nil.
    static func parse(_ spec: String) -> (code: UInt32, mods: UInt32)? {
        var mods = 0
        var code: Int?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd": mods |= cmdKey
            case "opt", "alt": mods |= optionKey
            case "ctrl": mods |= controlKey
            case "shift": mods |= shiftKey
            default: code = keyCodes[part]
            }
        }
        guard let c = code else { return nil }
        return (UInt32(c), UInt32(mods))
    }

    var isActive: Bool { !refs.isEmpty }

    /// Kaydedemediklerinin adını döner (tanınmayan tuş ya da başkası almış).
    @discardableResult
    func register(_ list: [(String, () -> Void)]) -> [String] {
        installHandler()
        var failed: [String] = []
        for (i, (spec, action)) in list.enumerated() {
            guard let k = HotKeys.parse(spec) else { failed.append(spec); continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x53_44_43_4B), id: UInt32(i + 1))  // 'SDCK'
            if RegisterEventHotKey(k.code, k.mods, id, GetApplicationEventTarget(), 0, &ref) == noErr, let r = ref {
                refs.append(r); actions[UInt32(i + 1)] = action
            } else { failed.append(spec) }
        }
        return failed
    }

    func unregisterAll() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll(); actions.removeAll()
    }

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ud in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<HotKeys>.fromOpaque(ud!).takeUnretainedValue()
            me.actions[id.id]?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}

// MARK: - Kabuk

final class Shell {
    let pathExtra: [String]
    init(pathExtra: [String]) { self.pathExtra = pathExtra }

    private var env: [String: String] {
        var e = ProcessInfo.processInfo.environment
        let base = e["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        e["PATH"] = (pathExtra + [base]).joined(separator: ":")
        return e
    }

    func makeProcess(_ cmd: String) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        p.environment = env
        return p
    }

    /// Kısa komut: çıktısını toplayıp geri verir.
    func capture(_ cmd: String, timeout: TimeInterval = 90, done: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = self.makeProcess(cmd)
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            do { try p.run() } catch {
                DispatchQueue.main.async { done("Çalıştırılamadı: \(error.localizedDescription)") }; return
            }
            let deadline = DispatchTime.now() + timeout
            DispatchQueue.global().asyncAfter(deadline: deadline) { if p.isRunning { p.terminate() } }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            var out = String(data: data, encoding: .utf8) ?? ""
            if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out = p.terminationStatus == 0 ? "Tamam. (çıktı yok)" : "Hata — çıkış kodu \(p.terminationStatus)"
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    /// Kısa komutu bekleyerek çalıştırır; çıkarken temizlik için.
    func runSync(_ cmd: String, timeout: TimeInterval = 10) {
        let p = makeProcess(cmd)
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        p.waitUntilExit()
    }

    /// {fit}: telefonun genişliği korunup boyu Mac'in ana ekranının oranına
    /// uydurulmuş çözünürlük. Dik TV'de (1080x1920) telefon 1080x1920 olur,
    /// yansıtma ekranı kenar boşluğu olmadan doldurur. Ekran yataysa telefonun
    /// kendi çözünürlüğü döner, yani hiçbir şey değişmez.
    ///
    /// {fitdpi}: yoğunluk. Ekran kısalınca YouTube "kısa ekran" düzenine geçiyor
    /// (küçük resim solda, yazı sağda); 683dp'de geçti, 768dp'de geçmedi —
    /// ölçüldü. Alt çubuk kaydırırken gizlenip açıldıkça eşiğin iki yanına
    /// düşüyor ve düzen gidip geliyordu. O yüzden boyu en az 768dp tutacak
    /// yoğunluk seçilir (1920 piksel için 400; telefonun normali 450).
    func fitSize(dev: String) -> (size: String, dpi: String)? {
        let p = makeProcess("adb \(dev) shell 'wm size; wm density'")
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let s = String(data: d, encoding: .utf8) ?? ""
        guard let r = s.range(of: #"Physical size: (\d+)x(\d+)"#, options: .regularExpression) else { return nil }
        let nums = s[r].dropFirst("Physical size: ".count).split(separator: "x").compactMap { Int($0) }
        guard nums.count == 2 else { return nil }
        let pw = min(nums[0], nums[1]), ph = max(nums[0], nums[1])
        var physDpi = 0
        if let dr = s.range(of: #"Physical density: (\d+)"#, options: .regularExpression) {
            physDpi = Int(s[dr].dropFirst("Physical density: ".count)) ?? 0
        }
        guard physDpi > 0 else { return nil }

        // Menü çubuğunun olduğu ekran; scrcpy tam ekranı orada açar.
        guard let screen = NSScreen.screens.first else { return nil }
        let sw = screen.frame.width * screen.backingScaleFactor
        let sh = screen.frame.height * screen.backingScaleFactor
        guard sh > sw else { return ("\(pw)x\(ph)", "\(physDpi)") }

        var w = pw
        var h = Int((Double(pw) * Double(sh / sw)).rounded())
        if h > ph { h = ph; w = Int((Double(ph) * Double(sw / sh)).rounded()) }
        let minHeightDp = 768
        let dpi = min(physDpi, (h & ~1) * 160 / minHeightDp)
        return ("\(w & ~1)x\(h & ~1)", "\(dpi)")   // kodlayıcılar çift sayı ister
    }

    /// Telefona, scrcpy sunucusu bitince `cleanup`ı çalıştıran bir bekçi bırakır.
    /// Bağlantı nasıl koparsa kopsun (kablo, Mac uykusu, kapatma) sunucu ölür
    /// ve bekçi temizliği telefonda kendisi yapar; Mac'e ulaşması gerekmez.
    /// İki adım: tek adımda arka plandaki alt kabuk adb'nin terminalini açık
    /// tutuyor ve `adb shell` hiç dönmüyordu.
    func startPhoneWatchdog(dev: String, cleanup: String) {
        let script = """
        P='[c]om.genymobile.scrcpy.Server'
        i=0
        until pgrep -f "$P" >/dev/null; do i=$((i+1)); [ $i -ge 60 ] && break; sleep 1; done
        while pgrep -f "$P" >/dev/null; do sleep 2; done
        \(cleanup)

        """
        let b64 = Data(script.utf8).base64EncodedString()
        let f = "/data/local/tmp/scrcpydeck-watch.sh"
        runSync("adb \(dev) shell 'echo \(b64) | base64 -d > \(f)'")
        runSync("adb \(dev) shell 'setsid sh \(f) </dev/null >/dev/null 2>&1 &'")
    }

    func inTerminal(_ cmd: String) {
        let full = "export PATH=\"\(pathExtra.joined(separator: ":")):$PATH\"; \(cmd)"
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(full.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\nend tell"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    /// Telefonun IP'si: önce hotspot arayüzü, sonra Wi-Fi, en son Mac'in ağ geçidi.
    func phoneIP(dev: String) -> String? {
        for probe in ["adb \(dev) shell ip addr show swlan0", "adb \(dev) shell ip addr show wlan0"] {
            let p = makeProcess(probe)
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            guard (try? p.run()) != nil else { continue }
            let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let s = String(data: d, encoding: .utf8) ?? ""
            if let r = s.range(of: #"inet (\d+\.\d+\.\d+\.\d+)"#, options: .regularExpression) {
                return String(s[r]).replacingOccurrences(of: "inet ", with: "")
            }
        }
        let p = makeProcess("route -n get default 2>/dev/null | awk '/gateway:/{print $2}'")
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let s = (String(data: d, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    func devices() -> [Device] {
        let p = makeProcess("adb devices -l 2>/dev/null")
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let text = String(data: d, encoding: .utf8) ?? ""
        var out: [Device] = []
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ").filter { !$0.isEmpty }
            guard parts.count >= 2, parts[1] == "device" else { continue }
            let model = parts.first(where: { $0.hasPrefix("model:") }).map { String($0.dropFirst(6)) } ?? "cihaz"
            out.append(Device(serial: String(parts[0]), model: model))
        }
        return out
    }
}

/// Uzun süren komutların çıktısını biriktirir. Boru dolup komutu kilitlemesin
/// diye sürekli boşaltılır ve yalnızca son 16 KB tutulur.
final class OutputBuffer {
    private let q = DispatchQueue(label: "scrcpydeck.outbuf")
    private var data = Data()
    func append(_ d: Data) {
        q.sync { data.append(d); if data.count > 16384 { data.removeFirst(data.count - 16384) } }
    }
    var text: String { q.sync { String(data: data, encoding: .utf8) ?? "" } }
}

// MARK: - Denetleyici

final class Controller: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var config = Config()
    private var shell = Shell(pathExtra: [])
    private var running: [String: (Process, String)] = [:]   // id -> (process, başlık)
    private var stopping: Set<String> = []                   // elle durdurulanlar
    private var cleanups: [String: String] = [:]             // id -> bitince çalışacak komut
    private var devices: [Device] = []
    private var deviceText = "cihaz aranıyor…"
    private var timer: Timer?
    private var hadUSB = false   // son kontrolde USB'li cihaz var mıydı
    private let hotKeys = HotKeys()
    private var hotKeyFailed: [String] = []

    /// Otomatik başlatma makineye özeldir (commands.json iki Mac'te aynı):
    /// Mac mini'de açık, MacBook'ta kapalı. Menüden değiştirilir.
    private var autoStart: Bool {
        get { UserDefaults.standard.bool(forKey: "autoStart") }
        set { UserDefaults.standard.set(newValue, forKey: "autoStart") }
    }
    private var autoItem: Item? {
        for g in config.groups { for i in g.items where i.auto && i.kind == "run" { return i } }
        return nil
    }

    override init() {
        super.init()
        reload()
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        statusItem.menu = menu
        refreshIcon()
        refreshDevice()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshDevice(); self?.refreshIcon()
        }
    }

    private func reload() {
        hotKeys.unregisterAll()   // yeni listeyle refreshIcon yeniden kaydeder
        config = loadConfig()
        shell = Shell(pathExtra: config.pathExtra)
    }

    // MARK: Durum

    private func refreshDevice() {
        DispatchQueue.global(qos: .utility).async {
            let list = self.shell.devices()
            DispatchQueue.main.async {
                self.devices = list
                if list.isEmpty { self.deviceText = "cihaz bağlı değil" }
                else if list.count == 1 { self.deviceText = list[0].label }
                else { self.deviceText = "\(list.count) bağlantı — \(self.activeDevice()?.label ?? "seçilmedi")" }
                self.refreshIcon()
                self.autoStartIfPlugged()
            }
        }
    }

    /// Komutların hedefleyeceği cihaz. Tek cihaz varsa o; birden fazlaysa
    /// senin seçtiğin, seçmediysen USB olan (daha kararlı).
    private func activeDevice() -> Device? {
        if devices.count == 1 { return devices[0] }
        if let saved = UserDefaults.standard.string(forKey: "selectedSerial"),
           let d = devices.first(where: { $0.serial == saved }) { return d }
        return devices.first(where: { !$0.isWireless }) ?? devices.first
    }

    /// {dev} yer tutucusunun karşılığı: tek cihazda boş, çoklu cihazda -s SERİ.
    private func devFlag() -> String {
        guard let d = activeDevice() else { return "" }
        return "-s \(d.serial)"
    }

    /// Kablo takıldığı anda (USB yokken var olunca) otomatik komutu başlatır.
    /// Yalnızca geçişte çalışır: elle durdurursan kablo takılı kaldıkça yeniden
    /// açılmaz. Kablo gevşeyip geri gelirse yeni bir geçiş sayılır, yeniden bağlanır.
    /// Uygulama açılırken telefon zaten takılıysa da başlar.
    private func autoStartIfPlugged() {
        let hasUSB = devices.contains { !$0.isWireless }
        defer { hadUSB = hasUSB }
        guard hasUSB, !hadUSB, autoStart, let item = autoItem, running[item.id] == nil else { return }
        // Kablo takıldıktan sonra adb tam hazır olsun.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.running[item.id] == nil else { return }
            self.launch(item)
        }
    }

    private func refreshIcon() {
        guard let b = statusItem.button else { return }
        let symbol: String
        if !running.isEmpty                 { symbol = "play.rectangle.fill" }
        else if deviceText.contains("değil") { symbol = "iphone.slash" }
        else                                 { symbol = "iphone" }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "ScrcpyDeck")
        img?.isTemplate = true
        b.image = img
        b.title = running.isEmpty ? "" : " \(running.count)"
        b.toolTip = "ScrcpyDeck — \(deviceText)"
        updateHotKeys()
    }

    /// Kısayollar yalnızca bir yansıtma açıkken etkin; yoksa F8 gibi tuşlar
    /// Mac'te başka hiçbir yerde çalışmazdı.
    private func updateHotKeys() {
        let want = !running.isEmpty && !config.hotkeys.isEmpty
        if want == hotKeys.isActive { return }
        if !want { hotKeys.unregisterAll(); return }
        hotKeyFailed = hotKeys.register(config.hotkeys.map { hk in
            (hk.key, { [weak self] in
                guard let self = self else { return }
                let cmd = hk.cmd.replacingOccurrences(of: "{dev}", with: self.devFlag())
                self.shell.capture(cmd, timeout: 10) { _ in }
            })
        })
    }

    // MARK: Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        info(menu, deviceText)

        if let err = config.error {
            menu.addItem(.separator())
            for line in err.split(separator: "\n") { info(menu, String(line)) }
        }

        // Çalışanlar
        if !running.isEmpty {
            menu.addItem(.separator())
            info(menu, "Çalışanlar:")
            for (id, pair) in running.sorted(by: { $0.value.1 < $1.value.1 }) {
                let it = action(menu, "  ■  \(pair.1)", #selector(stopOne(_:)))
                it.representedObject = id
            }
            action(menu, "Tümünü durdur", #selector(stopAll))
        }

        // Cihaz seçimi — birden fazla bağlantı varken hangisinin kullanılacağı
        if devices.count > 1 {
            menu.addItem(.separator())
            info(menu, "Cihaz (aynı telefon iki kez bağlı):")
            let active = activeDevice()
            for d in devices {
                let it = action(menu, "  " + d.label, #selector(selectDevice(_:)))
                it.representedObject = d.serial
                it.state = (d.serial == active?.serial) ? .on : .off
            }
        }

        // Gruplar
        for g in config.groups {
            menu.addItem(.separator())
            let sub = NSMenu(); sub.autoenablesItems = false
            for item in g.items {
                let isRunning = running[item.id] != nil
                let mark = isRunning ? "■ " : ""
                let it = action(sub, mark + item.title, #selector(activate(_:)))
                it.representedObject = item.id
                it.state = isRunning ? .on : .off
            }
            let parent = NSMenuItem(title: g.name, action: nil, keyEquivalent: "")
            parent.isEnabled = true; parent.submenu = sub
            menu.addItem(parent)
        }

        if !config.hotkeys.isEmpty {
            menu.addItem(.separator())
            info(menu, "Kısayollar (yansıtma açıkken):")
            for hk in config.hotkeys {
                let bad = hotKeyFailed.contains(hk.key) ? "  — kaydedilemedi" : ""
                info(menu, "  \(hk.key)  \(hk.title)\(bad)")
            }
        }

        menu.addItem(.separator())
        if let a = autoItem {
            let it = action(menu, "Kablo takılınca otomatik başlat: \(a.title)", #selector(toggleAutoStart))
            it.state = autoStart ? .on : .off
        }
        action(menu, "Komutları düzenle…", #selector(openConfig))
        action(menu, "Yeniden yükle", #selector(reloadConfig))
        action(menu, "Çıkış", #selector(quit))
    }

    @discardableResult
    private func info(_ m: NSMenu, _ t: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false
        m.addItem(i); return i
    }

    @discardableResult
    private func action(_ m: NSMenu, _ t: String, _ s: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: "")
        i.target = self; i.isEnabled = true; m.addItem(i); return i
    }

    private func find(_ id: String) -> Item? {
        for g in config.groups { for i in g.items where i.id == id { return i } }
        return nil
    }

    // MARK: Eylemler

    @objc private func activate(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let item = find(id) else { return }

        if running[id] != nil { stop(id: id); return }

        if let q = item.confirm, !ask(q) { return }
        launch(item)
    }

    private func launch(_ item: Item) {
        var cmd = item.cmd.replacingOccurrences(of: "{dev}", with: devFlag())
        if item.needsIP {
            guard let ip = shell.phoneIP(dev: devFlag()) else {
                alert("IP bulunamadı", "Telefonun IP adresi okunamadı. USB ile bağlı mı?"); return
            }
            cmd = cmd.replacingOccurrences(of: "{ip}", with: ip)
        }
        if item.needsFit {
            guard let fit = shell.fitSize(dev: devFlag()) else {
                alert("Çözünürlük okunamadı", "Telefonun ekran boyutu okunamadı. USB ile bağlı mı?"); return
            }
            cmd = cmd.replacingOccurrences(of: "{fitdpi}", with: fit.dpi)
                     .replacingOccurrences(of: "{fit}", with: fit.size)
        }
        if item.needsFile {
            guard let p = pickFile() else { return }
            cmd = cmd.replacingOccurrences(of: "{file}", with: "'\(p)'")
        }
        if item.needsSave {
            guard let p = pickSave() else { return }
            cmd = cmd.replacingOccurrences(of: "{save}", with: "'\(p)'")
        }

        switch item.kind {
        case "run":
            if let pc = item.phoneCleanup { shell.startPhoneWatchdog(dev: devFlag(), cleanup: pc) }
            start(item: item, cmd: cmd,
                  cleanup: item.cleanup?.replacingOccurrences(of: "{dev}", with: devFlag()))
        case "terminal": shell.inTerminal(cmd)
        default:
            shell.capture(cmd) { [weak self] out in self?.alert(item.title, out) }
        }
    }

    private func start(item: Item, cmd: String, cleanup: String?) {
        // Komutu, TERM aldiginda kendi cocugunu da olduren bir sarmalayiciya al.
        // Aksi halde bilesik bir komutta (&&, | gibi) sadece kabuk oluyor ve
        // scrcpy sahipsiz calismaya devam ediyor.
        let wrapped = "\(cmd) & __child=$!; trap 'kill $__child 2>/dev/null' TERM INT; wait $__child"
        let p = shell.makeProcess(wrapped)

        // Cikti /dev/null'a gitmiyor: komut hemen hata verip olurse sana gosterelim.
        let buf = OutputBuffer()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { buf.append(d) }
        }

        let id = item.id
        let started = Date()
        p.terminationHandler = { [weak self] proc in
            let elapsed = Date().timeIntervalSince(started)
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.running[id] = nil
                // Çıkışta quit() temizliği kendisi bekleyerek yapmış olabilir.
                if let c = self.cleanups.removeValue(forKey: id) { self.shell.capture(c) { _ in } }
                let wasStopped = self.stopping.remove(id) != nil
                self.refreshIcon()
                // Elle durdurulmadiysa ve daha basinda hata verip ciktiysa goster.
                if !wasStopped && status != 0 && elapsed < 10 {
                    let out = buf.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.alert("\(item.title) — başlatılamadı",
                               out.isEmpty ? "Çıkış kodu \(status)" : out)
                }
            }
        }

        do { try p.run() } catch {
            alert(item.title, "Başlatılamadı: \(error.localizedDescription)"); return
        }
        running[id] = (p, item.title)
        if let c = cleanup { cleanups[id] = c }
        refreshIcon()
    }

    private func stop(id: String) {
        guard let (p, _) = running[id] else { return }
        stopping.insert(id)
        p.terminate()
        running[id] = nil
        refreshIcon()
    }

    @objc private func stopOne(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { stop(id: id) }
    }

    @objc private func stopAll() {
        for (id, _) in running { stop(id: id) }
    }

    @objc private func toggleAutoStart() {
        autoStart.toggle()
        // Açarken telefon zaten takılıysa beklemeden başlasın.
        if autoStart { hadUSB = false; autoStartIfPlugged() }
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String else { return }
        UserDefaults.standard.set(serial, forKey: "selectedSerial")
        refreshDevice()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    @objc private func reloadConfig() {
        reload()
        refreshIcon()
        alert("Yeniden yüklendi", config.error ?? "\(config.groups.count) grup, \(config.groups.reduce(0){ $0 + $1.items.count }) komut yüklendi.")
    }

    @objc private func quit() {
        // Temizliği uygulama kapanmadan bitir; yoksa telefon örneğin TV
        // çözünürlüğünde kalır.
        let procs = running.map { $0.value.0 }
        let pending = Array(cleanups.values)
        cleanups.removeAll()
        stopAll()
        for p in procs { p.waitUntilExit() }
        for c in pending { shell.runSync(c) }
        NSApp.terminate(nil)
    }

    // MARK: Pencereler

    private func alert(_ title: String, _ body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = String(body.prefix(3000))
        a.addButton(withTitle: "Tamam")
        a.runModal()
    }

    private func ask(_ q: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Onay"
        a.informativeText = q
        a.addButton(withTitle: "Evet"); a.addButton(withTitle: "Vazgeç")
        return a.runModal() == .alertFirstButtonReturn
    }

    private func pickFile() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url?.path : nil
    }

    private func pickSave() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel()
        p.nameFieldStringValue = "kayit.mp4"
        p.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
        return p.runModal() == .OK ? p.url?.path : nil
    }
}

// MARK: - Giriş

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
