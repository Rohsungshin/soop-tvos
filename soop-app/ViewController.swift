import UIKit
import WebKit
import AVKit
import AVFoundation

// MARK: - TVWebView
//
// WKWebView를 non-focusable로 만든다. 그렇게 하지 않으면 페이지 로드 후
// tvOS focus engine이 WKWebView로 focus를 옮기고, 동시에 first responder도
// WKWebView로 강제 전환된다. 그러면 WebKit 내부 .select press 핸들러가
// 우리의 PressInterceptor보다 먼저 press를 가로채서 첫 번째 클릭 이후
// 우리 코드가 더 이상 호출되지 않게 된다.
class TVWebView: WKWebView {
    override var canBecomeFocused: Bool { false }
}

// MARK: - PressInterceptor
//
// WKWebView 위에 올린 투명 UIView. focusable + first responder를 모두 잡고
// 모든 리모컨 press 이벤트를 독점 처리한다.
// point(inside:with:)가 false라 마우스/터치는 그대로 WKWebView로 통과한다.
private class PressInterceptor: UIView {

    enum Direction { case up, down, left, right }

    var onDirection: ((Direction) -> Void)?
    var onSelect: (() -> Void)?
    var onMenu: (() -> Void)?

    // 텍스트 입력 모드 — 키보드 입력을 직접 webView로 주입
    var inTextInputMode: Bool = false
    var onTextInput: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onEnter: (() -> Void)?

    // alert/modal 떠있을 때만 focus 양보
    var allowFocus: Bool = true

    override var canBecomeFocused: Bool { allowFocus }
    override var canBecomeFirstResponder: Bool { allowFocus }

    // 마우스/포인터/터치 이벤트는 hit-test 통과 → 아래 WKWebView로 전달
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    // ─── pressesBegan ───
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // 텍스트 입력 모드: 키보드의 letter/숫자/special key 입력을 가로채 webView에 주입
        if inTextInputMode {
            for press in presses {
                // Menu(ESC) — 텍스트 모드 종료
                if press.type == .menu {
                    onMenu?()
                    return
                }
                if let key = press.key {
                    // Backspace
                    if key.keyCode == .keyboardDeleteOrBackspace {
                        onBackspace?()
                        return
                    }
                    // Enter — 폼 제출 또는 줄바꿈
                    if key.keyCode == .keyboardReturnOrEnter || key.keyCode == .keyboardReturn {
                        onEnter?()
                        return
                    }
                    // 일반 문자 (letter/digit/space/punctuation)
                    let chars = key.characters
                    if !chars.isEmpty,
                       let first = chars.unicodeScalars.first,
                       !CharacterSet.controlCharacters.contains(first) {
                        onTextInput?(chars)
                        return
                    }
                }
            }
            return  // 다른 press는 그냥 무시 (텍스트 모드 안에선)
        }

        // 일반 모드
        for press in presses {
            switch press.type {
            case .select:     onSelect?();         return
            case .menu:       onMenu?();            return
            case .upArrow:    onDirection?(.up);    return
            case .downArrow:  onDirection?(.down);  return
            case .leftArrow:  onDirection?(.left);  return
            case .rightArrow: onDirection?(.right); return
            default: break
            }
            if let key = press.key {
                switch key.keyCode {
                case .keyboardUpArrow:    onDirection?(.up);    return
                case .keyboardDownArrow:  onDirection?(.down);  return
                case .keyboardLeftArrow:  onDirection?(.left);  return
                case .keyboardRightArrow: onDirection?(.right); return
                default: break
                }
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if shouldConsume(presses) { return }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if shouldConsume(presses) { return }
        super.pressesCancelled(presses, with: event)
    }

    private func shouldConsume(_ presses: Set<UIPress>) -> Bool {
        for press in presses {
            switch press.type {
            case .select, .menu, .upArrow, .downArrow, .leftArrow, .rightArrow:
                return true
            default: break
            }
            if let key = press.key {
                switch key.keyCode {
                case .keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow, .keyboardRightArrow:
                    return true
                default: break
                }
            }
        }
        return false
    }

    // ─── 하드웨어 키보드 단축키 ───
    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow,    modifierFlags: [], action: #selector(cmdUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow,  modifierFlags: [], action: #selector(cmdDown)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow,  modifierFlags: [], action: #selector(cmdLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(cmdRight)),
            UIKeyCommand(input: "\r",                         modifierFlags: [], action: #selector(cmdSelect)),
            UIKeyCommand(input: UIKeyCommand.inputEscape,     modifierFlags: [], action: #selector(cmdMenu)),
        ]
    }
    @objc private func cmdUp()     { onDirection?(.up) }
    @objc private func cmdDown()   { onDirection?(.down) }
    @objc private func cmdLeft()   { onDirection?(.left) }
    @objc private func cmdRight()  { onDirection?(.right) }
    @objc private func cmdSelect() { onSelect?() }
    @objc private func cmdMenu()   { onMenu?() }
}

// MARK: - 커스텀 가상 키보드 ViewController
// tvOS의 UIAlertController/시스템 키보드는 focus 관리가 불안정해서 키 입력이 사라지는
// 문제가 있다. 모든 키를 UIButton으로 직접 구성한 키보드 — focus engine 표준 동작.
private class VirtualKeyboardViewController: UIViewController {
    private let displayLabel = UILabel()
    private var displayText: String = ""
    private var isSecure: Bool = false
    var initialText: String = ""
    var placeholderText: String = ""
    var onConfirm: ((String) -> Void)?
    var onCancel: (() -> Void)?

    // 키 레이아웃 — 숫자, 영문 소문자, 특수문자
    // 비밀번호에 자주 쓰이는 ! @ # $ % ^ & * 등 포함
    private let keyRows: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l","-"],
        ["z","x","c","v","b","n","m",".","_","@"],
        ["!","#","$","%","^","&","*","+","=","?"],
        ["(",")","[","]","{","}","/","\\",":",";"],
    ]
    private var firstKeyButton: UIButton?
    private var letterButtons: [(button: UIButton, char: String)] = []
    private var isUppercase: Bool = false
    private var capsButton: UIButton?

    convenience init(initialText: String, placeholder: String, isSecure: Bool) {
        self.init(nibName: nil, bundle: nil)
        self.initialText = initialText
        self.placeholderText = placeholder
        self.isSecure = isSecure
        self.displayText = initialText
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 0.97)

        // 표시용 라벨 (현재 입력 텍스트)
        displayLabel.font = UIFont.monospacedSystemFont(ofSize: 44, weight: .medium)
        displayLabel.textColor = .white
        displayLabel.backgroundColor = UIColor(white: 0.18, alpha: 1)
        displayLabel.textAlignment = .center
        displayLabel.layer.cornerRadius = 12
        displayLabel.layer.masksToBounds = true
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(displayLabel)
        updateDisplay()

        // 키 그리드
        let keysStack = UIStackView()
        keysStack.axis = .vertical
        keysStack.spacing = 10
        keysStack.alignment = .center
        keysStack.translatesAutoresizingMaskIntoConstraints = false
        for row in keyRows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 10
            rowStack.distribution = .fillEqually
            for ch in row {
                let btn = makeKeyButton(title: ch)
                btn.addAction(UIAction { [weak self] _ in
                    guard let self = self else { return }
                    // 알파벳이면 대소문자 토글 상태 반영, 숫자/특수문자는 그대로
                    let isLetter = ch.first.map { $0.isLetter } ?? false
                    self.append(isLetter && self.isUppercase ? ch.uppercased() : ch)
                }, for: .primaryActionTriggered)
                // letter 버튼만 추적 (대소문자 전환용)
                if ch.first?.isLetter == true {
                    letterButtons.append((btn, ch))
                }
                rowStack.addArrangedSubview(btn)
                if firstKeyButton == nil { firstKeyButton = btn }
            }
            keysStack.addArrangedSubview(rowStack)
        }
        view.addSubview(keysStack)

        // 액션 버튼들 (Space, Backspace, Clear, 확인, 취소)
        let actionStack = UIStackView()
        actionStack.axis = .horizontal
        actionStack.spacing = 20
        actionStack.distribution = .fillEqually
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let shiftBtn = makeActionButton(title: "⇧ abc", width: 0)
        shiftBtn.addAction(UIAction { [weak self] _ in self?.toggleCase() }, for: .primaryActionTriggered)
        capsButton = shiftBtn

        let spaceBtn = makeActionButton(title: "Space", width: 0)
        spaceBtn.addAction(UIAction { [weak self] _ in self?.append(" ") }, for: .primaryActionTriggered)

        let backBtn = makeActionButton(title: "⌫ 지우기", width: 0)
        backBtn.addAction(UIAction { [weak self] _ in self?.backspace() }, for: .primaryActionTriggered)

        let clearBtn = makeActionButton(title: "전체삭제", width: 0)
        clearBtn.addAction(UIAction { [weak self] _ in self?.clearAll() }, for: .primaryActionTriggered)

        let cancelBtn = makeActionButton(title: "취소", width: 0)
        cancelBtn.addAction(UIAction { [weak self] _ in
            // dismiss 완료 후 콜백 — 그래야 부모의 restoreFocus()가 정상 작동
            let handler = self?.onCancel
            self?.dismiss(animated: true) { handler?() }
        }, for: .primaryActionTriggered)

        let okBtn = makeActionButton(title: "확인", width: 0)
        okBtn.setTitleColor(.black, for: .normal)
        okBtn.setTitleColor(.black, for: .focused)
        okBtn.backgroundColor = UIColor(red: 1, green: 0.8, blue: 0, alpha: 1)
        okBtn.addAction(UIAction { [weak self] _ in
            let text = self?.displayText ?? ""
            let handler = self?.onConfirm
            self?.dismiss(animated: true) { handler?(text) }
        }, for: .primaryActionTriggered)

        [shiftBtn, spaceBtn, backBtn, clearBtn, cancelBtn, okBtn].forEach { actionStack.addArrangedSubview($0) }
        view.addSubview(actionStack)

        NSLayoutConstraint.activate([
            displayLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            displayLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            displayLabel.widthAnchor.constraint(equalToConstant: 900),
            displayLabel.heightAnchor.constraint(equalToConstant: 90),

            keysStack.topAnchor.constraint(equalTo: displayLabel.bottomAnchor, constant: 40),
            keysStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            actionStack.topAnchor.constraint(equalTo: keysStack.bottomAnchor, constant: 30),
            actionStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionStack.widthAnchor.constraint(equalToConstant: 1100),
            actionStack.heightAnchor.constraint(equalToConstant: 70),
        ])
    }

    private func makeKeyButton(title: String) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.setTitle(title, for: .normal)  // 그대로 표시 (소문자/숫자/특수문자)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .medium)
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(.black, for: .focused)
        btn.backgroundColor = UIColor(white: 0.25, alpha: 1)
        btn.layer.cornerRadius = 10
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 80).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 80).isActive = true
        return btn
    }

    private func toggleCase() {
        isUppercase.toggle()
        // 모든 letter 버튼의 표시 텍스트 업데이트
        for (btn, ch) in letterButtons {
            btn.setTitle(isUppercase ? ch.uppercased() : ch, for: .normal)
        }
        // Shift 버튼 표시 업데이트
        capsButton?.setTitle(isUppercase ? "⇧ ABC" : "⇧ abc", for: .normal)
        capsButton?.backgroundColor = isUppercase
            ? UIColor(red: 0.2, green: 0.7, blue: 1, alpha: 1)
            : UIColor(white: 0.3, alpha: 1)
    }

    private func makeActionButton(title: String, width: CGFloat) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(.black, for: .focused)
        btn.backgroundColor = UIColor(white: 0.3, alpha: 1)
        btn.layer.cornerRadius = 10
        return btn
    }

    private func append(_ s: String) {
        displayText += s
        updateDisplay()
    }

    private func backspace() {
        guard !displayText.isEmpty else { return }
        displayText.removeLast()
        updateDisplay()
    }

    private func clearAll() {
        displayText = ""
        updateDisplay()
    }

    private func updateDisplay() {
        if displayText.isEmpty {
            displayLabel.text = placeholderText.isEmpty ? "입력하세요" : placeholderText
            displayLabel.textColor = UIColor(white: 0.6, alpha: 1)
        } else if isSecure {
            displayLabel.text = String(repeating: "•", count: displayText.count)
            displayLabel.textColor = .white
        } else {
            displayLabel.text = displayText
            displayLabel.textColor = .white
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        // 첫 키를 초기 focus로
        if let f = firstKeyButton { return [f] }
        return super.preferredFocusEnvironments
    }
}

