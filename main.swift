import Cocoa
import UserNotifications

let configURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".proxyctl/config.json")

struct ProxyItem: Codable {
    var name: String, host: String, port: Int, user: String, pass: String
}
struct AppState: Codable {
    var proxies: [ProxyItem] = [], active: Int? = nil
}

func loadConfig() -> AppState {
    guard let d = try? Data(contentsOf: configURL), let s = try? JSONDecoder().decode(AppState.self, from: d) else {
        let s = AppState(); saveConfig(s); return s
    }
    return s
}
func saveConfig(_ s: AppState) {
    try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONEncoder().encode(s).write(to: configURL, options: .atomic)
}

// ── System Proxy ─────────────────────────────────────────────────────────────
func getServices() -> [String] {
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    t.arguments = ["-listallnetworkservices"]
    t.standardOutput = Pipe(); try? t.run(); t.waitUntilExit()
    let out = String(data: (t.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return out.components(separatedBy: "\n").map{$0.trimmingCharacters(in:.whitespaces)}
              .filter{!$0.isEmpty && !$0.hasPrefix("*") && !$0.hasPrefix("An asterisk")}
}
func runNS(_ args: String...) {
    for s in getServices() {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        t.arguments = [args[0], s] + Array(args.dropFirst())
        t.standardOutput = Pipe(); t.standardError = Pipe()
        try? t.run(); t.waitUntilExit()
    }
}
func enableProxy(host: String, port: Int, user: String, pass: String) {
    runNS("-setwebproxy", host, String(port))
    runNS("-setsecurewebproxy", host, String(port))
    runNS("-setwebproxystate", "on")
    runNS("-setsecurewebproxystate", "on")
    if !user.isEmpty {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        t.arguments = ["add-generic-password","-a",user,"-w",pass,"-s","webproxy:\(host):\(port)","-U"]
        t.standardOutput = Pipe(); try? t.run()
    }
}
func disableProxy() { runNS("-setwebproxystate","off"); runNS("-setsecurewebproxystate","off") }
func activeProxyStr() -> String? {
    guard let s = getServices().first else { return nil }
    let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    t.arguments = ["-getwebproxy", s]; t.standardOutput = Pipe(); try? t.run(); t.waitUntilExit()
    let out = String(data:(t.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding:.utf8) ?? ""
    guard out.contains("Enabled: Yes") else { return nil }
    let lines = out.components(separatedBy:"\n")
    let host = lines.first{$0.hasPrefix("Server: ")}?.split(separator:": ").dropFirst().joined(separator:": ") ?? ""
    let port = lines.first{$0.hasPrefix("Port: ")}?.split(separator:": ").last ?? ""
    return host.isEmpty ? nil : "\(host):\(port)"
}

// ── Sync all configs ─────────────────────────────────────────────────────────
func syncAllConfigs(state: AppState) {
    // 1. Bot's proxy config
    let botURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects/syndicate/claude-dashboard/data/proxies.json")
    if let ai = state.active, ai < state.proxies.count {
        let p = state.proxies[ai]
        let arr: [[String:Any]] = [["url":"http://\(p.user):\(p.pass)@\(p.host):\(p.port)","label":p.name,"status":"ok","latency_ms":NSNull(),"country":NSNull(),"active":true]]
        try? JSONSerialization.data(withJSONObject:arr, options:.prettyPrinted).write(to:botURL)
    }
    // 2. Oracle V2 PROXY_URL
    let oracleURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects/syndicate/claude-dashboard/oracle_v2/.env")
    if var env = try? String(contentsOf:oracleURL, encoding:.utf8), let ai = state.active, ai < state.proxies.count {
        let p = state.proxies[ai]
        let new = "PROXY_URL=http://\(p.user):\(p.pass)@\(p.host):\(p.port)"
        var lines = env.components(separatedBy:"\n")
        var found = false
        for i in 0..<lines.count {
            if lines[i].hasPrefix("PROXY_URL=") { lines[i] = new; found = true }
        }
        if !found { lines.append(new) }
        try? lines.joined(separator:"\n").write(to:oracleURL, atomically:true, encoding:.utf8)
    }
}

// ── Health ───────────────────────────────────────────────────────────────────
struct Health { var ok: Bool, country: String, city: String, ip: String, ms: Double }
let FLAGS = ["US":"🇺🇸","GB":"🇬🇧","DE":"🇩🇪","FR":"🇫🇷","NL":"🇳🇱","JP":"🇯🇵","SG":"🇸🇬",
             "AU":"🇦🇺","CA":"🇨🇦","BR":"🇧🇷","RU":"🇷🇺","IN":"🇮🇳","KR":"🇰🇷","IT":"🇮🇹",
             "ES":"🇪🇸","SE":"🇸🇪","NO":"🇳🇴","UA":"🇺🇦","PL":"🇵🇱","TR":"🇹🇷","CN":"🇨🇳","HK":"🇭🇰"]
func flag(_ c: String) -> String { FLAGS[c] ?? "🌐" }

func check(_ p: ProxyItem, _ cb: @escaping (Health)->Void) {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = 10
    cfg.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable:1, kCFNetworkProxiesHTTPPort:p.port, kCFNetworkProxiesHTTPProxy:p.host,
        kCFNetworkProxiesHTTPSEnable:1, kCFNetworkProxiesHTTPSPort:p.port, kCFNetworkProxiesHTTPSProxy:p.host
    ] as [String:Any]
    if !p.user.isEmpty {
        cfg.httpAdditionalHeaders = ["Proxy-Authorization":"Basic \(Data("\(p.user):\(p.pass)".utf8).base64EncodedString())"]
    }
    let t0 = Date()
    URLSession(configuration:cfg).dataTask(with: URL(string:"https://ipinfo.io/json")!) { d,_,_ in
        let ms = Date().timeIntervalSince(t0)*1000
        if let d, let j = try? JSONSerialization.jsonObject(with:d) as?[String:Any] {
            let c = (j["country"] as? String) ?? "??"
            let ct = (j["city"] as? String) ?? ""
            let ip = (j["ip"] as? String) ?? ""
            cb(Health(ok:true, country:c, city:ct, ip:ip, ms:ms))
        } else { cb(Health(ok:false,country:"??",city:"",ip:"",ms:-1)) }
    }.resume()
}

// ── App ──────────────────────────────────────────────────────────────────────
class AD: NSObject, NSApplicationDelegate {
    var si: NSStatusItem!
    var state = loadConfig()
    var health: [Int:Health] = [:]

    func applicationDidFinishLaunching(_ n: Notification) {
        si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        si.button?.target = self; si.button?.action = #selector(click)
        refresh(); build()
    }
    @objc func click() { si.button?.performClick(nil) }

    func notify(t: String, m: String) {
        let nc = UNUserNotificationCenter.current()
        nc.requestAuthorization(options:[.alert,.sound]) { _,_ in }
        let c = UNMutableNotificationContent()
        c.title=t; c.body=m; c.sound=UNNotificationSound.default
        nc.add(UNNotificationRequest(identifier: UUID().uuidString, content:c, trigger: nil))
    }

    func refresh() {
        for (i,p) in state.proxies.enumerated() {
            check(p) { [weak self] h in DispatchQueue.main.async { self?.health[i]=h; self?.build() } }
        }
    }

    func build() {
        state = loadConfig()
        let ai = state.active; let ap = ai.flatMap{$0<state.proxies.count ? state.proxies[$0] : nil}
        let ah = ai.flatMap{health[$0]}
        var title = "🌐"
        if let a=ap, let h=ah, h.ok { title="\(flag(h.country)) \(a.name)" }
        else if let a=ap { title="🌐 \(a.name)" }
        si.button?.title = title; si.button?.toolTip = "Proxy: \(ap?.name ?? "OFF")"

        let menu = NSMenu()
        for (i,p) in state.proxies.enumerated() {
            let act = i==ai; let h = health[i]
            let m = act ? "●" : "○"
            let st: String; if let h { st=h.ok ? "🟢 \(Int(h.ms))ms" : "🔴" } else { st="⏳" }
            let geo = (h?.ok==true) ? "  \(flag(h!.country)) \(h!.country) \(h!.city)" : ""
            let it = NSMenuItem(title:"\(m) \(st)  \(p.name)\(geo)", action:#selector(sw), keyEquivalent:"")
            it.representedObject=i; menu.addItem(it)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title:"🔌  Proxy OFF", action:#selector(off), keyEquivalent:""))
        menu.addItem(NSMenuItem(title:"🔄  Refresh", action:#selector(refreshAction), keyEquivalent:"r"))
        menu.addItem(NSMenuItem(title:"➕  Add Proxy...", action:#selector(add), keyEquivalent:"n"))
        if !state.proxies.isEmpty {
            menu.addItem(.separator())
            let rm = NSMenu()
            for (i,p) in state.proxies.enumerated() {
                let it = NSMenuItem(title:"  \(p.name)", action:#selector(rmProxy), keyEquivalent:"")
                it.representedObject=i; rm.addItem(it)
            }
            let rmi = NSMenuItem(title:"🗑️  Remove", action:nil, keyEquivalent:""); rmi.submenu=rm; menu.addItem(rmi)
        }
        menu.addItem(.separator())
        let im = NSMenu()
        for (i,p) in state.proxies.enumerated() {
            let h = health[i]; let d: String
            if let h, h.ok { d="  \(p.name): \(h.ip) (\(h.country))" } else { d="  \(p.name): \(p.host):\(p.port)" }
            im.addItem(NSMenuItem(title:d, action:nil, keyEquivalent:""))
        }
        let infoItem = NSMenuItem(title:"ℹ️  Info", action:nil, keyEquivalent:"")
        infoItem.submenu = im
        menu.addItem(infoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title:"🚪  Quit", action:#selector(quit), keyEquivalent:"q"))
        si.menu = menu
    }

    @objc func sw(_ s: NSMenuItem) {
        guard let i=s.representedObject as?Int, i<state.proxies.count else { return }
        state=loadConfig(); let p=state.proxies[i]
        enableProxy(host:p.host,port:p.port,user:p.user,pass:p.pass)
        state.active=i; saveConfig(state)
        syncAllConfigs(state:state)  // ← sync bot configs
        let h=health[i]; let g=(h?.ok==true) ? " (\(flag(h!.country)) \(h!.country))" : ""
        notify(t:"✅ Activated", m:"\(p.name)\(g)"); build()
    }
    @objc func off(_ s: NSMenuItem) {
        disableProxy(); state=loadConfig(); state.active=nil; saveConfig(state)
        notify(t:"🔌 Proxy OFF", m:"Disabled"); build()
    }
    @objc func refreshAction(_ s: NSMenuItem) { health.removeAll(); refresh() }
    @objc func add(_ s: NSMenuItem) {
        let a=NSAlert(); a.messageText="Add New Proxy"
        a.informativeText="Format: name | host:port:user:password\nExample: MyProxy | proxy.example.com:8080:username:password"
        a.addButton(withTitle:"Add"); a.addButton(withTitle:"Cancel")
        let tf=NSTextField(frame:NSRect(x:0,y:0,width:300,height:24))
        tf.placeholderString="MyProxy | proxy.example.com:8080:user:pass"; a.accessoryView=tf
        guard (a.runModal() == .alertFirstButtonReturn), !tf.stringValue.isEmpty else { return }
        let pts=tf.stringValue.split(separator:"|",maxSplits:1).map{$0.trimmingCharacters(in:.whitespaces)}
        guard pts.count==2 else { notify(t:"❌ Error",m:"Use: name | host:port:user:password"); return }
        let cp=pts[1].split(separator:":").map(String.init)
        guard cp.count>=2, let port=Int(cp[1]) else { notify(t:"❌ Error",m:"Need host:port"); return }
        state=loadConfig()
        let np=ProxyItem(name:pts[0],host:cp[0],port:port,user:cp.count>2 ? cp[2]:"",pass:cp.count>3 ? cp[3]:"")
        state.proxies.append(np); state.active=state.proxies.count-1; saveConfig(state)
        enableProxy(host:np.host,port:np.port,user:np.user,pass:np.pass)
        syncAllConfigs(state:state)  // ← sync bot configs
        notify(t:"✅ Added",m:"\(np.name) activated"); refresh()
    }
    @objc func rmProxy(_ s: NSMenuItem) {
        guard let i=s.representedObject as?Int else { return }
        state=loadConfig(); let n=state.proxies[i].name; state.proxies.remove(at:i)
        if state.active==i { state.active=nil }
        else if let a=state.active, a>i { state.active=a-1 }
        saveConfig(state); health.removeValue(forKey:i); syncAllConfigs(state:state); notify(t:"🗑️ Removed",m:n); build()
    }
    @objc func quit(_ s: NSMenuItem) { notify(t:"👋 Bye",m:"Closed"); NSApp.terminate(nil) }
}

let app=NSApplication.shared; let ad=AD(); app.delegate=ad; app.setActivationPolicy(.accessory); app.run()
