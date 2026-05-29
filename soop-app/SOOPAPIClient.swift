import Foundation

// MARK: - SOOP 네이티브 API 클라이언트
//
// WKWebView 없이 SOOP의 HTTP API를 직접 호출한다.
// 1. 홈 페이지 HTML 스크래핑으로 라이브 방송 목록 추출
// 2. player_live_api.php 로 방송 메타데이터/스트림 URL 획득
// 3. broad_stream_assign.html 로 인증된 m3u8 URL 획득 (fallback)

struct LiveBroadcast {
    let bjId: String
    let broadNo: String
    let title: String
    let bjNick: String
    let thumbnailURL: URL?
    let viewerCount: Int
    let category: String
}

/// SOOP 카테고리 — sch.sooplive.com categoryList API 응답을 모델화
struct SOOPCategory {
    let code: String        // "00040019"
    let name: String        // "리그 오브 레전드"
    let viewCount: Int      // 시청자 합계
    let imageURL: URL?      // 카테고리 대표 이미지
    let tags: [String]      // 고정 태그
}

/// 즐겨찾기 BJ — myapi.sooplive.co.kr/api/favorite 응답
struct FavoriteBJ {
    let bjId: String
    let nick: String
    let isLive: Bool
    let stationName: String
    let totalViewCount: Int
    let lastBroadStart: String?
}

struct StreamInfo {
    let bjId: String
    let broadNo: String
    let title: String
    let bjNick: String
    let viewURL: URL          // 실제 AVPlayer로 넘길 m3u8 URL
    let timeShiftURL: URL?    // TS 필드 (인증 토큰 포함된 fallback)
    let aid: String?
    let resolution: String
    let isLive: Bool
}

enum SOOPAPIError: Error {
    case invalidURL
    case invalidResponse
    case decodingFailed(String)
    case streamUnavailable(String)
    case notLive
    /// SOOP `RESULT=-6` — 19+ 방송에 인증 미통과. AbroadChk=FAIL 쿠키 보유 상태.
    case adultVerificationRequired
}

extension Notification.Name {
    static let soopLoginSucceeded = Notification.Name("soopLoginSucceeded")
}

final class SOOPAPIClient {

