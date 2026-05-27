import Foundation

struct Credentials {
    let id: String
    let password: String
}

class LoginManager {

    private let userId: String
    private let password: String
    private weak var webViewProvider: WebViewProviding?
    private var hasAttemptedLogin = false

    protocol WebViewProviding: AnyObject {
        func loadURL(_ url: URL)
        func evaluateJavaScript(_ js: String, completion: ((Any?, Error?) -> Void)?)
    }

    init(id: String, password: String, webViewProvider: WebViewProviding?) {
        self.userId = id
        self.password = password
        self.webViewProvider = webViewProvider
    }

    static func loadCredentials() -> Credentials? {
        // 1. Bundle Resources에서 찾기
        if let bundlePath = Bundle.main.path(forResource: ".env", ofType: nil),
           let creds = parseEnvFile(at: bundlePath) {
            return creds
        }
        // 2. Bundle root에서 찾기 (tvOS simulator 등)
        if let bundleRoot = Bundle.main.resourcePath {
            let rootEnv = (bundleRoot as NSString).appendingPathComponent("../.env")
            if let creds = parseEnvFile(at: rootEnv) {
                return creds
            }
        }
        // 3. Documents에서 찾기
        let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let envPath = (docPath as NSString).appendingPathComponent(".env")
        if let creds = parseEnvFile(at: envPath) {
            return creds
        }
        return nil
    }

    private static func parseEnvFile(at path: String) -> Credentials? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var id: String?, pw: String?
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if key == "SOOP_ID" { id = value }
                else if key == "SOOP_PASSWORD" { pw = value }
            }
        }
        guard let id = id, !id.isEmpty, let pw = pw, !pw.isEmpty else { return nil }
        return Credentials(id: id, password: pw)
    }

    func tryAutoLogin(url: String) {
        guard !hasAttemptedLogin else { return }
        let loginPatterns = ["login.sooplive.com", "afreeca.tv/login", "sooplive.com/login", "members.sooplive.com"]
        if loginPatterns.contains(where: { url.lowercased().contains($0) }) {
            print("[LoginManager] 로그인 페이지 감지 → 자동 로그인")
            hasAttemptedLogin = true
            performLogin()
        }
    }

    func forceLogin() {
        hasAttemptedLogin = false
        if let url = URL(string: "https://login.sooplive.com/afreeca/login.php") {
            webViewProvider?.loadURL(url)
        }
    }

    private func performLogin() {
        let safeId = userId.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")
        let safePw = password.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")

        let js = """
        (function(){
            function findLoginButton(iF){
                // 다양한 셀렉터 시도
                var sels = [
                    'button[type="submit"]',
                    'input[type="submit"]',
                    'button.login-btn', 'button.loginBtn', 'button.btn_login',
                    '.btn_login button', '.login-btn', '.loginBtn',
                    '[class*="login-btn"]', '[class*="loginBtn"]', '[class*="LoginButton"]',
                    'button[class*="login"]', 'button[class*="Login"]'
                ];
                for(var i=0;i<sels.length;i++){
                    var e=document.querySelector(sels[i]);
                    if(e) return e;
                }
                // 텍스트로 찾기 — "로그인" 텍스트를 가진 button/a/[role=button]
                var all=document.querySelectorAll('button,[role="button"],input[type="button"],a');
                for(var i=0;i<all.length;i++){
                    var t=(all[i].textContent||all[i].value||'').trim();
                    if(t==='로그인'||t==='Login'||t==='Sign in'||t==='Sign In'){
                        return all[i];
                    }
                }
                return null;
            }
            function go(){
                var iS=['input[name="userId"]','input[name="user_id"]','input[name="id"]','input[type="text"]','input[type="email"]'];
                var pS=['input[name="password"]','input[name="user_pw"]','input[type="password"]'];
                var iF=null,pF=null;
                for(var s of iS){var e=document.querySelector(s);if(e){iF=e;break}}
                for(var s of pS){var e=document.querySelector(s);if(e){pF=e;break}}
                if(iF&&pF){
                    var sv=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
                    sv.call(iF,'\(safeId)');iF.dispatchEvent(new Event('input',{bubbles:true}));iF.dispatchEvent(new Event('change',{bubbles:true}));
                    sv.call(pF,'\(safePw)');pF.dispatchEvent(new Event('input',{bubbles:true}));pF.dispatchEvent(new Event('change',{bubbles:true}));
                    var b=findLoginButton(iF);
                    if(b){
                        setTimeout(function(){
                            try{ b.click(); }catch(e){}
                            // 0.7초 후에도 페이지에 그대로면 form.submit() fallback
                            setTimeout(function(){
                                if(document.querySelector('input[type="password"]')){
                                    var f=iF.closest('form');
                                    if(f){ try{ f.submit(); }catch(e){} }
                                }
                            },700);
                        },500);
                        return 'clicked:'+(b.tagName||'')+'/'+(b.className||'').toString().substring(0,40);
                    }
                    var f=iF.closest('form');
                    if(f){setTimeout(function(){try{f.submit();}catch(e){}},500);return 'form.submit';}
                    return 'no-button-no-form';
                }
                return 'no-inputs';
            }
            if(document.readyState==='complete') return go();
            window.addEventListener('load',function(){setTimeout(go,1000)});
            return 'pending-load';
        })();
        """

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.webViewProvider?.evaluateJavaScript(js) { result, error in
                if let error = error {
                    print("[LoginManager] JS 에러: \(error.localizedDescription)")
                } else {
                    print("[LoginManager] 결과: \(String(describing: result))")
                }
            }
        }
    }
}
