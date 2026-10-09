import Foundation
import UIKit

// MARK: - 서버 기반 로그인 클라이언트 (soop-login-svr REST + 폴링 엔진)
//
// 같은 LAN 의 로그인 서버(soop-login-svr)에 헤드풀 브라우저 로그인 창을 요청하고,
// 사용자가 PC 에서 SOOP 로그인(필요 시 2차 인증/보안문자/소셜 로그인)을 완료하면 서버가 캡처한 세션 쿠키를
// 폴링으로 수신한다. 수신한 쿠키 문자열은 호출부가 SOOPAPIClient.applyServerCookies 로 흘려넣는다.
//
// 프로토콜: chzzk-app planning/2026-06-15-server-cookie-login-v1.0.md §4 (naver-login-svr 와 동일).
// - GET  /healthz                       (인증 불필요)
// - POST /api/v1/login/request          { clientId? } → { requestId, status, pollIntervalMs, expiresAt } | 409 busy
// - GET  /api/v1/login/status?requestId → pending | completed(cookies,nickname) | failed(reason) | expired
// - POST /api/v1/login/cancel           { requestId }
//
// .env 의 LOGIN_SERVER_URL / LOGIN_SERVER_TOKEN 을 읽어 동작한다. 둘 중 하나라도 비면 isConfigured=false.
// 콜백 스레드는 임의(URLSession 백그라운드) — UI 갱신은 호출부에서 main 디스패치한다.

/// 서버 로그인 폴링/요청 결과. 호출부(ServerLoginViewController)가 화면 상태로 매핑한다.
enum ServerLoginOutcome {
    /// 쿠키 수신 완료. cookies 는 "AuthTicket=..; UserTicket=..; ..." 형식, nickname 은 서버가 검증한 닉네임(없을 수 있음).
    case completed(cookies: String, nickname: String?)
    /// 실패/만료/취소. reason 은 서버 reason 코드 또는 클라이언트 내부 사유.
    case failed(reason: ServerLoginFailReason)
}

/// 실패 사유 — 서버 reason 코드 + 클라이언트측 내부 상황을 단일 enum 으로 통합.
/// (ServerLoginViewController 의 화면 문구 분기 키)
enum ServerLoginFailReason: Equatable {
    case windowClosed        // 서버 reason: window_closed
    case loginError          // 서버 reason: login_error
    case verificationFailed  // 서버 reason: verification_failed
    case cancelled           // 서버 reason: cancelled (또는 사용자 취소)
    case expired             // 서버 status: expired 또는 클라이언트 폴링 초과
    case serverUnreachable   // /login/request 네트워크 오류 / 500 등 연결 실패
    case unauthorized        // 401 — 토큰 누락/불일치(LOGIN_SERVER_TOKEN 오류)

    /// 서버 reason 문자열 → 사유 코드 매핑. 알 수 없는 코드는 loginError 로 수렴.
    static func from(serverReason raw: String?) -> ServerLoginFailReason {
        switch raw {
        case "window_closed":       return .windowClosed
        case "verification_failed": return .verificationFailed
        case "cancelled":           return .cancelled
        case "login_error":         return .loginError
        default:                    return .loginError
        }
    }
}

final class LoginServerClient {

    static let shared = LoginServerClient()

    private let session: URLSession
    /// 폴링 간격(서버 권장값 우선, 없으면 기본 2초).
    private let defaultPollIntervalMs = 2000
    /// 클라이언트 폴링 한도 — 서버 만료(5분) + 여유 30초. 초과 시 클라이언트도 expired 처리.
    private let clientTimeout: TimeInterval = 5 * 60 + 30