// MARK: - WKScriptMessageHandler 리테인 사이클 방지 래퍼
private class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}

// MARK: - 메인 ViewController
class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate,
                      WKScriptMessageHandler, LoginManager.WebViewProviding {

    private var webView: TVWebView!
    private var pressInterceptor: PressInterceptor!
    private var loginManager: LoginManager!

    // 세션당 자동 로그인은 1회만. 로그인 후 무한 루프 방지.
    private var autoLoginAttempted = false

    // tvOS focus engine이 항상 PressInterceptor를 선택하도록 강제.
    // 단, alert/UIAlertController 같은 모달이 떠 있을 때는 시스템에 양보 —
    // 그렇지 않으면 alert의 "확인" 버튼이 포커스를 못 받아 alert을 닫을 수 없게 됨.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if presentedViewController != nil {
            return super.preferredFocusEnvironments
        }
        if let p = pressInterceptor { return [p] }
        return super.preferredFocusEnvironments
    }

    // URL 표시용 작은 라벨 (상단)
    private lazy var urlBar: UILabel = {
        let l = UILabel()
        l.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        l.textColor = .white
        l.backgroundColor = UIColor(white: 0, alpha: 0.7)
        l.textAlignment = .left
        l.numberOfLines = 1
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.5
        l.layer.cornerRadius = 4
        l.layer.masksToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private func setupURLBar() {
        view.addSubview(urlBar)
        NSLayoutConstraint.activate([
            urlBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            urlBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            urlBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            urlBar.heightAnchor.constraint(equalToConstant: 22),
        ])
        view.bringSubviewToFront(urlBar)
    }

    private func updateURLBar(_ prefix: String = "") {
        let url = webView?.url?.absoluteString ?? "(no url)"
        urlBar.text = " [\(prefix)] \(url)"
        view.bringSubviewToFront(urlBar)
    }

    // MARK: - 라이프사이클

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView()
        setupURLBar()
        loadCredentialsAndStart()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // AVPlayerViewController 등 fullScreen modal이 dismiss된 후에도 호출됨
        restoreFocus()
    }

    // 텍스트 입력 모드(allowFocus=false) 중 Menu 키 → 모드 종료
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !pressInterceptor.allowFocus {
            for press in presses {
                if press.type == .menu {
                    exitTextInputMode()
                    return
                }
            }
        }
        super.pressesBegan(presses, with: event)
    }

    private func exitTextInputMode() {
        pressInterceptor.inTextInputMode = false
        hideInputHint()
        webView.evaluateJavaScript("if(document.activeElement)document.activeElement.blur()", completionHandler: nil)
    }

    // MARK: - WebView 설정

    // 완전한 Safari User Agent. 끝의 "Version/.. Safari/.." 토큰이 없으면
    // SOOP이 "지원 브라우저 아님"으로 판정해 라이브 페이지에서 흰 안내 화면을
    // 띄울 수 있다.
    private let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.applicationNameForUserAgent = safariUA
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        config.userContentController.add(WeakMessageHandler(self), name: "keyboard")
        config.userContentController.add(WeakMessageHandler(self), name: "debug")
        config.userContentController.add(WeakMessageHandler(self), name: "hlsPlay")

        // ─── 기본 CSS + addEventListener 추적 (메인 프레임, document start) ───
        // SOOP 스크립트보다 먼저 실행되어야 함. 여기서 EventTarget.prototype.addEventListener를
        // 가로채 click/mousedown 핸들러를 element에 저장. 나중에 _click이 직접 호출해
        // event.isTrusted 체크와 user-gesture 요구를 우회한다.
        let css = """
        (function(){
            var s=document.createElement('style');
            s.id='tvos-base';
            s.textContent=`
                html{background:#000!important}
                body{margin:0!important;padding:0!important;overflow-x:hidden!important}
                ::-webkit-scrollbar{display:none!important}
                a,button,[role="button"],[onclick]{cursor:pointer!important}
            `;
            (document.head||document.documentElement).appendChild(s);

            // ★ window.close() 가로채기 — Naver OAuth 같은 팝업 기반 로그인이
            // 콜백 후 자기 자신을 닫으려고 하는데, WKWebView에선 메인 webView가 닫혀
            // 검정 화면이 되는 문제. 대신 SOOP 홈으로 navigate.
            try{
                var origClose=window.close;
                window.close=function(){
                    try{
                        if(window.opener){
                            try{ window.opener.postMessage({type:'oauth-done'},'*'); }catch(e){}
                        }
                        if(location.host.indexOf('sooplive')<0 && location.host.indexOf('afreeca')<0){
                            location.href='https://www.sooplive.com/';
                        }
                    }catch(e){}
                };
            }catch(e){}

            // 디버그 로그 박스 (document_start 시점에 미리 생성)
            function ensureEarlyLog(){
                var el=document.getElementById('soop-debug-log');
                if(el) return el;
                if(!document.body && !document.documentElement) return null;
                el=document.createElement('div');
                el.id='soop-debug-log';
                el.style.cssText='position:fixed!important;top:80px!important;left:10px!important;'+
                    'width:520px!important;max-height:380px!important;overflow:hidden!important;'+
                    'background:rgba(0,0,0,0.92)!important;color:#0f0!important;padding:8px!important;'+
                    'font:11px monospace!important;'+
                    'z-index:2147483647!important;pointer-events:none!important;border:1px solid #0f0!important;white-space:pre-wrap!important';
                (document.body||document.documentElement).appendChild(el);
                return el;
            }
            function earlyLog(msg){
                var el=ensureEarlyLog();
                if(el) el.textContent=(el.textContent+'\\n'+msg).split('\\n').slice(-30).join('\\n');
            }
            // DOMContentLoaded 시 한 번 환경 정보 표시
            document.addEventListener('DOMContentLoaded',function(){
                earlyLog('UA: '+navigator.userAgent.substring(0,80));
                earlyLog('MediaSource: '+(typeof window.MediaSource!=='undefined'));
                earlyLog('EME: '+(typeof navigator.requestMediaKeySystemAccess==='function'));
                earlyLog('Cookies: '+navigator.cookieEnabled);
            });

            // ★ console.error/warn 캡처 — SOOP 플레이어가 안 되는 정확한 이유 추적
            try{
                ['error','warn'].forEach(function(level){
                    var orig=console[level];
                    console[level]=function(){
                        try{
                            var args=Array.prototype.slice.call(arguments).map(function(a){
                                try{
                                    if(a instanceof Error) return a.name+':'+a.message;
                                    if(typeof a==='object') return JSON.stringify(a).substring(0,150);
                                    return String(a).substring(0,150);
                                }catch(e){return '[?]';}
                            }).join(' ');
                            if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.debug){
                                window.webkit.messageHandlers.debug.postMessage('console.'+level+': '+args);
                            }
                            earlyLog('['+level+'] '+args.substring(0,120));
                        }catch(e){}
                        return orig.apply(console,arguments);
                    };
                });
                // 글로벌 에러도 캡처
                window.addEventListener('error',function(e){
                    var msg='[uncaught] '+(e.message||'')+' @ '+(e.filename||'').substring(0,60)+':'+(e.lineno||'');
                    if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.debug){
                        window.webkit.messageHandlers.debug.postMessage(msg);
                    }
                    earlyLog(msg.substring(0,120));
                },true);
                window.addEventListener('unhandledrejection',function(e){
                    var msg='[unhandled] '+(e.reason&&e.reason.message?e.reason.message:String(e.reason)).substring(0,150);
                    if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.debug){
                        window.webkit.messageHandlers.debug.postMessage(msg);
                    }
                    earlyLog(msg.substring(0,120));
                });
            }catch(e){}

            // ★ addEventListener monkey-patch
            var orig=EventTarget.prototype.addEventListener;
            EventTarget.prototype.addEventListener=function(type,handler,options){
                try{
                    if((type==='click'||type==='mousedown'||type==='mouseup'||type==='pointerdown')
                        && typeof handler==='function'){
                        if(!this._soopHandlers) this._soopHandlers={};
                        if(!this._soopHandlers[type]) this._soopHandlers[type]=[];
                        // 중복 방지
                        if(this._soopHandlers[type].indexOf(handler)<0){
                            this._soopHandlers[type].push(handler);
                        }
                    }
                }catch(e){}
                return orig.apply(this,arguments);
            };
            // removeEventListener도 패치
            var origRemove=EventTarget.prototype.removeEventListener;
            EventTarget.prototype.removeEventListener=function(type,handler,options){
                try{
                    if(this._soopHandlers&&this._soopHandlers[type]){
                        var arr=this._soopHandlers[type];
                        var i=arr.indexOf(handler);
                        if(i>=0) arr.splice(i,1);
                    }
                }catch(e){}
                return origRemove.apply(this,arguments);
            };
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: css, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        // HLS URL 캡처: 모든 프레임에서 document_start에 실행 (iframe 내 플레이어도 포함)
        config.userContentController.addUserScript(
            WKUserScript(source: hlsCaptureJS(), injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        // ─── 영상 자동재생 (모든 프레임 포함) ───
        config.userContentController.addUserScript(
            WKUserScript(source: videoAutoplayJS(), injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )

        // ─── 네비게이션 + 가상 키보드 (메인 프레임) ───
        config.userContentController.addUserScript(
            WKUserScript(source: navigationJS(), injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        // WKWebView (non-focusable 서브클래스)
        webView = TVWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.customUserAgent = safariUA
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.isOpaque = false
        view.addSubview(webView)

        // PressInterceptor — WKWebView 위에 투명 오버레이
        pressInterceptor = PressInterceptor(frame: view.bounds)
        pressInterceptor.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pressInterceptor.backgroundColor = .clear
        view.addSubview(pressInterceptor)

        pressInterceptor.onDirection = { [weak self] dir in
            let d: String
            switch dir {
            case .up:    d = "up"
            case .down:  d = "down"
            case .left:  d = "left"
            case .right: d = "right"
            }
            self?.webView.evaluateJavaScript("window._nav&&window._nav('\(d)')", completionHandler: nil)
        }
        pressInterceptor.onSelect = { [weak self] in
            self?.webView.evaluateJavaScript("window._click&&window._click()", completionHandler: nil)
        }
        pressInterceptor.onMenu = { [weak self] in
            // 텍스트 입력 모드 중이면 모드 종료, 아니면 일반 뒤로가기
            if self?.pressInterceptor.inTextInputMode == true {
                self?.exitTextInputMode()
                return
            }
            guard let wv = self?.webView else { return }
            if wv.canGoBack { wv.goBack() }
        }

        // 텍스트 입력 모드: 키 입력을 JS로 주입
        pressInterceptor.onTextInput = { [weak self] chars in
            let safe = chars
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            let js = """
            (function(){
                var el=document.activeElement;
                if(!el||(el.tagName!=='INPUT'&&el.tagName!=='TEXTAREA'&&!el.isContentEditable)) return;
                if(el.tagName==='INPUT'||el.tagName==='TEXTAREA'){
                    var desc=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value');
                    var newVal=(el.value||'')+'\(safe)';
                    if(desc&&desc.set) desc.set.call(el,newVal); else el.value=newVal;
                } else {
                    el.textContent=(el.textContent||'')+'\(safe)';
                }
                el.dispatchEvent(new Event('input',{bubbles:true}));
                el.dispatchEvent(new Event('keyup',{bubbles:true}));
            })();
            """
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
        pressInterceptor.onBackspace = { [weak self] in
            let js = """
            (function(){
                var el=document.activeElement;
                if(!el||(el.tagName!=='INPUT'&&el.tagName!=='TEXTAREA'&&!el.isContentEditable)) return;
                if(el.tagName==='INPUT'||el.tagName==='TEXTAREA'){
                    var v=el.value||''; if(v.length===0) return;
                    var desc=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value');
                    var newVal=v.slice(0,-1);
                    if(desc&&desc.set) desc.set.call(el,newVal); else el.value=newVal;
                } else {
                    el.textContent=(el.textContent||'').slice(0,-1);
                }
                el.dispatchEvent(new Event('input',{bubbles:true}));
            })();
            """
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
        pressInterceptor.onEnter = { [weak self] in
            // Enter — 폼 제출 시도 (또는 텍스트 모드 종료)
            self?.webView.evaluateJavaScript("""
                (function(){
                    var el=document.activeElement;
                    if(el&&el.form){ try{ el.form.submit(); }catch(e){} }
                })();
            """, completionHandler: nil)
            self?.exitTextInputMode()
        }
    }

    // MARK: - 영상 자동재생 JS (모든 프레임)

    // MARK: - HLS 캡처 (모든 프레임, document_start)

    private func hlsCaptureJS() -> String {
        return """
        (function(){
            function log(m){
                try{
                    var s='[HLS] '+String(m).substring(0,180);
                    try{console.error(s);}catch(e){}
                    try{
                        if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.debug)
                            window.webkit.messageHandlers.debug.postMessage(s);
                    }catch(e){}
                    try{
                        var el=document.getElementById('soop-debug-log');
                        if(el) el.textContent=(el.textContent+'\n'+s).split('\n').slice(-25).join('\n');
                    }catch(e){}
                }catch(e){}
            }
            log('init frame='+location.href.substring(0,70));

            // tvOS WKWebView에서 MediaSource가 있어도 live HLS가 실패하는 경우가 많음.
            // MSE 존재 여부와 무관하게 항상 인터셉터 설치 → AVPlayer로 재생.
            var mseAvail=(typeof window.MediaSource!=='undefined');
            log('MSE: '+mseAvail+' — always intercepting');

            var _sent={};
            function sendHLS(u){
                try{
                    if(!u) return;
                    u=String(u).trim();
                    if(u.indexOf('.m3u8')<0) return;
                    if(u.indexOf('://')<0){
                        if(u.indexOf('//')<0) return;
                        u='https:'+u;
                    }
                    if(_sent[u]) return;
                    _sent[u]=1;
                    log('FOUND '+u.substring(0,120));
                    var h=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.hlsPlay;
                    if(h) h.postMessage(u);
                }catch(e){}
            }

            // .m3u8 포함 텍스트에서 URL 추출 (regex 대신 index search — Swift 이스케이프 불필요)
            function scanText(text){
                if(!text) return;
                var idx=text.indexOf('.m3u8');
                if(idx<0) return;
                while(idx>=0){
                    var s=idx,e=idx+5;
                    while(s>0){
                        var cc=text.charCodeAt(s-1);
                        if(cc<=32||cc===34||cc===39||cc===60||cc===62||cc===44) break;
                        s--;
                    }
                    while(e<text.length){
                        var cc=text.charCodeAt(e);
                        if(cc<=32||cc===34||cc===39||cc===60||cc===62||cc===44) break;
                        e++;
                    }
                    sendHLS(text.substring(s,e));
                    idx=text.indexOf('.m3u8',idx+1);
                }
            }

            // ① video.src setter
            try{
                var vd=Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype,'src');
                if(vd&&vd.set){
                    Object.defineProperty(HTMLMediaElement.prototype,'src',{
                        get:vd.get,configurable:true,
                        set:function(v){
                            log('video.src='+String(v||'').substring(0,80));
                            try{sendHLS(v);}catch(e){}
                            vd.set.call(this,v);
                        }
                    });
                }
            }catch(e){log('vsrc-err:'+e.message);}

            // ② XHR 전수 로깅 + 요청/응답 URL 스캔
            try{
                var ox=XMLHttpRequest.prototype.open,os=XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.open=function(m,u){
                    this._su=String(u||'');
                    log('XHR '+m+' '+this._su.substring(0,80));
                    // 요청 URL 자체에 .m3u8 포함 시 즉시 캡처 (응답 대기 불필요)
                    try{sendHLS(this._su);}catch(e){}
                    return ox.apply(this,arguments);
                };
                XMLHttpRequest.prototype.send=function(){
                    var self=this;
                    self.addEventListener('load',function(){
                        try{
                            var t=self.responseText||'';
                            log('XHR-resp '+self._su.substring(0,60)+' len='+t.length+(t.indexOf('.m3u8')>=0?' [HAS-M3U8]':''));
                            scanText(t);
                        }catch(e){log('XHR-resp-err:'+e.message);}
                    },false);
                    return os.apply(this,arguments);
                };
            }catch(e){log('xhr-err:'+e.message);}

            // ③ fetch 전수 로깅 + 요청/응답 URL 스캔
            try{
                var of=window.fetch;
                window.fetch=function(){
                    var fu=typeof arguments[0]==='string'?arguments[0]:
                           (arguments[0]&&arguments[0].url?arguments[0].url:'?');
                    log('fetch '+String(fu).substring(0,80));
                    // 요청 URL 자체에 .m3u8 포함 시 즉시 캡처
                    try{sendHLS(fu);}catch(e){};
                    var p=of.apply(this,arguments);
                    try{p&&p.then&&p.then(function(r){
                        try{r.clone().text().then(function(t){
                            if(!t) return;
                            log('fetch-resp '+String(fu).substring(0,50)+' len='+t.length+(t.indexOf('.m3u8')>=0?' [HAS-M3U8]':''));
                            scanText(t);
                        });}catch(e){}
                    });}catch(e){}
                    return p;
                };
            }catch(e){log('fetch-err:'+e.message);}
        })();
        """
    }

    private func videoAutoplayJS() -> String {
        return """
        (function(){
            var isTop=(window===window.top);

            // 비디오 기본 스타일 — 검정 배경만 부여, fullscreen 강제는 하지 않는다.
            // 이전엔 모든 video를 position:fixed로 화면 전체로 만들었으나, 이 경우
            // 광고/로딩 placeholder/추천 영상까지 모두 fullscreen이 되며 실제 본영상을
            // 가리거나 플레이어 레이아웃을 망가뜨려 로딩이 멈추는 문제가 있었음.
            // 플레이어가 자체 레이아웃을 그대로 사용하도록 두고, 우리는 자동재생만 담당.
            // 비디오에 별도 CSS 강제하지 않음 — 플레이어가 자체 스타일 사용

            function playVideo(v){
                if(!v) return;
                try{ v.playsInline=true; v.autoplay=true; }catch(e){}
                function tryPlay(muted){
                    try{ v.muted=muted; }catch(e){}
                    var p; try{ p=v.play(); }catch(e){
                        if(!muted) tryPlay(true);
                        return;
                    }
                    if(p&&p.then){
                        p.then(function(){
                            if(muted) setTimeout(function(){ try{if(!v.paused)v.muted=false;}catch(e){}},500);
                        }).catch(function(){
                            if(!muted) tryPlay(true);
                        });
                    } else {
                        if(muted) setTimeout(function(){ try{if(!v.paused)v.muted=false;}catch(e){}},500);
                    }
                }
                tryPlay(false);
            }

            function playAll(){
                document.querySelectorAll('video').forEach(function(v){
                    if(v.paused||v.readyState<3) playVideo(v);
                });
            }

            // 비디오 상태 진단 — 디버그 라벨에 항상 표시
            var diagEl=null;
            function showVideoDiag(){
                if(!diagEl){
                    diagEl=document.createElement('div');
                    diagEl.style.cssText='position:fixed!important;top:50%!important;right:20px!important;'+
                        'transform:translateY(-50%)!important;'+
                        'background:rgba(0,0,0,0.92)!important;color:#0ff!important;padding:12px!important;'+
                        'font:14px monospace!important;min-width:380px!important;max-width:500px!important;'+
                        'z-index:2147483647!important;pointer-events:none!important;'+
                        'border:2px solid #0ff!important;border-radius:6px!important;white-space:pre-wrap!important';
                    (document.body||document.documentElement).appendChild(diagEl);
                }
                var lines=[];
                var videos=document.querySelectorAll('video');
                lines.push('Videos: '+videos.length);
                videos.forEach(function(v,i){
                    var rs=['NOTHING','META','CURRENT','FUTURE','ENOUGH'][v.readyState]||v.readyState;
                    var ns=['EMPTY','IDLE','LOADING','NO_SRC'][v.networkState]||v.networkState;
                    var err=v.error?('ERR'+v.error.code):'-';
                    var src=(v.currentSrc||v.src||'').substring(0,60);
                    lines.push('V'+i+' rs='+rs+' ns='+ns+' p='+(v.paused?'Y':'N')+' err='+err);
                    if(src) lines.push('   src='+src);
                });
                var ifrs=document.querySelectorAll('iframe');
                if(ifrs.length){
                    lines.push('iframes: '+ifrs.length);
                    ifrs.forEach(function(f,i){
                        lines.push(' i'+i+' '+(f.src||'').substring(0,70));
                    });
                }
                diagEl.textContent=lines.join('\\n');
            }
            // 0.5초마다 진단 갱신 (30초간)
            var diagTicks=0;
            (function diagLoop(){
                try{ showVideoDiag(); }catch(e){}
                diagTicks++;
                if(diagTicks<60) setTimeout(diagLoop,500);
            })();

            // canplay/canplaythrough/loadeddata 세 이벤트 모두 처리 — 플레이어 구현에 따라
            // canplay만 오거나 loadeddata만 오는 경우가 있음
            ['canplay','canplaythrough','loadeddata'].forEach(function(evtName){
                document.addEventListener(evtName,function(e){
                    var v=e.target;
                    if(v&&v.tagName==='VIDEO'&&v.paused&&!v.ended) playVideo(v);
                },true);
            });

            // 한 번도 재생되지 않은 비디오만 재시도 (currentTime===0이고 src가 있는 경우)
            // 이전엔 모든 pause를 재시도해 플레이어와 충돌하는 문제가 있었음
            document.addEventListener('pause',function(e){
                var v=e.target;
                if(v&&v.tagName==='VIDEO'&&!v.ended&&v.currentTime===0&&v.currentSrc){
                    setTimeout(function(){
                        if(v.paused&&!v.ended&&v.currentTime===0) playVideo(v);
                    },800);
                }
            },true);

            // 광고 종료 시 본영상 트리거를 길게 재시도 (3초 → 15초까지).
            // 플레이어가 본영상 <video>를 새로 만들거나 src를 swap하는 데 시간이 걸릴 수 있음.
            document.addEventListener('ended',function(e){
                if(!(e.target&&e.target.tagName==='VIDEO')) return;
                [500,1500,3000,5000,8000,12000].forEach(function(delay){
                    setTimeout(function(){
                        document.querySelectorAll('video').forEach(function(v){
                            // currentSrc가 있어야 의미 있는 video — 빈 video는 건너뜀
                            if(v.paused&&!v.ended&&(v.currentSrc||v.src)){
                                playVideo(v);
                            }
                        });
                    },delay);
                });
            },true);

            // ★ video 요소의 src 변경만 정밀하게 감시.
            // 광고 → 본영상으로 같은 video 요소의 src가 바뀌는 경우(가장 흔한 패턴)를
            // 잡아낸다. 다른 속성(style/class)은 감시 안 함 — React 리렌더에 휩쓸리지 않게.
            function watchVideoSrc(v){
                if(!v||v._soopSrcWatched) return;
                v._soopSrcWatched=true;
                try{
                    var srcObs=new MutationObserver(function(){
                        if(v.paused&&!v.ended){
                            setTimeout(function(){
                                if(v.paused&&!v.ended) playVideo(v);
                            },300);
                        }
                    });
                    srcObs.observe(v,{attributes:true,attributeFilter:['src']});
                }catch(e){}
            }

            // ★ 광고 스킵 버튼 자동 클릭 (1회 한정)
            // 광고가 6초 이상 재생되면 스킵 가능 시점이라고 가정하고, 명확한 "skip"
            // 텍스트/클래스를 가진 버튼을 1회만 클릭한다. 이전엔 모든 "play/btn"
            // 클래스를 매 0.5초마다 클릭해 페이지가 마비됐었음 — 이번엔 한 번만 한다.
            var skipClicked=false;
            document.addEventListener('playing',function(e){
                if(skipClicked) return;
                if(!(e.target&&e.target.tagName==='VIDEO')) return;
                setTimeout(function(){
                    if(skipClicked) return;
                    var skip=null;
                    document.querySelectorAll('button,[role="button"],a').forEach(function(b){
                        if(skip) return;
                        var text=((b.textContent||'')+'').toLowerCase().trim();
                        var label=((b.getAttribute('aria-label')||'')+'').toLowerCase();
                        var cls=((b.className||'')+'').toString().toLowerCase();
                        var matchesSkip=
                            text.indexOf('스킵')!==-1 ||
                            text.indexOf('건너')!==-1 ||
                            text.indexOf('skip')!==-1 ||
                            label.indexOf('skip')!==-1 ||
                            cls.indexOf('skip')!==-1 ||
                            cls.indexOf('Skip')!==-1;
                        if(matchesSkip){
                            var r=b.getBoundingClientRect();
                            if(r.width>5&&r.height>5) skip=b;
                        }
                    });
                    if(skip){
                        skip.click();
                        skipClicked=true;
                    }
                },6500);  // 광고가 보통 5초 후 스킵 가능 → 6.5초 후 시도
            },true);

            // DOM에 새로 추가되는 <video> 요소만 감시 (subtree+childList).
            // 새 video가 추가되면 src 감시자도 부착.
            var obs=new MutationObserver(function(muts){
                for(var i=0;i<muts.length;i++){
                    var m=muts[i];
                    if(!m.addedNodes) continue;
                    for(var j=0;j<m.addedNodes.length;j++){
                        var n=m.addedNodes[j];
                        if(!n||n.nodeType!==1) continue;
                        if(n.tagName==='VIDEO'){
                            watchVideoSrc(n);
                            if(n.readyState>=3) playVideo(n);
                        } else if(n.querySelectorAll){
                            n.querySelectorAll('video').forEach(function(v){
                                watchVideoSrc(v);
                                if(v.readyState>=3) playVideo(v);
                            });
                        }
                    }
                }
            });
            obs.observe(document.documentElement,{childList:true,subtree:true});

            // 초기 video 요소에도 src 감시자 부착
            document.querySelectorAll('video').forEach(watchVideoSrc);

            // ─── Hls.isSupported 패치 ─────────────────────────────────────────
            // tvOS WKWebView에서 hls.js의 MSE 경로는 live stream 재생에 실패하는 경우가 많음.
            // MSE 존재 여부와 무관하게 Hls.isSupported()=false로 강제해 native HLS path 선택.
            // native path에서 video.src=m3u8_url 로 설정 → video.src setter가 URL 캡처 → AVPlayer.
            (function patchHls(){
                if(typeof window.Hls!=='undefined'){
                    if(!window.Hls._soopPatched){
                        window.Hls._soopPatched=true;
                        var origIsSupported=window.Hls.isSupported;
                        window.Hls.isSupported=function(){
                            // tvOS native HLS(video src=*.m3u8)가 지원되면 false 반환 → native path
                            var v=document.createElement('video');
                            var native=v.canPlayType&&(
                                v.canPlayType('application/vnd.apple.mpegurl')!==''||
                                v.canPlayType('application/x-mpegURL')!==''
                            );
                            return native?false:(origIsSupported?origIsSupported():false);
                        };
                    }
                } else {
                    setTimeout(patchHls,500);
                }
            })();
        })();
        """
    }

    // MARK: - 네비게이션 + 가상 키보드 JS (메인 프레임)

    private func navigationJS() -> String {
        return """
        (function(){
            var focusables=[],idx=0;

            // 포커스 표시는 메인 프레임에 떠 있는 "고정 위치 오버레이 div"로 그린다.
            // 이렇게 하는 이유 두 가지:
            //  (1) iframe 안의 요소에도 시각 표시가 가능 — 메인 프레임 좌표로 변환해 그려줌
            //  (2) 부모가 overflow:hidden 이어도 잘리지 않음 — 비디오 플레이어 내부
            //      컨트롤러처럼 잘리기 쉬운 자식 요소도 항상 보임
            var fs=document.createElement('style');
            fs.id='tvos-focus';
            fs.textContent=
                '@keyframes soopPulse{' +
                    '0%,100%{box-shadow:inset 0 0 0 6px #ffcc00,0 0 30px 10px rgba(255,204,0,0.55),0 0 0 1px rgba(0,0,0,0.5)}' +
                    '50%{box-shadow:inset 0 0 0 6px #ffcc00,0 0 55px 16px rgba(255,204,0,0.85),0 0 0 1px rgba(0,0,0,0.5)}' +
                '}' +
                '#soop-focus-overlay{' +
                    'position:fixed!important;pointer-events:none!important;' +
                    'box-sizing:border-box!important;border-radius:10px!important;' +
                    'z-index:2147483646!important;display:none;' +
                    'transition:left .15s ease-out,top .15s ease-out,width .15s ease-out,height .15s ease-out!important;' +
                    'animation:soopPulse 1.4s ease-in-out infinite!important;' +
                '}' +
                '#soop-focus-badge{' +
                    'position:absolute!important;top:-14px!important;right:8px!important;' +
                    'background:#ffcc00!important;color:#000!important;' +
                    'padding:4px 12px!important;border-radius:4px!important;' +
                    'font:700 13px -apple-system,sans-serif!important;' +
                    'box-shadow:0 2px 8px rgba(0,0,0,0.6)!important;' +
                    'white-space:nowrap!important;' +
                '}';
            (document.head||document.documentElement).appendChild(fs);

            // 오버레이 div (포커스된 요소 위에 노란 테두리 + 배지)
            var overlay=document.createElement('div');
            overlay.id='soop-focus-overlay';
            var badge=document.createElement('div');
            badge.id='soop-focus-badge';
            badge.textContent='▶ 선택됨';
            overlay.appendChild(badge);
            (document.body||document.documentElement).appendChild(overlay);

            // 화면 좌하단 HUD: 현재 위치 / 전체 수 표시
            var hud=document.createElement('div');
            hud.id='soop-hud';
            hud.style.cssText='position:fixed!important;left:20px!important;bottom:20px!important;' +
                'background:rgba(0,0,0,0.75)!important;color:#ffcc00!important;' +
                'padding:8px 14px!important;border-radius:6px!important;' +
                'font:600 14px -apple-system,sans-serif!important;' +
                'z-index:2147483647!important;pointer-events:none!important;' +
                'border:1px solid rgba(255,204,0,0.4)!important;display:none;';
            (document.body||document.documentElement).appendChild(hud);

            function updateHud(){
                if(!focusables.length){ hud.style.display='none'; return; }
                hud.textContent='● ' + (idx+1) + ' / ' + focusables.length;
                hud.style.display='block';
            }

            // 포커스된 요소의 위치를 계산해 오버레이를 그 위에 배치
            function positionOverlay(){
                if(idx<0||idx>=focusables.length){ overlay.style.display='none'; return; }
                var f=focusables[idx],rect;
                try{ rect=f.el.getBoundingClientRect(); }catch(e){ overlay.style.display='none'; return; }
                if(!rect||rect.width<1||rect.height<1){ overlay.style.display='none'; return; }
                var ox=f.offsetX||0, oy=f.offsetY||0;
                overlay.style.display='block';
                overlay.style.left=(ox+rect.left-4)+'px';
                overlay.style.top=(oy+rect.top-4)+'px';
                overlay.style.width=(rect.width+8)+'px';
                overlay.style.height=(rect.height+8)+'px';
            }

            var FOCUS_SELS='a[href],button,[role="button"],input,select,textarea,[onclick],video,' +
                'div[class*="card"],div[class*="item"],div[class*="thumbnail"],' +
                'div[class*="channel"],div[class*="stream"],div[class*="live"],' +
                'div[class*="banner"],div[class*="recommend"],' +
                'li[class*="item"],article,img[class*="thumb"],span[class*="thumb"],' +
                /* 영상 플레이어 컨트롤러만 (wrapper는 잘못된 클릭 트리거함) */
                '[class*="control"] [class*="btn"],[class*="control"] button,' +
                '[class*="player"] button,[class*="Player"] button,' +
                '[class*="play-btn"],[class*="playBtn"],[class*="play_btn"],' +
                '[aria-label],[data-role="button"]';

            // 같은-오리진 iframe까지 재귀 탐색하면서 모든 포커스 가능 요소를 모은다.
            // 각 요소의 좌표는 iframe 누적 오프셋을 더해 메인 프레임 좌표계로 변환한다.
            function collectFromDoc(doc,offsetX,offsetY,all){
                try{
                    doc.querySelectorAll(FOCUS_SELS).forEach(function(el){
                        try{
                            var r=el.getBoundingClientRect();
                            if(r.width>10&&r.height>10){
                                all.push({
                                    el:el,
                                    offsetX:offsetX,
                                    offsetY:offsetY,
                                    cx:offsetX+r.left+r.width/2,
                                    cy:offsetY+r.top+r.height/2
                                });
                            }
                        }catch(e){}
                    });
                    doc.querySelectorAll('iframe').forEach(function(iframe){
                        try{
                            var idoc=iframe.contentDocument||iframe.contentWindow.document;
                            if(idoc){
                                var fr=iframe.getBoundingClientRect();
                                collectFromDoc(idoc,offsetX+fr.left,offsetY+fr.top,all);
                            }
                        }catch(e){/* 크로스-오리진은 접근 불가, 건너뜀 */}
                    });
                }catch(e){}
            }

            function collect(){
                var all=[];
                collectFromDoc(document,0,0,all);
                all.sort(function(a,b){
                    if(Math.abs(a.cy-b.cy)<50) return a.cx-b.cx;
                    return a.cy-b.cy;
                });
                focusables=all;
                if(idx>=focusables.length) idx=0;
            }

            // 사용자가 _nav 한 경우(scroll=true)만 스크롤. 위치는 항상 다시 계산.
            function highlight(i,scroll){
                if(i<0||i>=focusables.length){ overlay.style.display='none'; updateHud(); return; }
                var el=focusables[i].el;
                if(scroll){
                    try{ el.scrollIntoView({block:'center',inline:'center',behavior:'smooth'}); }
                    catch(e){ try{ el.scrollIntoView(); }catch(_){} }
                    // 부드러운 스크롤이 끝난 뒤 위치 재계산
                    setTimeout(positionOverlay,400);
                }
                positionOverlay();
                updateHud();
            }

            // 페이지/iframe 스크롤·리사이즈 시 오버레이 위치 동기화
            window.addEventListener('scroll',positionOverlay,true);
            window.addEventListener('resize',positionOverlay);

            window._nav=function(dir){
                // 매번 fresh collect — Naver 등 외부 페이지가 input을 JS로 늦게 렌더하는
                // 경우에도 input이 focusables에 반영되도록 한다. 사용자 입력 시점에만
                // 실행되므로 React 자동 갱신 폭주 문제는 없음.
                var prevEl=focusables[idx]?focusables[idx].el:null;
                collect();
                if(!focusables.length) return;
                // 이전에 포커스됐던 요소가 새 focusables에도 있으면 그 위치 유지
                if(prevEl){
                    for(var i=0;i<focusables.length;i++){
                        if(focusables[i].el===prevEl){ idx=i; break; }
                    }
                }
                var cur=focusables[idx],bestIdx=idx,bestDist=Infinity;
                for(var i=0;i<focusables.length;i++){
                    if(i===idx) continue;
                    var t=focusables[i],dx=t.cx-cur.cx,dy=t.cy-cur.cy;
                    var dist=Math.sqrt(dx*dx+dy*dy);
                    if(dist>2000) continue;
                    var ok=false;
                    if(dir==='up')    ok=dy<-10&&Math.abs(dy)>Math.abs(dx)*0.3;
                    if(dir==='down')  ok=dy>10 &&Math.abs(dy)>Math.abs(dx)*0.3;
                    if(dir==='left')  ok=dx<-10&&Math.abs(dx)>Math.abs(dy)*0.3;
                    if(dir==='right') ok=dx>10 &&Math.abs(dx)>Math.abs(dy)*0.3;
                    if(ok&&dist<bestDist){bestDist=dist;bestIdx=i;}
                }
                if(bestIdx===idx){
                    if(dir==='up'&&idx>0) bestIdx=idx-1;
                    else if(dir==='down'&&idx<focusables.length-1) bestIdx=idx+1;
                }
                idx=bestIdx;
                highlight(idx,true);
            };

            function postKeyboard(el){
                if(!window.webkit||!window.webkit.messageHandlers||!window.webkit.messageHandlers.keyboard) return;
                var tag=el.tagName||'';
                var inputType=(el.getAttribute('type')||'text').toLowerCase();
                var skip=['hidden','submit','button','checkbox','radio','file','image','reset'];
                if(tag==='INPUT'&&skip.indexOf(inputType)!==-1) return;
                if(tag!=='INPUT'&&tag!=='TEXTAREA'&&!el.isContentEditable) return;
                window.webkit.messageHandlers.keyboard.postMessage({
                    tag:tag,
                    value:el.value||el.textContent||'',
                    placeholder:el.getAttribute('placeholder')||'',
                    isPassword:inputType==='password'
                });
            }

            // document_start에서 monkey-patch한 _soopHandlers에 저장된 핸들러를 직접 호출.
            // originalTarget: 사용자가 실제로 클릭한 요소 (event.target에 사용).
            // el: 핸들러가 부착된 요소 (event.currentTarget이자 this).
            // 이 구분이 중요한 이유: SOOP은 BODY에 click 위임을 쓰는데,
            // 위임 핸들러는 e.target을 보고 어느 자식을 클릭했는지 판단함.
            function callTrackedHandlers(el,originalTarget){
                if(!el||!el._soopHandlers) return false;
                var target=originalTarget||el;
                // 좌표는 클릭된 요소 중앙으로 계산
                var cx=0,cy=0;
                try{
                    var r=target.getBoundingClientRect();
                    cx=r.left+r.width/2; cy=r.top+r.height/2;
                }catch(e){}
                var fired=false;
                var event={
                    preventDefault:function(){this.defaultPrevented=true;},
                    stopPropagation:function(){},
                    stopImmediatePropagation:function(){},
                    isDefaultPrevented:function(){return !!this.defaultPrevented;},
                    isPropagationStopped:function(){return false;},
                    defaultPrevented:false,
                    target:target,           // 원래 클릭된 요소
                    currentTarget:el,        // 핸들러가 붙은 요소
                    srcElement:target,
                    type:'click',bubbles:true,cancelable:true,
                    isTrusted:true,
                    button:0,buttons:1,
                    clientX:cx,clientY:cy,pageX:cx,pageY:cy,screenX:cx,screenY:cy,
                    offsetX:cx,offsetY:cy,
                    altKey:false,ctrlKey:false,shiftKey:false,metaKey:false,
                    detail:1,view:window,which:1,
                    relatedTarget:null
                };
                ['mousedown','mouseup','click'].forEach(function(type){
                    var hs=el._soopHandlers[type];
                    if(hs&&hs.length){
                        event.type=type;
                        hs.slice().forEach(function(h,i){
                            // 핸들러 소스 처음 100자 — 어떤 처리하는지 힌트
                            var src=(h.toString&&h.toString()||'').replace(/\\s+/g,' ').substring(0,120);
                            postDebug('  '+type+'#'+i+' src='+src);
                            try{
                                var result=h.call(el,event);
                                fired=true;
                                postDebug('  -> returned='+(result===undefined?'undef':String(result).substring(0,40)));
                            }catch(e){
                                postDebug('  -> ERROR: '+(e.message||e));
                            }
                        });
                    }
                });
                return fired;
            }

            // React 합성 이벤트 핸들러를 찾아 직접 호출.
            function callReactHandler(el){
                if(!el) return false;
                try{
                    var keys=Object.keys(el);
                    for(var i=0;i<keys.length;i++){
                        var k=keys[i];
                        if(k.indexOf('__reactProps')===0||k.indexOf('__reactEventHandlers')===0){
                            var props=el[k];
                            if(props&&typeof props.onClick==='function'){
                                var fakeEvent={
                                    preventDefault:function(){},
                                    stopPropagation:function(){},
                                    isDefaultPrevented:function(){return false;},
                                    isPropagationStopped:function(){return false;},
                                    persist:function(){},
                                    target:el,currentTarget:el,
                                    type:'click',bubbles:true,cancelable:true,
                                    nativeEvent:{type:'click',target:el,currentTarget:el,isTrusted:true}
                                };
                                try{ props.onClick(fakeEvent); return true; }catch(e){}
                            }
                        }
                    }
                }catch(e){}
                return false;
            }

            // 실제 mouse 이벤트 sequence를 디스패치.
            function dispatchRealClick(el){
                if(!el) return;
                try{
                    var r=el.getBoundingClientRect();
                    var x=r.left+r.width/2, y=r.top+r.height/2;
                    ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(type){
                        var EventCtor=(type.indexOf('pointer')===0?window.PointerEvent:window.MouseEvent);
                        if(!EventCtor) EventCtor=window.MouseEvent;
                        var evt;
                        try{
                            evt=new EventCtor(type,{
                                bubbles:true,cancelable:true,view:window,button:0,
                                clientX:x,clientY:y
                            });
                        }catch(e){
                            evt=document.createEvent('MouseEvents');
                            evt.initMouseEvent(type,true,true,window,1,x,y,x,y,false,false,false,false,0,null);
                        }
                        el.dispatchEvent(evt);
                    });
                }catch(e){
                    try{ el.click(); }catch(_){}
                }
            }

            // 화면에 보이는 디버그 로그 오버레이 — 좌측 큰 박스로 에러까지 표시
            var debugLogEl=null;
            function ensureDebugLog(){
                if(debugLogEl) return debugLogEl;
                debugLogEl=document.createElement('div');
                debugLogEl.id='soop-debug-log';
                debugLogEl.style.cssText='position:fixed!important;top:80px!important;left:10px!important;'+
                    'width:520px!important;max-height:380px!important;overflow:hidden!important;'+
                    'background:rgba(0,0,0,0.92)!important;color:#0f0!important;padding:8px!important;'+
                    'font:11px monospace!important;'+
                    'z-index:2147483647!important;pointer-events:none!important;border:1px solid #0f0!important;white-space:pre-wrap!important';
                (document.body||document.documentElement).appendChild(debugLogEl);
                // 환경 정보 표시
                var info='UA: '+navigator.userAgent.substring(0,80)+'\\n'+
                    'MediaSource: '+(typeof window.MediaSource!=='undefined')+'\\n'+
                    'WebKitMediaSource: '+(typeof window.WebKitMediaSource!=='undefined')+'\\n'+
                    'EME: '+(typeof navigator.requestMediaKeySystemAccess==='function')+'\\n'+
                    'WebRTC: '+(typeof window.RTCPeerConnection==='function');
                debugLogEl.textContent=info;
                return debugLogEl;
            }
            function postDebug(msg){
                try{
                    var s=(typeof msg==='string')?msg:JSON.stringify(msg);
                    var el=ensureDebugLog();
                    el.textContent=(el.textContent+'\\n'+s).split('\\n').slice(-20).join('\\n');
                    if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.debug){
                        window.webkit.messageHandlers.debug.postMessage(s);
                    }
                }catch(e){}
            }

            // window.open을 가로채서 호출 여부와 URL을 native에 알림
            (function(){
                var origOpen=window.open;
                window.open=function(url,name,features){
                    postDebug('window.open called url='+url+' name='+name);
                    return origOpen?origOpen.apply(window,arguments):null;
                };
            })();

            window._click=function(){
                // 클릭 시점에도 최신 focusables 보장 (선택은 유지)
                if(focusables.length){
                    var prev=focusables[idx]?focusables[idx].el:null;
                    collect();
                    if(prev){
                        for(var i=0;i<focusables.length;i++){
                            if(focusables[i].el===prev){ idx=i; break; }
                        }
                    }
                }
                if(!focusables.length||!focusables[idx]) return;
                var el=focusables[idx].el;
                var tag=el.tagName||'';
                var inputType=(el.getAttribute('type')||'').toLowerCase();
                var textTypes=['text','search','email','url','tel','number','','password'];
                var isText=(tag==='INPUT'&&textTypes.indexOf(inputType)!==-1)||
                            tag==='TEXTAREA'||el.isContentEditable;

                // wrapper DIV/SPAN 안에 input이 있는 경우 그것을 사용
                // 예: Naver는 <div class="input_item_id_focus"><input ...></div> 구조라
                // 포커스 가능 요소가 div가 되어 input으로 인식 안 됐었음
                if(!isText && el.querySelector){
                    var innerInput=el.querySelector('input[type="text"],input[type="password"],'+
                        'input[type="email"],input[type="url"],input[type="search"],'+
                        'input[type="tel"],input[type="number"],input:not([type]),textarea,'+
                        '[contenteditable="true"]');
                    if(innerInput){
                        postDebug('-> inner input found: '+innerInput.tagName+' type='+innerInput.type);
                        el=innerInput;
                        isText=true;
                    }
                }

                if(isText){
                    el.focus();
                    window._soopActiveInput=el;
                    postKeyboard(el);
                    return;
                }

                // video 요소 직접 선택 시 .play() 호출
                if(tag==='VIDEO'){
                    postDebug('-> VIDEO direct play');
                    var v=el;
                    var vp; try{ vp=v.play(); }catch(e){}
                    if(vp&&vp.then) vp.catch(function(){
                        try{ v.muted=true; v.play().catch(function(){}); }catch(e){}
                    });
                    return;
                }

                // 클릭 가능 조상 찾기 — 포커스된 게 <img>나 <span>이라도 부모 <a>/<button> 트리거
                var clickable=el;
                try{
                    var anc=el.closest('a[href],button,[role="button"],[onclick]');
                    if(anc) clickable=anc;
                }catch(e){}

                postDebug('=== CLICK ===');
                postDebug('target='+el.tagName+'.'+(el.className||'').toString().substring(0,40));
                postDebug('clickable='+clickable.tagName+'.'+(clickable.className||'').toString().substring(0,60));
                postDebug('href='+(clickable.getAttribute&&clickable.getAttribute('href')));
                // 모든 own property keys 출력 — react/vue 등 framework 시그니처 찾기
                var allKeys=Object.keys(clickable).filter(function(k){return k.charAt(0)==='_'||k.indexOf('$')>=0;});
                postDebug('special-keys='+allKeys.join(','));

                // 1순위: 진짜 href를 가진 <a>면 .click()
                if(clickable.tagName==='A'){
                    var rawHref=clickable.getAttribute('href');
                    if(rawHref&&rawHref!=='#'&&rawHref.indexOf('javascript')!==0){
                        postDebug('-> A.click() with real href');
                        clickable.click();
                        return;
                    }
                }

                // 2순위: 추적된 addEventListener 핸들러 — clickable/el/얕은 부모(2단계까지)만.
                // BODY/document 같은 먼 ancestor는 generic 분석/스크롤 핸들러일 가능성이 높고
                // 진짜 위임 핸들러는 합성 이벤트 bubble을 통해 자연스럽게 받는 게 더 안정적.
                var firedAny=false;
                if(callTrackedHandlers(clickable,clickable)){ postDebug('-> tracked handlers on clickable'); firedAny=true; }
                else if(clickable!==el && callTrackedHandlers(el,clickable)){ postDebug('-> tracked handlers on el'); firedAny=true; }
                else {
                    // 즉시 부모와 그 부모까지만 시도 (얕은 위임만)
                    var p=clickable.parentElement;
                    var depth=0;
                    while(p&&depth<2){
                        if(callTrackedHandlers(p,clickable)){
                            postDebug('-> tracked handlers on parent depth='+depth+' '+p.tagName);
                            firedAny=true;
                            break;
                        }
                        p=p.parentElement; depth++;
                    }
                }

                // 2-c: React 핸들러도 시도
                if(!firedAny && callReactHandler(clickable)){
                    postDebug('-> React onClick on clickable');
                    firedAny=true;
                }

                // ★ 항상 dispatchRealClick + clickable.click() — body 위임 등 깊은 핸들러가
                // 합성 이벤트 bubble로 자연스럽게 받게 한다. 첫 Naver 성공 사례가 이 경로.
                postDebug('-> dispatchRealClick + click()');
                dispatchRealClick(clickable);
                try{ clickable.click(); }catch(e){}

                // 3순위: 자식 <a>
                var a=clickable.querySelector?clickable.querySelector('a[href]'):null;
                if(a&&a.href&&a.getAttribute('href')!=='#'){
                    postDebug('-> child A.click()');
                    a.click();
                    return;
                }

                // 4순위: mouse event sequence 디스패치 + 표준 .click()
                postDebug('-> dispatchRealClick fallback');
                dispatchRealClick(clickable);
                try{ clickable.click(); }catch(e){}

                // 추가 시도: 모든 자식 요소에도 dispatch (핸들러가 <img> 등 자식에 붙어있을 경우)
                try{
                    var children=clickable.querySelectorAll('*');
                    for(var i=0;i<children.length&&i<5;i++){
                        dispatchRealClick(children[i]);
                        try{ children[i].click(); }catch(e){}
                    }
                    postDebug('-> also dispatched on '+Math.min(5,children.length)+' children');
                }catch(e){}

                // 클릭 후 정지된 비디오 직접 재생 시도
                // 플레이 버튼 클릭이 스트림 로딩을 시작했지만 play()가 별도로 필요한 경우 대비
                setTimeout(function(){
                    document.querySelectorAll('video').forEach(function(v){
                        if(v.paused&&!v.ended&&v.currentSrc&&v.readyState>=2){
                            postDebug('-> post-click play: '+v.currentSrc.substring(0,60));
                            var p; try{ p=v.play(); }catch(e){}
                            if(p&&p.then) p.catch(function(){
                                try{ v.muted=true; v.play().catch(function(){}); }catch(e){}
                            });
                        }
                    });
                },600);
            };

            window._back=function(){window.history.back();};

            window._setInputValue=function(value){
                postDebug('=== setInputValue("'+value.substring(0,15)+'") ===');
                var activeEl=document.activeElement;
                postDebug('activeEl: '+(activeEl?activeEl.tagName+'#'+activeEl.id+'/'+activeEl.name:'null')+
                    (activeEl===document.body?' [BODY]':''));
                postDebug('_soopActive: '+(window._soopActiveInput?
                    window._soopActiveInput.tagName+'#'+window._soopActiveInput.id+'/'+window._soopActiveInput.name:'null'));

                var el=activeEl;
                if(!el||el===document.body||el===document.documentElement){
                    el=window._soopActiveInput||null;
                    postDebug('fallback to _soopActiveInput');
                }
                window._soopActiveInput=null;
                // iframe 안에 포커스된 입력창이 있으면 거기까지 내려간다
                while(el&&el.contentDocument){
                    try{
                        var inner=el.contentDocument.activeElement;
                        if(!inner||inner===el.contentDocument.body) break;
                        el=inner;
                    }catch(e){ break; }
                }
                if(!el){ postDebug('no element found — abort'); return; }
                postDebug('target: '+el.tagName+'#'+el.id+'/'+el.name+' type='+el.type);
                try{ el.focus(); }catch(e){}
                if(el.tagName==='INPUT'||el.tagName==='TEXTAREA'){
                    var desc=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value');
                    var setter=desc&&desc.set;
                    // 먼저 값을 비운다 (floating label이 초기화되도록)
                    if(setter) setter.call(el,''); else el.value='';
                    el.dispatchEvent(new Event('input',{bubbles:true}));
                    // 한 글자씩 keydown→input→keyup 순서로 주입
                    // SOOP 로그인 폼이 keyup 기반 floating label을 사용하므로
                    // 실제 키보드 입력과 동일한 이벤트 시퀀스가 필요
                    for(var i=0;i<value.length;i++){
                        var ch=value[i];
                        var code=ch.charCodeAt(0);
                        var kOpts={key:ch,charCode:code,keyCode:code,which:code,bubbles:true,cancelable:true};
                        try{ el.dispatchEvent(new KeyboardEvent('keydown',kOpts)); }catch(e){}
                        try{ el.dispatchEvent(new KeyboardEvent('keypress',kOpts)); }catch(e){}
                        if(setter) setter.call(el,el.value+ch); else el.value=el.value+ch;
                        el.dispatchEvent(new Event('input',{bubbles:true}));
                        try{ el.dispatchEvent(new KeyboardEvent('keyup',kOpts)); }catch(e){}
                    }
                    el.dispatchEvent(new Event('change',{bubbles:true}));
                    postDebug('typed '+value.length+' chars, el.value="'+el.value.substring(0,20)+'"');
                } else if(el.isContentEditable){
                    el.textContent=value;
                    el.dispatchEvent(new Event('input',{bubbles:true}));
                    postDebug('contenteditable set');
                } else {
                    postDebug('unknown element type — cannot set value');
                }
                // blur는 하지 않는다 — SOOP 폼이 blur 시 값을 초기화할 수 있음
            };

            // focusin으로 자동 키보드를 띄우지 않는다.
            // 이전엔 SOOP 로그인 페이지가 ID 입력창에 자동 포커스할 때 우리 다이얼로그가
            // 떠서 LoginManager의 자동 자격증명 입력을 방해했음.
            // 이제 가상 키보드는 사용자가 리모컨으로 명시적으로 _click 한 경우만 표시됨.

            // 초기 1회만 수집·하이라이트.
            // 자동 refresh(타이머·MutationObserver)는 모두 제거 — 페이지가 자체적으로
            // 자주 갱신될 때 화면이 떨리거나 선택이 깜빡이는 현상을 차단한다.
            // 이후 갱신은 사용자가 방향키를 눌렀을 때 _nav 내부에서만 일어난다.
            collect();
            highlight(idx,false);
        })();
        """
    }

    // MARK: - 가상 키보드 (WKScriptMessageHandler)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "debug" {
            print("[WebDebug] \(message.body)")
            return
        }
        if message.name == "hlsPlay" {
            if let urlStr = message.body as? String, let url = URL(string: urlStr) {
                print("[HLS] Received URL: \(urlStr)")
                DispatchQueue.main.async { [weak self] in self?.presentAVPlayer(url: url) }
            }
            return
        }
        guard message.name == "keyboard",
              let body = message.body as? [String: Any] else { return }
        let value = body["value"] as? String ?? ""
        let placeholder = body["placeholder"] as? String ?? ""
        let isPassword = body["isPassword"] as? Bool ?? false
        DispatchQueue.main.async { [weak self] in
            self?.showKeyboard(currentValue: value, placeholder: placeholder, isPassword: isPassword)
        }
    }

    private func showKeyboard(currentValue: String, placeholder: String, isPassword: Bool) {
        let vc = VirtualKeyboardViewController(
            initialText: currentValue,
            placeholder: placeholder,
            isSecure: isPassword
        )
        vc.modalPresentationStyle = .overFullScreen
        vc.onConfirm = { [weak self] text in
            print("[Keyboard] onConfirm text='\(text)' len=\(text.count)")
            let safe = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
            self?.webView.evaluateJavaScript("window._setInputValue('\(safe)')", completionHandler: { _, err in
                if let err = err { print("[Keyboard] _setInputValue JS error: \(err)") }
            })
            self?.restoreFocus()
        }
        vc.onCancel = { [weak self] in
            self?.webView.evaluateJavaScript(
                "if(document.activeElement)document.activeElement.blur()", completionHandler: nil)
            self?.restoreFocus()
        }
        releaseFocusForModal()
        present(vc, animated: true)
    }

    private var inputHintLabel: UILabel?

    private func showInputHint() {
        if inputHintLabel == nil {
            let label = UILabel()
            label.text = "⌨️ 키보드로 입력 — 완료 후 Menu(ESC) 키"
            label.textColor = .black
            label.backgroundColor = UIColor(red: 1, green: 0.8, blue: 0, alpha: 0.95)
            label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            label.textAlignment = .center
            label.layer.cornerRadius = 8
            label.layer.masksToBounds = true
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -30),
                label.widthAnchor.constraint(equalToConstant: 480),
                label.heightAnchor.constraint(equalToConstant: 44),
            ])
            inputHintLabel = label
        }
        inputHintLabel?.isHidden = false
    }

    private func hideInputHint() {
        inputHintLabel?.isHidden = true
    }

    // MARK: - AVPlayer (HLS 네이티브 재생)

    private weak var avPlayerVC: AVPlayerViewController?

    private func presentAVPlayer(url: URL) {
        guard avPlayerVC == nil else { return }
        print("[AVPlayer] playing: \(url)")
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        vc.modalPresentationStyle = .fullScreen
        releaseFocusForModal()
        present(vc, animated: true) { player.play() }
        avPlayerVC = vc
    }

    // MARK: - HLS URL 탐색 (Swift에서 evaluateJavaScript로 직접 검색)

    private var hlsSearchAttempts = 0

    private func startHLSSearch() {
        hlsSearchAttempts = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.tryHLSSearch()
        }
    }

    private func tryHLSSearch() {
        guard let currentURL = webView.url?.absoluteString,
              currentURL.contains("sooplive.com") || currentURL.contains("afreeca.tv") else { return }
        guard hlsSearchAttempts < 12, avPlayerVC == nil else { return }
        hlsSearchAttempts += 1
        print("[HLSSearch] attempt \(hlsSearchAttempts)")

        let js = """
        (function(){
            function grab(text){
                if(!text) return null;
                var i=text.indexOf('.m3u8');
                if(i<0) return null;
                var s=i,e=i+5;
                while(s>0){var c=text.charCodeAt(s-1);if(c<=32||c===34||c===39||c===44||c===92)break;s--;}
                while(e<text.length){var c=text.charCodeAt(e);if(c<=32||c===34||c===39||c===44||c===92)break;e++;}
                var u=text.substring(s,e);
                return (u.indexOf('http')>=0||u.substring(0,2)==='//') ? u : null;
            }
            var r=null;
            // 1. __NEXT_DATA__ (Next.js SSR)
            try{var nd=document.getElementById('__NEXT_DATA__');if(nd){r=grab(nd.textContent);}}catch(e){}
            // 2. inline <script> 태그
            if(!r){try{var sc=document.querySelectorAll('script:not([src])');for(var i=0;i<sc.length&&!r;i++)r=grab(sc[i].textContent);}catch(e){}}
            // 3. window 전역 변수 스캔 (대문자로 시작하거나 _ $ 로 시작하는 것만)
            if(!r){try{Object.getOwnPropertyNames(window).forEach(function(k){
                if(r) return;
                var f=k.charAt(0);
                if(f!=='_'&&f!=='$'&&!/[A-Z]/.test(f)) return;
                try{
                    var v=window[k];
                    if(typeof v==='string'&&v.indexOf('.m3u8')>=0){r=grab(v);return;}
                    if(v&&typeof v==='object'){var s=JSON.stringify(v);if(s&&s.length<80000&&s.indexOf('.m3u8')>=0){r=grab(s);}}
                }catch(e){}
            });}catch(e){}}
            return r;
        })()
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            if let u = result as? String, !u.isEmpty {
                var urlStr = u
                if urlStr.hasPrefix("//") { urlStr = "https:" + urlStr }
                print("[HLSSearch] FOUND: \(urlStr)")
                if let url = URL(string: urlStr) {
                    DispatchQueue.main.async { self.presentAVPlayer(url: url) }
                    return
                }
            }
            // 못 찾으면 2초 후 재시도
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.tryHLSSearch()
            }
        }
    }

    private func restoreFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // modal이 떠있는 동안은 PressInterceptor focus를 복구하지 않음
            guard self.presentedViewController == nil else { return }
            // PressInterceptor가 뷰에서 제거됐다면 다시 추가
            if self.pressInterceptor.superview == nil {
                self.pressInterceptor.frame = self.view.bounds
                self.pressInterceptor.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.view.addSubview(self.pressInterceptor)
            }
            self.pressInterceptor.allowFocus = true
            self.setNeedsFocusUpdate()
            self.updateFocusIfNeeded()
            self.pressInterceptor.becomeFirstResponder()
        }
    }

    /// UIAlertController 같은 modal을 띄우기 직전에 호출 — PressInterceptor가
    /// focus를 양보해서 alert의 버튼/키보드가 focus를 받을 수 있게 한다.
    /// 더 강력한 격리를 위해 뷰 계층에서 아예 제거 (responder 체인 완전 배제).
    private func releaseFocusForModal() {
        pressInterceptor.allowFocus = false
        pressInterceptor.resignFirstResponder()
        pressInterceptor.removeFromSuperview()
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    // MARK: - 자격증명 로드

    private func loadCredentialsAndStart() {
        // 자격증명이 있어도 자동 로그인은 시도하지 않음 — 사용자가 로그인 페이지에서
        // 리모컨/가상 키보드로 수동 로그인. 쿠키는 세션 간 유지되므로 한 번 로그인하면
        // 다음 실행부터는 로그인 상태 유지.
        if let creds = LoginManager.loadCredentials() {
            loginManager = LoginManager(id: creds.id, password: creds.password, webViewProvider: self)
        }
        // 자동 로그인을 비활성화 (auto-fill을 건너뜀)
        autoLoginAttempted = true

        let url = URL(string: "https://www.sooplive.com/")!
        webView.load(URLRequest(url: url))
    }

    // MARK: - LoginManager.WebViewProviding
    func loadURL(_ url: URL) { webView.load(URLRequest(url: url)) }
    func evaluateJavaScript(_ js: String, completion: ((Any?, Error?) -> Void)?) {
        webView.evaluateJavaScript(js, completionHandler: completion)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateURLBar("START")
        print("[Nav] START: \(webView.url?.absoluteString ?? "")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateURLBar("DONE")
        let urlStr = webView.url?.absoluteString ?? ""
        print("[Nav] DONE: \(urlStr)")

        // ★ 빈/blank 페이지 감지 — Naver OAuth 콜백 후 window.close()가 호출되면
        // WKWebView가 about:blank로 가거나 빈 페이지가 남는 경우가 있음.
        // 그때 자동으로 SOOP 홈으로 복귀해 사용자가 검정 화면에 갇히지 않게 함.
        let isBlank = urlStr.isEmpty || urlStr == "about:blank" || urlStr.hasPrefix("file://")
        if isBlank {
            print("[Nav] Detected blank — auto-recover to SOOP home")
            if let home = URL(string: "https://www.sooplive.com/") {
                webView.load(URLRequest(url: home))
            }
        }

        restoreFocus()
        checkLoginStateAndAutoLogin()

        // sooplive.com / afreeca.tv 모든 페이지에서 HLS URL 탐색 시작
        // play.sooplive.com 뿐 아니라 www.sooplive.com 스트리머 페이지에서도 트리거
        if urlStr.contains("sooplive.com") || urlStr.contains("afreeca.tv") {
            startHLSSearch()
        }
    }

    /// 페이지 로드 후 추가 검증.
    /// loadCredentialsAndStart에서 시작 시 1회 로그인을 강제하므로 보통 여기서는
    /// 트리거되지 않지만, 로그인 실패/만료 케이스를 fallback으로 잡는다.
    private func checkLoginStateAndAutoLogin() {
        guard !autoLoginAttempted, let lm = loginManager else { return }
        let url = webView.url?.absoluteString.lowercased() ?? ""
        let loginPagePatterns = ["login.sooplive", "afreeca.tv/login", "/login", "members.sooplive"]
        if loginPagePatterns.contains(where: { url.contains($0) }) { return }
        guard url.contains("sooplive") || url.contains("afreeca") else { return }

        // React 렌더 완료 대기 후 검사
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.autoLoginAttempted else { return }
            let js = """
            (function(){
                var t = document.body ? (document.body.innerText || '') : '';
                // "로그인" 텍스트가 있고 "로그아웃"이 없으면 비로그인 상태
                return t.indexOf('로그인') >= 0 && t.indexOf('로그아웃') < 0;
            })();
            """
            self.webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self = self else { return }
                if let needsLogin = result as? Bool, needsLogin {
                    self.autoLoginAttempted = true
                    print("[ViewController] fallback: 비로그인 감지 → 자동 로그인")
                    lm.forceLogin()
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateURLBar("FAIL")
        print("[Nav] FAIL: \(error.localizedDescription)")
        restoreFocus()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateURLBar("FAIL-PROV")
        print("[Nav] FAIL-PROV: \(error.localizedDescription)")
        restoreFocus()
    }

    // MARK: - WKUIDelegate
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let urlStr = navigationAction.request.url?.absoluteString ?? "(no url)"
        print("[Popup] createWebViewWith url=\(urlStr) targetFrame=\(navigationAction.targetFrame == nil ? "nil(new window)" : "main")")
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            completionHandler()
            self?.restoreFocus()
        })
        releaseFocusForModal()
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            completionHandler(true); self?.restoreFocus()
        })
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { [weak self] _ in
            completionHandler(false); self?.restoreFocus()
        })
        releaseFocusForModal()
        present(alert, animated: true)
    }
}
