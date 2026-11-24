// Batería del Redragon M999 (dongle 2.4G, VID 0x320F / PID 0x226F) en la barra de menús.
// Protocolo (sacado del software de Redragon): Output rid 4, 64 bytes, comando 0x1A = "leer N bytes en dirección A".
//   trama: [0]=04 [1..2]=suma16 LE de [3..63] [3]=1A [4]=len [5..6]=addr [7]=0
//   respuesta (Input rid 4): [3]=1A, [7]=estado (0=OK), datos desde [8]: [8]=batería %, [9]=carga (0/1)
import AppKit
import IOKit.hid
import ServiceManagement

let vid = 0x320F, pid = 0x226F

func frame(cmd: UInt8 = 0x1A, len: UInt8 = 6, addr: UInt16 = 0) -> [UInt8] {
    var f = [UInt8](repeating: 0, count: 64)
    f[0] = 4; f[3] = cmd; f[4] = len; f[5] = UInt8(addr & 0xff); f[6] = UInt8(addr >> 8)
    let sum = f[3...].reduce(0) { $0 + Int($1) }
    f[1] = UInt8(sum & 0xff); f[2] = UInt8(sum >> 8 & 0xff)
    return f
}

/// nil si no es una respuesta válida a la lectura 0x1A.
func parse(_ b: [UInt8]) -> (percent: Int, charging: Bool)? {
    guard b.count > 9, b[0] == 4, b[3] == 0x1A, b[7] == 0, b[8] <= 100 else { return nil }
    return (Int(b[8]), b[9] == 1)
}

/// Copia `src` a `dstDir/<nombre>` (creando `dstDir`) y reemplaza una copia previa.
func copyApp(_ src: URL, toDir dstDir: URL) throws -> URL {
    let fm = FileManager.default
    let dst = dstDir.appendingPathComponent(src.lastPathComponent)
    try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
    if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
    try fm.copyItem(at: src, to: dst)
    return dst
}

if CommandLine.arguments.contains("--selftest") {
    precondition(frame().prefix(8).elementsEqual([0x04, 0x20, 0x00, 0x1A, 0x06, 0x00, 0x00, 0x00]))
    precondition(parse([4, 0x20, 0, 0x1A, 6, 0, 0, 0, 84, 1, 0, 0, 0, 0])! == (84, true))
    precondition(parse([4, 0x20, 0, 0x1A, 6, 0, 0, 0xFF, 84, 1, 0, 0, 0, 0]) == nil)
    precondition(parse([1, 0, 0xE8, 0xFF, 0, 0, 0, 0, 0, 0]) == nil)
    // copyApp: crea el destino, copia y reemplaza una copia previa
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("m999-selftest-\(getpid())")
    let src = tmp.appendingPathComponent("src/X.app")
    try! fm.createDirectory(at: src, withIntermediateDirectories: true)
    let out = tmp.appendingPathComponent("dest/Applications")   // no existe todavía
    try! "v1".write(to: src.appendingPathComponent("f"), atomically: true, encoding: .utf8)
    let d1 = try! copyApp(src, toDir: out)
    precondition(try! String(contentsOf: d1.appendingPathComponent("f"), encoding: .utf8) == "v1")
    try! "v2".write(to: src.appendingPathComponent("f"), atomically: true, encoding: .utf8)
    let d2 = try! copyApp(src, toDir: out)
    precondition(try! String(contentsOf: d2.appendingPathComponent("f"), encoding: .utf8) == "v2")
    try? fm.removeItem(at: tmp)
    print("selftest ok"); exit(0)
}