    // 진행 중 세션 상태 (메인 스레드 기준으로만 변경/참조 — requestLogin/cancel 은 호출부에서 main 호출).
    private var currentRequestId: String?
    private var pollTimer: Timer?
    private var pollDeadline: Date?
    private var outcomeHandler: ((ServerLoginOutcome) -> Void)?
    /// 폴링 시작 콜백 — requestId 수신(신규/409 busy) 시 화면을 [S2 대기중]으로 전환하기 위함.
    private var pendingHandler: ((_ isBusy: Bool) -> Void)?
    // completed/failed 를 1회만 보고하기 위한 가드. 읽기/쓰기 모두 main 에서만 일어난다
    // (쓰기: requestLogin/finish, 읽기: startPolling/pollOnce 의 타이머 콜백 — 모두 main runloop).
    // 백그라운드 dataTask 완료 클로저에서는 이 값을 읽지 않는다(데이터 레이스 제거) — 최종 단일성은
    // finish() 가 main 에서 멱등 게이트로 보장한다.
    private var didFinish = false
    /// 연속 폴링 실패(네트워크 오류/파싱 실패) 횟수 — 임계치 초과 시 5분 30초를 기다리지 않고 조기 종료.
    /// 어떤 성공 응답이든 받으면 0 으로 리셋한다. main(타이머 콜백)에서만 변경/참조.
    private var consecutivePollFailures = 0
    /// 조기 종료 임계치 — 약 10초(2초 간격 × 5회) 연속 실패 시 서버 도달 불가로 판단.
    private let maxConsecutivePollFailures = 5

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - .env 설정 로딩