    static let shared = SOOPAPIClient()

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7"
        ]
        self.session = URLSession(configuration: config)

        // .env에 SOOP_COOKIES=name1=val1; name2=val2 형식으로 저장된 쿠키를 부팅 시 주입.
        // 네이버 OAuth 등 복잡한 로그인 흐름을 우회하기 위한 수동 세션 주입.
        Self.injectCookiesFromEnv()
    }

    /// .env에서 SOOP_COOKIES 값을 읽어 HTTPCookieStorage.shared 에 주입.
    /// 포맷: `SOOP_COOKIES=_au=xxx; _au3rd=yyy; AuthTicket=zzz; UserTicket=www`
    static func injectCookiesFromEnv() {
        guard let path = Bundle.main.path(forResource: ".env", ofType: nil),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("[SOOPAPI] .env not found — no manual cookies")
            return
        }
        var cookieString = ""
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SOOP_COOKIES=") {
                cookieString = String(trimmed.dropFirst("SOOP_COOKIES=".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        guard !cookieString.isEmpty else {
            print("[SOOPAPI] SOOP_COOKIES not in .env")
            return
        }
        var injected = 0
        for pair in cookieString.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let name = parts[0], value = parts[1]
            // sooplive.com 전체 도메인에 적용 (서브도메인 모두 포함)
            for domain in [".sooplive.com", "sooplive.com"] {
                let props: [HTTPCookiePropertyKey: Any] = [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: "/",
                    .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 30)
                ]
                if let cookie = HTTPCookie(properties: props) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                    injected += 1
                }
            }
        }
        print("[SOOPAPI] injected \(injected) cookies from .env")
    }

    // MARK: - 네이티브 로그인 (login.sooplive.co.kr/app/LoginAction.php)
    //
    // yt-dlp #11266 패턴 그대로. .env의 SOOP_ID / SOOP_PASSWORD 로 POST 로그인.
    // 성공 시 AuthTicket·UserTicket·BbsTicket 등이 HTTPCookieStorage.shared 에 저장됨.

    /// .env에서 ID/PW 읽어 로그인 시도. 결과는 콜백.
    /// - completion: success=true이면 로그인 성공, 쿠키가 세션에 저장됨.
    func login(completion: @escaping (Bool, String?) -> Void) {
        guard let creds = Self.loadCredentialsFromEnv(),
              !creds.id.isEmpty, !creds.pw.isEmpty else {
            print("[SOOPAPI] login: no credentials in .env")
            completion(false, "No SOOP_ID / SOOP_PASSWORD in .env")
            return
        }
        guard let url = URL(string: "https://login.sooplive.co.kr/app/LoginAction.php") else {
            completion(false, "invalid URL")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://login.sooplive.co.kr", forHTTPHeaderField: "Origin")
        req.setValue("https://login.sooplive.co.kr/afreeca/login.php", forHTTPHeaderField: "Referer")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "szWork", value: "login"),
            URLQueryItem(name: "szType", value: "json"),
            URLQueryItem(name: "szUid", value: creds.id),
            URLQueryItem(name: "szPassword", value: creds.pw),
            URLQueryItem(name: "isSaveId", value: "false"),
            URLQueryItem(name: "szScriptVar", value: "oLoginRet"),
            URLQueryItem(name: "szAction", value: "")
        ]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        session.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, "decoding failed")
                return
            }
            let result = (json["RESULT"] as? Int) ?? Int((json["RESULT"] as? String) ?? "0") ?? 0
            if result == 1 {
                // 쿠키 자동 저장 (URLSession이 HTTPCookieStorage.shared 사용 중)
                let cookies = HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("sooplive") } ?? []
                print("[SOOPAPI] login OK — \(cookies.count) cookies stored")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .soopLoginSucceeded, object: nil)
                }
                completion(true, nil)
            } else {
                let msg = "RESULT=\(result) (\(json))"
                print("[SOOPAPI] login FAILED: \(msg)")
                completion(false, msg)
            }
        }.resume()
    }

    private struct Creds { let id: String; let pw: String }

    private static func loadCredentialsFromEnv() -> Creds? {
        guard let path = Bundle.main.path(forResource: ".env", ofType: nil),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        var id = "", pw = ""
        content.enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("SOOP_ID=") { id = String(t.dropFirst("SOOP_ID=".count)).trimmingCharacters(in: .whitespaces) }
            if t.hasPrefix("SOOP_PASSWORD=") { pw = String(t.dropFirst("SOOP_PASSWORD=".count)).trimmingCharacters(in: .whitespaces) }
        }
        return Creds(id: id, pw: pw)
    }

    // MARK: - 즐겨찾기 BJ 목록 (myapi.sooplive.co.kr/api/favorite)

    /// 로그인된 사용자의 즐겨찾기 BJ 목록 가져오기. 로그인 안 됐으면 빈 결과.
    func fetchFavorites(completion: @escaping (Result<[FavoriteBJ], SOOPAPIError>) -> Void) {
        guard let url = URL(string: "https://myapi.sooplive.co.kr/api/favorite") else {
            completion(.failure(.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://www.sooplive.co.kr/", forHTTPHeaderField: "Referer")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]] else {
                completion(.failure(.invalidResponse))
                return
            }
            var favs: [FavoriteBJ] = []
            for f in list {
                guard let bjId = f["user_id"] as? String, !bjId.isEmpty else { continue }
                let nick = (f["user_nick"] as? String) ?? bjId
                let isLive = (f["is_live"] as? Bool) ?? false
                let station = (f["station_name"] as? String) ?? ""
                let viewCnt = (f["total_view_cnt"] as? Int) ?? 0
                let lastStart = f["last_broad_start"] as? String
                favs.append(FavoriteBJ(
                    bjId: bjId, nick: nick, isLive: isLive,
                    stationName: station, totalViewCount: viewCnt,
                    lastBroadStart: lastStart
                ))
            }
            // 정렬: 라이브 → 즐겨찾기 추가 순
            let sorted = favs.sorted { ($0.isLive ? 1 : 0) > ($1.isLive ? 1 : 0) }
            print("[SOOPAPI] fetchFavorites: \(sorted.count) (\(sorted.filter{$0.isLive}.count) live)")
            completion(.success(sorted))
        }.resume()
    }

    // MARK: - 실시간 카테고리 API (sch.sooplive.com)

    /// 모든 SOOP 카테고리를 페이지네이션으로 가져온다.
    /// `https://sch.sooplive.com/api.php?m=categoryList&szPlatform=pc&nPageNo=N&nListCnt=100`
    /// view_cnt 기준 정렬되어 있음.
    func fetchCategories(maxPages: Int = 7,
                        completion: @escaping (Result<[SOOPCategory], SOOPAPIError>) -> Void) {
        let group = DispatchGroup()
        // 페이지별 결과를 분리 보관 — 응답 도착 순서가 dedup 결과에 영향을 미치지 않게 한다.
        // (기존 버그: 7페이지를 병렬 호출하면 allCats에 append되는 순서가 비결정적이라
        // 같은 code로 다른 name이 들어올 때 새로고침마다 어느 쪽이 살아남는지 바뀌었음.
        // 예: 같은 code에 페이지 1=여행, 페이지 2=토크/캠방으로 응답하던 케이스에서
        // 페이지 2가 먼저 도착하면 토크/캠방이 우선 채택되어 라벨이 뒤바뀌었다.)
        var pageResults: [Int: [SOOPCategory]] = [:]
        let lock = NSLock()
        var anyFailed = false

        for page in 1...maxPages {
            group.enter()
            let urlStr = "https://sch.sooplive.com/api.php?m=categoryList&szPlatform=pc&nPageNo=\(page)&nListCnt=100"
            guard let url = URL(string: urlStr) else { group.leave(); continue }
            var req = URLRequest(url: url)
            req.setValue("https://www.sooplive.com/", forHTTPHeaderField: "Referer")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            session.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataDict = json["data"] as? [String: Any],
                      let list = dataDict["list"] as? [[String: Any]] else {
                    anyFailed = true
                    return
                }
                var pageCats: [SOOPCategory] = []
                for c in list {
                    let code = (c["category_no"] as? String) ?? ""
                    let name = (c["category_name"] as? String) ?? ""
                    let vcnt = (c["view_cnt"] as? Int) ?? Int(c["view_cnt"] as? String ?? "0") ?? 0
                    let imgStr = (c["cate_img"] as? String) ?? ""
                    let tags = (c["fixed_tags"] as? [String]) ?? []
                    guard !code.isEmpty, !name.isEmpty else { continue }
                    pageCats.append(SOOPCategory(
                        code: code, name: name, viewCount: vcnt,
                        imageURL: URL(string: imgStr), tags: tags
                    ))
                }
                lock.lock(); pageResults[page] = pageCats; lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) {
            // 결정적 머지: 페이지 번호 오름차순으로 순회하여 첫 등장 entry를 채택.
            // 같은 code의 다른 name이 더 뒷 페이지에 또 나오더라도 무시 → 결과가 항상 같음.
            var seen = Set<String>()
            var unique: [SOOPCategory] = []
            for page in 1...maxPages {
                for cat in pageResults[page] ?? [] {
                    if seen.insert(cat.code).inserted {
                        unique.append(cat)
                    }
                }
            }
            // 정렬: view_cnt 내림차순
            let sorted = unique.sorted { $0.viewCount > $1.viewCount }
            print("[SOOPAPI] fetchCategories: \(sorted.count) categories (deterministic merge)")
            if sorted.isEmpty && anyFailed {
                completion(.failure(.invalidResponse))
            } else {
                completion(.success(sorted))
            }
        }
    }

    /// 특정 카테고리의 라이브 방송 목록 가져오기.
    /// `https://sch.sooplive.com/api.php?m=categoryContentsList&szCateNo={CODE}&szType=live`
    func fetchBroadcasts(byCategory cateCode: String,
                        pageCount: Int = 60,
                        completion: @escaping (Result<[LiveBroadcast], SOOPAPIError>) -> Void) {
        let urlStr = "https://sch.sooplive.com/api.php?m=categoryContentsList&szType=live&nPageNo=1&nListCnt=\(pageCount)&szPlatform=pc&szCateNo=\(cateCode)&szOrder=view_cnt_desc&strmLangType="
        guard let url = URL(string: urlStr) else {
            completion(.failure(.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://www.sooplive.com/", forHTTPHeaderField: "Referer")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req) { data, _, error in
            if let error = error {
                print("[SOOPAPI] fetchBroadcasts error: \(error)")
                completion(.failure(.invalidResponse))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let list = dataDict["list"] as? [[String: Any]] else {
                completion(.failure(.invalidResponse))
                return
            }
            var results: [LiveBroadcast] = []
            for b in list {
                let bjId = (b["user_id"] as? String) ?? ""
                let nick = (b["user_nick"] as? String) ?? bjId
                let title = (b["broad_title"] as? String) ?? nick
                let thumb = (b["thumbnail"] as? String) ?? ""
                let bno = String((b["broad_no"] as? Int) ?? Int((b["broad_no"] as? String) ?? "0") ?? 0)
                let cate = (b["broad_cate_no"] as? String) ?? ""
                let viewCnt = (b["view_cnt"] as? Int) ?? Int((b["view_cnt"] as? String) ?? "0") ?? 0
                guard !bjId.isEmpty, bno != "0" else { continue }
                results.append(LiveBroadcast(
                    bjId: bjId, broadNo: bno,
                    title: title, bjNick: nick,
                    thumbnailURL: URL(string: thumb),
                    viewerCount: viewCnt,
                    category: cate
                ))
            }
            print("[SOOPAPI] fetchBroadcasts(\(cateCode)): \(results.count) live")
            completion(.success(results))
        }.resume()
    }

    // MARK: - 인기 BJID 폴링
    //
    // SOOP의 라이브 리스트 API가 client-side rendering이라 단순 HTTP 호출로
    // 얻기 어려움. 대신 잘 알려진 인기 BJ들의 BJID를 하드코딩해 player_live_api로
    // 각자 라이브 상태를 폴링한다. RESULT==1 && BSTATUS=="BROADING" 인 것만 표시.

    static let knownBJIDs: [String] = [
        // 게임 (GTA / 기타)
        "khm11903",      // 봉준 (GTA)
        "phonics1",      // 김민교 (GTA)
        "rrvv17",        // 항상#킴성태 (GTA)
        "iamquaddurup",  // 장지수 (GTA)
        "dlsn9911",      // 제갈금자 (GTA)
        "joey1114",      // 저라뎃 (GTA)
        "b13246",        // 타요* (GTA)
        "gksdidqksxn",   // 준밧드 (GTA)
        "brainzerg7",    // Calm_김윤환 (스타크래프트)
        // 토크/캠방
        "devil0108",     // 감스트
        "wnnw",          // 남순
        // 버튜버 (시도 — BJID 추측)
        "bichan_v",
        "yuumi_v",
        "lupinasol",
        // 스포츠 / 기타
        "kbo_official",
        "sports_kr",
        "soop_sports",
        // 음악
        "music_live",
        "mc1004"
    ]

    /// 주어진 BJID 리스트 전체를 폴링해서 라이브 중인 방송만 반환.
    /// 카테고리 페이지에서 스크래핑한 BJID 풀로 호출.
    func fetchLiveListForBJIDs(_ bjids: [String],
                              completion: @escaping (Result<[LiveBroadcast], SOOPAPIError>) -> Void) {
        let group = DispatchGroup()
        var results: [LiveBroadcast] = []
        let lock = NSLock()

        for bjId in bjids {
            group.enter()
            _fetchChannelMeta(bjId: bjId, broadNo: "0") { meta in
                defer { group.leave() }
                guard let meta = meta else { return }
                let thumb = URL(string: "https://liveimg.sooplive.com/m/\(meta.broadNo)?\(Int.random(in: 1...999))")
                let bc = LiveBroadcast(
                    bjId: meta.bjId, broadNo: meta.broadNo,
                    title: meta.title.isEmpty ? meta.bjNick : meta.title,
                    bjNick: meta.bjNick,
                    thumbnailURL: thumb,
                    viewerCount: 0,
                    category: meta.cate
                )
                lock.lock(); results.append(bc); lock.unlock()
            }
        }
        group.notify(queue: .main) {
            print("[SOOPAPI] fetchLiveListForBJIDs(\(bjids.count)): \(results.count) live")
            completion(.success(results))
        }
    }

    /// 라이브 방송 목록을 가져온다.
    /// - parameter categoryPrefix: 카테고리 CATE 코드 prefix (예: "00040000"=게임).
    ///   nil이면 카테고리 필터 없이 전체.
    func fetchLiveList(categoryPrefix: String? = nil,
                      completion: @escaping (Result<[LiveBroadcast], SOOPAPIError>) -> Void) {
        let group = DispatchGroup()
        var results: [LiveBroadcast] = []
        let lock = NSLock()

        for bjId in Self.knownBJIDs {
            group.enter()
            _fetchChannelMeta(bjId: bjId, broadNo: "0") { meta in
                defer { group.leave() }
                guard let meta = meta else { return }
                let thumb = URL(string: "https://liveimg.sooplive.com/m/\(meta.broadNo)?\(Int.random(in: 1...999))")
                let bc = LiveBroadcast(
                    bjId: meta.bjId, broadNo: meta.broadNo,
                    title: meta.title.isEmpty ? meta.bjNick : meta.title,
                    bjNick: meta.bjNick,
                    thumbnailURL: thumb,
                    viewerCount: 0,
                    category: meta.cate
                )
                lock.lock(); results.append(bc); lock.unlock()
                print("[SOOPAPI] live: \(meta.bjId) cate=\(meta.cate) title=\(meta.title.prefix(30))")
            }
        }
        group.notify(queue: .main) {
            print("[SOOPAPI] fetchLiveList: total live=\(results.count), filter=\(categoryPrefix ?? "ALL")")
            for r in results {
                print("  → \(r.bjId) cate=\(r.category) title=\(r.title.prefix(40))")
            }
            // 카테고리 필터 — STRICT (매칭 없으면 빈 결과 반환)
            var filtered = results
            if let prefix = categoryPrefix, !prefix.isEmpty {
                let cat4 = String(prefix.prefix(4))
                filtered = results.filter { $0.category.hasPrefix(cat4) }
                print("  filter prefix=\(cat4) → matched \(filtered.count)")
            }
            print("  → returning \(filtered.count) broadcasts")
            completion(.success(filtered))
        }
    }

    /// 가벼운 채널 메타 조회 — 카테고리 필터링용. 스트림 URL은 받지 않음 (빠름).
    private struct ChannelMeta {
        let bjId: String
        let broadNo: String
        let title: String
        let bjNick: String
        let cate: String
    }

    private func _fetchChannelMeta(bjId: String, broadNo: String, completion: @escaping (ChannelMeta?) -> Void) {
        guard let url = URL(string: "https://live.sooplive.com/afreeca/player_live_api.php?bjid=\(bjId)") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://play.sooplive.com", forHTTPHeaderField: "Origin")
        req.setValue("https://play.sooplive.com/\(bjId)", forHTTPHeaderField: "Referer")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = "bid=\(bjId)&bno=0&type=live&pwd=&player_type=html5&stream_type=common&quality=master&mode=landing&from_api=0".data(using: .utf8)

        session.dataTask(with: req) { data, _, _ in
            guard let data = data else { completion(nil); return }
            let clean = Self.sanitizeJSONBytes(data)
            guard let j = try? JSONSerialization.jsonObject(with: clean) as? [String: Any],
                  let c = j["CHANNEL"] as? [String: Any],
                  let result = c["RESULT"] as? Int ?? Int((c["RESULT"] as? String) ?? "0"),
                  result == 1,
                  let bstatus = c["BSTATUS"] as? String,
                  bstatus == "BROADING",
                  let bno = c["BNO"] as? String else {
                completion(nil); return
            }
            completion(ChannelMeta(
                bjId: bjId, broadNo: bno,
                title: c["TITLE"] as? String ?? "",
                bjNick: c["BJNICK"] as? String ?? bjId,
                cate: c["CATE"] as? String ?? ""
            ))
        }.resume()
    }

    // MARK: - 스트림 정보 (player_live_api.php)

    /// 익명 시청용 쿠키 부트스트랩 — 홈 + 플레이 페이지 방문해서 _au, _ausa, _ausb 같은
    /// 세션 쿠키를 받아둔 뒤 API를 호출하면 스트림 URL의 인증이 통과될 가능성이 높아진다.
    private func bootstrapCookies(forBJID bjId: String, broadNo: String, completion: @escaping () -> Void) {
        let urls: [String] = [
            "https://www.sooplive.com/",
            "https://play.sooplive.com/\(bjId)/\(broadNo)"
        ]
        let group = DispatchGroup()
        for str in urls {
            guard let u = URL(string: str) else { continue }
            var req = URLRequest(url: u)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9", forHTTPHeaderField: "Accept")
            group.enter()
            session.dataTask(with: req) { _, _, _ in group.leave() }.resume()
        }
        group.notify(queue: .global()) { completion() }
    }

    func fetchStreamInfo(bjId: String, broadNo: String,
                        completion: @escaping (Result<StreamInfo, SOOPAPIError>) -> Void) {
        bootstrapCookies(forBJID: bjId, broadNo: broadNo) { [weak self] in
            self?._fetchStreamInfo(bjId: bjId, broadNo: broadNo, completion: completion)
        }
    }

    private func _fetchStreamInfo(bjId: String, broadNo: String,
                                 completion: @escaping (Result<StreamInfo, SOOPAPIError>) -> Void) {
        guard let url = URL(string: "https://live.sooplive.com/afreeca/player_live_api.php?bjid=\(bjId)") else {
            completion(.failure(.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://play.sooplive.com", forHTTPHeaderField: "Origin")
        req.setValue("https://play.sooplive.com/\(bjId)/\(broadNo)", forHTTPHeaderField: "Referer")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let body = "bid=\(bjId)&bno=\(broadNo)&type=live&pwd=&player_type=html5&stream_type=common&quality=master&mode=landing&from_api=0&is_revive=false"
        req.httpBody = body.data(using: .utf8)

        session.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(.invalidResponse))
                print("[SOOPAPI] fetchStreamInfo error: \(error)")
                return
            }
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }

            // SOOP 응답에 제어문자가 끼어있는 경우가 있어 sanitize 후 파싱
            let sanitized = Self.sanitizeJSONBytes(data)
            guard let json = try? JSONSerialization.jsonObject(with: sanitized) as? [String: Any],
                  let channel = json["CHANNEL"] as? [String: Any] else {
                completion(.failure(.decodingFailed("CHANNEL field missing")))
                return
            }

            let result = (channel["RESULT"] as? Int) ?? Int(channel["RESULT"] as? String ?? "0") ?? 0
            let bstatus = channel["BSTATUS"] as? String ?? ""
            // RESULT=-6은 SOOP의 19+ 인증 미통과 신호 (AbroadChk=FAIL 쿠키 상태).
            // 19+ 방송 시청은 SOOP 계정의 휴대폰 본인인증 + 성인 콘텐츠 보기 활성화가 필요하며
            // 클라이언트(앱) 측 우회는 불가능하다. 별도 에러로 분리해서 UI에서 구체 메시지를 띄운다.
            if result == -6 {
                let abroadChk = HTTPCookieStorage.shared.cookies?
                    .first(where: { $0.name == "AbroadChk" })?.value ?? "(none)"
                print("[SOOPAPI] _fetchStreamInfo: RESULT=-6 (adult verification needed). AbroadChk=\(abroadChk)")
                completion(.failure(.adultVerificationRequired))
                return
            }
            if result != 1 || bstatus != "BROADING" {
                print("[SOOPAPI] _fetchStreamInfo: RESULT=\(result) BSTATUS=\(bstatus) → notLive")
                completion(.failure(.notLive))
                return
            }

            let bjNick = channel["BJNICK"] as? String ?? bjId
            let title = channel["TITLE"] as? String ?? ""
            let resolution = channel["RESOLUTION"] as? String ?? ""
            let initialAid = (channel["AID"] as? String) ?? (channel["hls_authentication_key"] as? String)
            let tsURLString = channel["TS"] as? String ?? ""
            let actualBNO = (channel["BNO"] as? String) ?? broadNo

            // 1080p 우회 시도: TS URL을 viewURL로 먼저 시도, view_url+aid는 fallback
            // Chrome video element는 TS URL로 1080p~1440p를 받음. AVPlayer는 native HLS이라
            // 미디어 스택 레벨에서 동일 처리될 가능성. 401 받으면 PlayerViewController가
            // timeShiftURL(여기선 view_url+aid)로 자동 fallback.
            self.fetchAID(bjId: bjId, broadNo: actualBNO) { aidResult in
                let aid = (try? aidResult.get()) ?? initialAid
                if let aid = aid, !aid.isEmpty {
                    self.fetchViewURL(broadNo: actualBNO, bjId: bjId) { vResult in
                        switch vResult {
                        case .success(let vurl):
                            let composed = URL(string: vurl.absoluteString + "?aid=" + aid) ?? vurl
                            // viewURL = TS (고화질 시도), timeShiftURL = view_url+aid (540p fallback)
                            let primary: URL
                            let fallback: URL?
                            if let ts = URL(string: tsURLString), !tsURLString.isEmpty {
                                primary = ts
                                fallback = composed
                                print("[SOOPAPI] primary(TS, \(resolution)): \(tsURLString.prefix(140))")
                                print("[SOOPAPI] fallback(view_url+aid): \(composed.absoluteString.prefix(140))")
                            } else {
                                primary = composed
                                fallback = nil
                                print("[SOOPAPI] only view_url+aid available")
                            }
                            let info = StreamInfo(
                                bjId: bjId, broadNo: actualBNO,
                                title: title, bjNick: bjNick,
                                viewURL: primary,
                                timeShiftURL: fallback,
                                aid: aid, resolution: resolution, isLive: true
                            )
                            completion(.success(info))
                        case .failure:
                            // view_url 실패 → TS 시도
                            if let ts = URL(string: tsURLString), !tsURLString.isEmpty {
                                let info = StreamInfo(
                                    bjId: bjId, broadNo: actualBNO,
                                    title: title, bjNick: bjNick,
                                    viewURL: ts, timeShiftURL: ts,
                                    aid: aid, resolution: resolution, isLive: true
                                )
                                completion(.success(info))
                            } else {
                                completion(.failure(.streamUnavailable("view_url+TS both failed")))
                            }
                        }
                    }
                } else if let ts = URL(string: tsURLString), !tsURLString.isEmpty {
                    let info = StreamInfo(
                        bjId: bjId, broadNo: actualBNO,
                        title: title, bjNick: bjNick,
                        viewURL: ts, timeShiftURL: ts,
                        aid: nil, resolution: resolution, isLive: true
                    )
                    completion(.success(info))
                } else {
                    completion(.failure(.streamUnavailable("no auth available")))
                }
            }
        }.resume()
    }

    /// AID 별도 호출 — `type=aid` 로 player_live_api.php에 다시 POST.
    /// 로그인 세션 쿠키가 있어야 RESULT=1 + AID 반환됨.
    private func fetchAID(bjId: String, broadNo: String,
                         completion: @escaping (Result<String, SOOPAPIError>) -> Void) {
        guard let url = URL(string: "https://live.sooplive.com/afreeca/player_live_api.php?bjid=\(bjId)") else {
            completion(.failure(.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://play.sooplive.com", forHTTPHeaderField: "Origin")
        req.setValue("https://play.sooplive.com/\(bjId)/\(broadNo)", forHTTPHeaderField: "Referer")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let body = "bid=\(bjId)&bno=\(broadNo)&type=aid&pwd=&player_type=html5&stream_type=common&quality=master&mode=landing&from_api=0"
        req.httpBody = body.data(using: .utf8)

        session.dataTask(with: req) { data, _, _ in
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            let clean = Self.sanitizeJSONBytes(data)
            guard let json = try? JSONSerialization.jsonObject(with: clean) as? [String: Any],
                  let channel = json["CHANNEL"] as? [String: Any] else {
                completion(.failure(.decodingFailed("AID response invalid")))
                return
            }
            // RESULT가 1이고 AID가 있어야 성공
            if let aid = channel["AID"] as? String, !aid.isEmpty {
                completion(.success(aid))
            } else {
                completion(.failure(.streamUnavailable("AID not granted (login required?)")))
            }
        }.resume()
    }

    // MARK: - view_url + AID (TS가 안 될 때 시도)

    func fetchViewURL(broadNo: String, bjId: String, cdn: String = "lg_cdn_pc_web",
                     quality: String = "master",
                     completion: @escaping (Result<URL, SOOPAPIError>) -> Void) {
        let urlStr = "https://livestream-manager.sooplive.com/broad_stream_assign.html?return_type=\(cdn)&use_cors=true&cors_origin_url=play.sooplive.com&broad_key=\(broadNo)-common-\(quality)-hls&player_mode=embed&time=\(Int.random(in: 1...100000))"
        guard let url = URL(string: urlStr) else {
            completion(.failure(.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://play.sooplive.com", forHTTPHeaderField: "Origin")
        req.setValue("https://play.sooplive.com/\(bjId)/\(broadNo)", forHTTPHeaderField: "Referer")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failure(.invalidResponse))
                print("[SOOPAPI] fetchViewURL error: \(error)")
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let viewURL = json["view_url"] as? String,
                  let url = URL(string: viewURL) else {
                completion(.failure(.streamUnavailable("view_url missing")))
                return
            }
            completion(.success(url))
        }.resume()
    }

    // MARK: - 유틸

    /// SOOP 응답에 종종 끼는 제어문자(0x00-0x1F 중 \n, \r, \t 제외)를 제거.
    private static func sanitizeJSONBytes(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        for byte in data {
            if byte >= 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                out.append(byte)
            }
        }
        return out
    }

    private static func extractContext(html: String, around offset: Int, span: Int) -> String {
        let ns = html as NSString
        let start = max(0, offset - span)
        let end = min(ns.length, offset + span)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