// Diagnóstico: estado del permiso de Monitorización de entrada tal como lo ve macOS para esta app.
// Ejecutar vía LaunchServices para que el permiso sea el de la app:  open -n -W --stdout /tmp/acceso.txt M999Battery.app --args --access
if CommandLine.arguments.contains("--access") {
    let s = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    print(s == kIOHIDAccessTypeGranted ? "granted" : s == kIOHIDAccessTypeDenied ? "denied" : "unknown"); exit(0)
}

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let info = NSMenuItem(title: "Buscando dongle…", action: nil, keyEquivalent: "")
    var mgr: IOHIDManager!
    var dev: IOHIDDevice?
    var lastOK: Date?             // última lectura válida
    var accessTimer: Timer?       // vigila la concesión del permiso de Monitorización de entrada
    var bt = Set<IOHIDDevice>()   // interfaces del mouse en modo Bluetooth (PID 0x22A4): macOS ya muestra su batería
    let btPid = 0x22A4
    let inbuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)

    /// Si la app corre fuera de /Applications (p. ej. desde el DMG), ofrece instalarla ahí.
    /// Devuelve true si relanzó la copia y esta instancia debe terminar.
    func offerInstall() -> Bool {
        let apps = URL(fileURLWithPath: "/Applications")
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let url = Bundle.main.bundleURL
        let here = url.deletingLastPathComponent().path
        guard here != apps.path, !UserDefaults.standard.bool(forKey: "noInstallPrompt") else { return false }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "¿Instalar M999Battery en Aplicaciones?"
        a.informativeText = "Se copiará a /Applications y se abrirá desde ahí. Si prefieres no moverla, funciona igual donde esté, incluido el inicio automático."
        a.addButton(withTitle: "Mover a /Applications")
        a.addButton(withTitle: "Dejarla aquí")
        let r = a.runModal()
        UserDefaults.standard.set(true, forKey: "noInstallPrompt")   // se pregunta una sola vez
        guard r == .alertFirstButtonReturn else { return false }
        do {
            let dst = try copyApp(url, toDir: apps)
            // El inicio automático se registra por ubicación: se quita aquí y la copia nueva lo vuelve a registrar.
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister(); UserDefaults.standard.set(true, forKey: "reregisterLogin")
            }
            // Si ya había una copia instalada corriendo, ciérrala para que no se quede la vieja.
            for o in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!) where o != .current { o.terminate() }
            if here == userApps.path { try? FileManager.default.removeItem(at: url) }   // no dejar un duplicado en ~/Applications
            NSWorkspace.shared.openApplication(at: dst, configuration: NSWorkspace.OpenConfiguration()) { _, _ in exit(0) }
            return true
        } catch {
            let e = NSAlert(); e.messageText = "No se pudo instalar"
            e.informativeText = "\(error.localizedDescription)\n\nPuedes arrastrar la app a la carpeta Aplicaciones tú mismo."
            e.runModal()
            return false
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        if offerInstall() { return }
        if UserDefaults.standard.bool(forKey: "reregisterLogin") {   // venimos de moverla: registra el inicio en la nueva ubicación
            try? SMAppService.mainApp.unregister(); try? SMAppService.mainApp.register()
            UserDefaults.standard.removeObject(forKey: "reregisterLogin")
        }
        let menu = NSMenu()
        menu.addItem(info)
        menu.addItem(withTitle: "Actualizar ahora", action: #selector(poll), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Abrir al iniciar sesión", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        show("🖱 –")

        mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(mgr, [[kIOHIDVendorIDKey: vid, kIOHIDProductIDKey: pid],
                                                    [kIOHIDVendorIDKey: vid, kIOHIDProductIDKey: btPid]] as CFArray)
        let me = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, d in
            Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue().attach(d)
        }, me)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, d in
            let app = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
            if app.bt.remove(d) != nil { app.refresh(); return }
            if app.dev == d { app.dev = nil; app.show("🖱 –"); app.info.title = "Dongle desconectado" }
        }, me)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, 0)
        checkAccess()
        Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
    }

    func show(_ s: String) { item.button?.title = s; print(s); fflush(stdout) }

    @objc func toggleLogin(_ s: NSMenuItem) {
        let svc = SMAppService.mainApp
        do { if svc.status == .enabled { try svc.unregister() } else { try svc.register() } }
        catch { info.title = "Inicio automático: \(error.localizedDescription)" }
        if svc.status == .requiresApproval {   // macOS pide confirmar el elemento de inicio
            info.title = "Aprueba M999Battery en Ajustes > General > Elementos de inicio"
            SMAppService.openSystemSettingsLoginItems()
        }
        s.state = svc.status == .enabled ? .on : .off
    }

    /// ¿Está el dongle en el bus USB? No depende del permiso: sin Monitorización de entrada macOS ni siquiera
    /// enumera los dispositivos de tipo teclado para esta app, así que HID no sirve para detectarlo.
    func dongleOnUSB() -> Bool {
        let m = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        m["idVendor"] = vid; m["idProduct"] = pid
        let s = IOServiceGetMatchingService(kIOMainPortDefault, m as CFDictionary)
        if s != 0 { IOObjectRelease(s) }
        return s != 0
    }

    /// Si el dongle está conectado y falta el permiso, lo pide (con el aviso del sistema y nuestra guía).
    func checkAccess() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted, dongleOnUSB() {
            info.title = "Falta el permiso de Monitorización de entrada"; ensureAccess()
        }
    }

    /// macOS solo deja que el usuario conceda Monitorización de entrada (el dongle se presenta como teclado).
    /// Primera vez: aviso nativo del sistema. Denegado: diálogo con botón a Ajustes. Después vigila y se conecta sola.
    func ensureAccess() {
        guard accessTimer == nil else { return }
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return
        case kIOHIDAccessTypeUnknown:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            // En algunos macOS ni el aviso del sistema registra la app en la lista: damos nuestra guía.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted { self?.showPermissionAlert() }
            }
        default: showPermissionAlert()
        }
        accessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else { return }
            t.invalidate(); self?.accessTimer = nil; self?.reattach()
        }
    }

    func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "M999Battery necesita Monitorización de entrada"
        a.informativeText = "macOS exige este permiso para leer el dongle, que se presenta como un teclado. La app no registra lo que escribes.\n\nEn la lista de Ajustes, activa M999Battery. Si no aparece, pulsa + y elige M999Battery en la carpeta Aplicaciones. Se conectará sola."
        a.addButton(withTitle: "Abrir Ajustes")
        a.addButton(withTitle: "Más tarde")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
    }

    /// Al concederse el permiso: cierra y reabre el dongle. Si macOS aplica el permiso solo a procesos nuevos,
    /// tras 4 s sin ninguna lectura válida la app se relanza sola (el relanzado ya arranca con permiso, sin vigilar).
    func reattach() {
        if let d = dev { IOHIDDeviceClose(d, 0); dev = nil }
        IOHIDManagerClose(mgr, 0); IOHIDManagerOpen(mgr, 0)   // vuelve a enumerar ya con permiso; los callbacks hacen attach
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.lastOK == nil, self.bt.isEmpty else { return }
            let c = NSWorkspace.OpenConfiguration(); c.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: c) { _, _ in exit(0) }
        }
    }

    /// Solo se muestra y consulta en 2.4G (sin el HID Bluetooth presente).
    func refresh() { item.isVisible = bt.isEmpty; print("visible=\(bt.isEmpty)"); fflush(stdout); if bt.isEmpty { poll() } }

    func attach(_ d: IOHIDDevice) {
        if (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int) == btPid { bt.insert(d); refresh(); return }
        // El dongle expone 2 interfaces; el canal de comandos es el de 64 bytes.
        guard (IOHIDDeviceGetProperty(d, kIOHIDMaxOutputReportSizeKey as CFString) as? Int) == 64 else { return }
        // Sin permiso, macOS deja "abrir" el dispositivo pero no entrega lecturas: hay que pedirlo ya, no solo si falla.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            info.title = "Falta el permiso de Monitorización de entrada"; ensureAccess()
        }
        guard IOHIDDeviceOpen(d, 0) == kIOReturnSuccess else {
            let granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            info.title = granted ? "No se pudo abrir el dongle" : "Falta el permiso de Monitorización de entrada"
            ensureAccess(); return
        }
        dev = d
        IOHIDDeviceRegisterInputReportCallback(d, inbuf, 128, { ctx, _, _, _, _, rep, len in
            let app = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
            guard let r = parse(Array(UnsafeBufferPointer(start: rep, count: len))) else { return }
            app.lastOK = Date()
            app.show("🖱 \(r.charging ? "⚡" : "")\(r.percent)%")
            let t = DateFormatter(); t.dateFormat = "HH:mm:ss"
            app.info.title = "M999: \(r.percent)%\(r.charging ? " (cargando)" : "") · \(t.string(from: Date()))"
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        poll()
    }

    @objc func poll() {
        if dev == nil { checkAccess() }   // dongle enchufado después de abrir la app
        guard let d = dev, bt.isEmpty else { return }
        let f = frame()
        _ = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 4, f, f.count)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