    /// LOGIN_SERVER_URL / LOGIN_SERVER_TOKEN 을 .env 에서 읽는다.
    private static func readEnvField(_ key: String) -> String? {
        guard let path = Bundle.main.path(forResource: ".env", ofType: nil),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var value: String?
        content.enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespaces)
            let prefix = "\(key)="
            if t.hasPrefix(prefix) {
                value = String(t.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        let v = value?.trimmingCharacters(in: .whitespaces)
        return (v?.isEmpty == false) ? v : nil
    }

    // .env 는 앱 번들에 고정 복사돼 런타임 중 바뀌지 않으므로, 첫 접근 시 1회만 읽어 캐시한다.
    // (캐시 전에는 매 makeRequest 마다 .env 를 디스크에서 재파싱 — 5분 30초 폴링 동안 ~165회.)
    // lazy 는 main/요청 디스패치 모두 동일 인스턴스를 통하므로 사실상 첫 isConfigured/요청 시점에 한 번 평가된다.

    /// 서버 Base URL — 끝의 슬래시는 제거해 경로 결합 시 중복 슬래시를 막는다.
    private lazy var baseURL: String? = {
        guard var url = Self.readEnvField("LOGIN_SERVER_URL") else { return nil }
        while url.hasSuffix("/") { url.removeLast() }
        return url.isEmpty ? nil : url
    }()

    private lazy var token: String? = Self.readEnvField("LOGIN_SERVER_TOKEN")

    /// 서버 구성 여부 — URL 과 토큰이 모두 채워졌을 때만 서버 로그인 경로를 노출한다.
    /// (URL 만 있고 토큰이 없으면 모든 /api 요청이 401 이므로 미구성으로 간주)
    var isConfigured: Bool { baseURL != nil && token != nil }

    // MARK: - 요청 빌더

    private func makeRequest(path: String, method: String, authorized: Bool, body: Data? = nil) -> URLRequest? {
        guard let base = baseURL, let url = URL(string: base + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token = token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }

    // MARK: - healthz (연결성 사전 점검)

    /// 서버 연결 가능 여부를 확인한다. 인증 불필요. (사용 선택 — requestLogin 이 실패를 직접 보고하므로 필수는 아님)
    func checkHealth(completion: @escaping (Bool) -> Void) {
        guard let req = makeRequest(path: "/healthz", method: "GET", authorized: false) else {
            completion(false); return
        }
        session.dataTask(with: req) { _, resp, error in
            let ok = error == nil && (resp as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } == true
            completion(ok)
        }.resume()
    }

    // MARK: - 로그인 요청 + 폴링 시작

    /// 로그인 세션을 시작한다.
    /// - clientId: 로깅용 기기 식별자(선택).
    /// - onPending: requestId 수신 시 1회 호출 — isBusy 는 409 busy(기존 세션 재사용) 여부. 화면을 [S2]로 전환.
    /// - onOutcome: 최종 결과(completed/failed) 1회 호출. completed 수신 즉시 폴링 중단.
    /// 모든 콜백 스레드는 임의 — UI 는 호출부에서 main 디스패치한다.
    func requestLogin(clientId: String? = nil,
                      onPending: @escaping (_ isBusy: Bool) -> Void,
                      onOutcome: @escaping (ServerLoginOutcome) -> Void) {
        // 직전 세션 정리 — 재요청("다시 요청") 시 잔여 타이머가 겹치지 않게.
        stopPolling()
        didFinish = false
        self.pendingHandler = onPending
        self.outcomeHandler = onOutcome

        var bodyObj: [String: Any] = [:]
        if let clientId = clientId { bodyObj["clientId"] = clientId }
        let body = try? JSONSerialization.data(withJSONObject: bodyObj)

        guard let req = makeRequest(path: "/api/v1/login/request", method: "POST",
                                    authorized: true, body: body ?? Data("{}".utf8)) else {
            finish(.failed(reason: .serverUnreachable)); return
        }

        session.dataTask(with: req) { [weak self] data, resp, error in
            guard let self = self else { return }
            if let error = error {
                print("[LoginServer] /login/request 네트워크 오류: \(error.localizedDescription)")
                self.finish(.failed(reason: .serverUnreachable)); return
            }
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let json = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]

            // 200 신규 세션 / 409 busy(기존 requestId 재사용) 둘 다 requestId 가 오면 폴링 시작.
            if status == 200 || status == 409 {
                guard let requestId = json?["requestId"] as? String, !requestId.isEmpty else {
                    print("[LoginServer] /login/request 응답에 requestId 없음 (status=\(status))")
                    self.finish(.failed(reason: .serverUnreachable)); return
                }
                let pollMs = (json?["pollIntervalMs"] as? Int) ?? self.defaultPollIntervalMs
                let isBusy = (status == 409)
                self.startPolling(requestId: requestId, pollIntervalMs: pollMs, isBusy: isBusy)
            } else if status == 401 {
                // 토큰 누락/불일치 → 연결 실패와 구분해 별도 안내(LOGIN_SERVER_TOKEN 점검 유도).
                print("[LoginServer] /login/request 인증 실패 status=401")
                self.finish(.failed(reason: .unauthorized))
            } else {
                // 500 browser_launch_failed / 기타 → 서버 연결/구성 실패로 보고.
                print("[LoginServer] /login/request 실패 status=\(status)")
                self.finish(.failed(reason: .serverUnreachable))
            }
        }.resume()
    }

    private func startPolling(requestId: String, pollIntervalMs: Int, isBusy: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.didFinish else { return }
            self.currentRequestId = requestId
            self.pollDeadline = Date().addingTimeInterval(self.clientTimeout)
            // requestId 확보 → 화면을 [S2 대기중]으로 전환.
            self.pendingHandler?(isBusy)

            let interval = max(0.5, Double(pollIntervalMs) / 1000.0)
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                self?.pollOnce()
            }
            // 타이머가 자기 자신을 강하게 잡지 않도록(메모리 누수 방지) common 모드 등록만 한다.
            RunLoop.main.add(timer, forMode: .common)
            self.pollTimer = timer
            self.consecutivePollFailures = 0
            // 첫 폴링은 간격을 기다리지 않고 즉시 1회 — 빠른 완료 반영.
            self.pollOnce()
        }
    }

    private func pollOnce() {
        guard !didFinish, let requestId = currentRequestId else { return }
        // 클라이언트 폴링 한도 초과 → expired 처리(서버 만료 + 여유 초과).
        if let deadline = pollDeadline, Date() >= deadline {
            print("[LoginServer] 클라이언트 폴링 한도 초과 — expired 처리")
            finish(.failed(reason: .expired)); return
        }
        // requestId 퍼센트 인코딩(하드닝) — 서버 UUID라 실무상 안전하나 쿼리 안전성 보장.
        let encodedId = requestId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? requestId
        guard let req = makeRequest(
            path: "/api/v1/login/status?requestId=\(encodedId)", method: "GET", authorized: true
        ) else { return }

        // 백그라운드 완료 클로저에서는 didFinish 를 읽지 않는다(레이스 제거). 결과 처리/실패 카운트는
        // 모두 main 으로 디스패치해 처리하며, finish() 의 멱등 게이트가 최종 단일성을 보장한다.
        session.dataTask(with: req) { [weak self] data, resp, error in
            // 일시적 네트워크 오류는 폴링을 끝내지 않고 다음 주기에 재시도(타임아웃 한도가 최종 게이트).
            // 단, 연속 실패가 임계치를 넘으면 서버 도달 불가로 보고 조기 종료한다.
            if error != nil {
                self?.handlePollFailure(); return
            }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // 404 unknown_request = 세션이 사라짐/정리됨 → 만료로 간주하고 종료.
            if status == 404 {
                self?.finish(.failed(reason: .expired)); return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self?.handlePollFailure(); return
            }

            switch json["status"] as? String {
            case "pending":
                self?.resetPollFailures()
                return   // 계속 폴링
            case "completed":
                let cookies = (json["cookies"] as? String) ?? ""
                let nickname = json["nickname"] as? String
                // 쿠키 누락 = 비정상 completed → 검증 실패로 처리(applyServerCookies 가 어차피 거름).
                guard !cookies.isEmpty else {
                    self?.finish(.failed(reason: .verificationFailed)); return
                }
                self?.finish(.completed(cookies: cookies, nickname: (nickname?.isEmpty == false) ? nickname : nil))
            case "failed":
                self?.finish(.failed(reason: .from(serverReason: json["reason"] as? String)))
            case "expired":
                self?.finish(.failed(reason: .expired))
            default:
                // 알 수 없는 상태 — 정상 응답이므로 카운터 리셋 후 다음 주기 재시도.
                self?.resetPollFailures()
                return
            }
        }.resume()
    }

    /// 폴링 transient 실패 1건 기록(main). 임계치 초과 시 서버 도달 불가로 조기 종료한다.
    private func resetPollFailures() {
        DispatchQueue.main.async { [weak self] in
            self?.consecutivePollFailures = 0
        }
    }

    private func handlePollFailure() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.didFinish else { return }
            self.consecutivePollFailures += 1
            if self.consecutivePollFailures >= self.maxConsecutivePollFailures {
                print("[LoginServer] 연속 폴링 실패 \(self.consecutivePollFailures)회 — serverUnreachable 조기 종료")
                self.finish(.failed(reason: .serverUnreachable))
            }
        }
    }

    // MARK: - 취소

    /// 진행 중 세션을 취소한다 — fire-and-forget(/login/cancel). 폴링은 즉시 중단한다.
    /// 화면 전환([S4 cancelled])은 호출부가 담당하므로 outcome 콜백은 호출하지 않는다.
    func cancel() {
        let requestId = currentRequestId
        stopPolling()
        guard let requestId = requestId,
              let body = try? JSONSerialization.data(withJSONObject: ["requestId": requestId]),
              let req = makeRequest(path: "/api/v1/login/cancel", method: "POST", authorized: true, body: body) else {
            return
        }
        session.dataTask(with: req) { _, _, _ in /* fire-and-forget */ }.resume()
    }

    // MARK: - 내부 종료 처리

    /// completed/failed 를 1회만 보고하고 폴링을 정리한다.
    private func finish(_ outcome: ServerLoginOutcome) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.didFinish else { return }
            self.didFinish = true
            let handler = self.outcomeHandler
            self.stopPolling()
            handler?(outcome)
        }
    }

    /// 타이머/상태를 정리한다. (재요청·취소·완료 공통)
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollDeadline = nil
        currentRequestId = nil
        pendingHandler = nil
        outcomeHandler = nil
    }
}
