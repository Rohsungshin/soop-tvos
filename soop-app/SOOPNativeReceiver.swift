import Foundation
import Network

// MARK: - SOOP 네이티브 수신기 (v1)
//
// SOOP 미디어 서버(캐시)에 TCP로 접속해 원본 H.264/AAC 패킷을 받는다.
// 프로토콜은 2026-10-03 사이클의 실측과 참조 구현(PERISU21/SOOPTV-1080p, 라이선스 없음 —
// 코드 미복제, 프로토콜 사실만 인용)에서 확보한 사실을 Swift로 재구현한 것이다.
//
// 프레이밍: 16B 리틀엔디언 헤더 [magic=0x202 : H][cmd : H][len : I][checksum(len^cmd^0x202) : I][0 : I]
// 핸드셰이크: 0xcb2e(broadNo, 0, qualityCode) → 0xcb2f(1) → 0xcb30(qualityCode, 0, 0, 2)
// 유지: 4초마다 0xcb30(qualityCode, nextFrame-30, 6) — 라이브 엣지보다 뒤로.
//       미래 프레임을 요청하면 연결이 영원히 멈춘다(참조 구현 주석 + 우리 문서 실측).
// 미디어: cmd 0xc748. 에코(cmd 0x1bc4)는 받은 body를 그대로 돌려보낸다.
//
// 보안 원칙(변경 금지 — docs/20261003 §1-5, docs/20261010 §2-3):
//   • 이 수신기는 어떤 인증 정보도 보내지 않는다(쿠키·토큰·Referer 없음, getfc만 HTTP).
//   • 호출부(SOOPNativePlayerController)는 공개 방송으로 확인된 방송에만 이 수신기를 켠다.

enum SOOPNativeError: Error, LocalizedError {
    case assignmentFailed(String)
    case invalidServer
    case connectionFailed(Error)
    case handshakeRejected
    case mediaTimeout
    case protocolError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .assignmentFailed(let code): return "미디어 서버 할당 실패 (err_code=\(code))"
        case .invalidServer: return "미디어 서버 주소가 유효하지 않습니다"
        case .connectionFailed(let e): return "미디어 서버 연결 실패: \(e.localizedDescription)"
        case .handshakeRejected: return "미디어 서버가 핸드셰이크를 거부했습니다"
        case .mediaTimeout: return "16초간 새 프레임이 도착하지 않았습니다"
        case .protocolError(let m): return "프로토콜 오류: \(m)"
        case .cancelled: return "취소됨"
        }
    }
}

struct SOOPNativeAssignment {
    let host: String
    let port: UInt16
}

/// 화질 코드. 1080p=1, 720p=2만 유효하다(참조: 10=720p+360p 동시 요청은 mid-stream 해상도
/// 전환을 일으켜 재생이 깨진다 — 코드 미복제, 사실만 인용).
enum SOOPNativeQuality: Int {
    case p1080 = 1
    case p720 = 2

    var label: String { self == .p1080 ? "1080p" : "720p" }
}

final class SOOPNativeReceiver {

    /// 미디어 프레임 하나(0xc748 body 전체). 먹서가 필드를 해석한다.
    typealias MediaHandler = (Data) -> Void
    typealias FailureHandler = (SOOPNativeError) -> Void

    private let queue = DispatchQueue(label: "soop.native.receiver")
    private var connection: NWConnection?
    private var pending = Data()
    private var keepAliveSource: DispatchSourceTimer?
    private var mediaSource: DispatchSourceTimer?
    private var running = false
    private var nextFrame: UInt64 = 0
    private let quality: SOOPNativeQuality
    /// 핸드셰이크에 쓰는 화질 코드 라벨(배지·메뉴용).
    var qualityLabel: String { quality.label }

    var onMedia: MediaHandler?
    var onFailure: FailureHandler?

    init(quality: SOOPNativeQuality = .p1080) {
        self.quality = quality
    }

    var isActive: Bool { running }

    // MARK: - 서버 할당 (HTTP, 인증 없음)

    /// getfc는 평문 HTTP이며 어떤 쿠키도 싣지 않는다. 응답은 쿼리스트링 형식(err_code=0&fc_ip=..&fc_port=..).
    static func assignServer(bjId: String, broadNo: String) async throws -> SOOPNativeAssignment {
        guard var comps = URLComponents(string: "http://affslb.sooplive.com:10035/getfc") else {
            throw SOOPNativeError.assignmentFailed("bad url")
        }
        comps.queryItems = [
            URLQueryItem(name: "bj", value: bjId),
            URLQueryItem(name: "bno", value: broadNo),
            URLQueryItem(name: "stype", value: "org"),
        ]
        guard let url = comps.url else { throw SOOPNativeError.assignmentFailed("bad url") }

        let request = URLRequest(url: url, timeoutInterval: 15)
        // Referer/Origin/User-Agent 미부여 — 이 경로에 인증 흔적을 남기지 않는다.

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let body = String(data: data, encoding: .utf8) else {
            throw SOOPNativeError.assignmentFailed("bad encoding")
        }
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { fields[String(kv[0])] = String(kv[1]) }
        }
        guard fields["err_code"] == "0" else {
            throw SOOPNativeError.assignmentFailed(fields["err_code"] ?? "?")
        }
        guard let ip = fields["fc_ip"], let portStr = fields["fc_port"], let port = UInt16(portStr), port > 0,
              isValidGlobalIPv4(ip) else {
            throw SOOPNativeError.invalidServer
        }
        return SOOPNativeAssignment(host: ip, port: port)
    }

    private static func isValidGlobalIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        // 사설/루프백/링크로컬 거부 — 서버가 내부망을 가리키면 뭔가 잘못된 것이다.
        if parts[0] == 10 || parts[0] == 127 || parts[0] == 0 { return false }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return false }
        if parts[0] == 192 && parts[1] == 168 { return false }
        if parts[0] == 169 && parts[1] == 254 { return false }
        return true
    }

    // MARK: - 프레이밍

    static func makePacket(command: UInt16, body: Data = Data()) -> Data {
        var p = Data(capacity: 16 + body.count)
        p.appendLE(UInt16(0x202))
        p.appendLE(command)
        p.appendLE(UInt32(body.count))
        p.appendLE(UInt32(0x202) ^ UInt32(command) ^ UInt32(body.count))
        p.appendLE(UInt32(0))
        p.append(body)
        return p
    }

    static func parseHeader(_ h: Data) -> (command: UInt16, length: Int)? {
        guard h.count >= 16 else { return nil }
        let magic = h.readLE(UInt16.self, at: 0)
        let command = h.readLE(UInt16.self, at: 2)
        let length = Int(h.readLE(UInt32.self, at: 4))
        let checksum = h.readLE(UInt32.self, at: 8)
        guard magic == 0x202, checksum == (UInt32(0x202) ^ UInt32(command) ^ UInt32(length)), length <= 8 * 1024 * 1024 else {
            return nil
        }
        return (command, length)
    }

    // MARK: - 연결 · 수신

    func start(assignment: SOOPNativeAssignment, broadNo: UInt64) {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let conn = NWConnection(
                host: NWEndpoint.Host(assignment.host),
                port: NWEndpoint.Port(rawValue: assignment.port)!,
                using: .tcp
            )
            connection = conn
            conn.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.sendHandshake(broadNo: broadNo)
                    self.receiveLoop()
                    self.startTimers()
                case .failed(let error):
                    self.fail(.connectionFailed(error))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    private func sendHandshake(broadNo: UInt64) {
        var b1 = Data(capacity: 12)
        b1.appendLE(UInt32(truncatingIfNeeded: broadNo))
        b1.appendLE(UInt32(0))
        b1.appendLE(UInt32(quality.rawValue))
        send(command: 0xcb2e, body: b1)

        var b2 = Data(capacity: 4)
        b2.appendLE(UInt32(1))
        send(command: 0xcb2f, body: b2)

        var b3 = Data(capacity: 16)
        b3.appendLE(UInt32(quality.rawValue))
        b3.appendLE(UInt32(0))
        b3.appendLE(UInt32(0))
        b3.appendLE(UInt32(2))
        send(command: 0xcb30, body: b3)
    }

    private func send(command: UInt16, body: Data) {
        guard let conn = connection else { return }
        conn.send(content: Self.makePacket(command: command, body: body), completion: .contentProcessed { [weak self] _ in
            _ = self // 전송 오류는 상태 핸들러/수신 타임아웃이 잡는다
        })
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.pending.append(data)
                self.drainPackets()
            }
            if let error = error {
                self.fail(.connectionFailed(error))
                return
            }
            if isComplete {
                self.fail(.protocolError("서버가 연결을 종료했습니다"))
                return
            }
            if self.running {
                self.receiveLoop()
            }
        }
    }

    private func drainPackets() {
        while running {
            guard pending.count >= 16, let (command, length) = Self.parseHeader(pending.prefix(16)) else { return }
            guard pending.count >= 16 + length else { return }
            let body = pending.subdata(in: 16..<(16 + length))
            pending.removeSubrange(0..<(16 + length))

            switch command {
            case 0xc748:
                // 다음 keep-alive 프레임 번호 — body@12 (미디어 시퀀스의 상위 카운터, 참조 구현과 동일 오프셋)
                if body.count >= 20 {
                    let seq = body.readLE(UInt64.self, at: 12)
                    if seq + 1 > nextFrame { nextFrame = seq + 1 }
                }
                markMedia()
                onMedia?(body)
            case 0x1bc4:
                send(command: command, body: body)   // 에코
            default:
                break   // 그 외 제어 패킷은 무시
            }
        }
    }

    // MARK: - 타이머

    private func startTimers() {
        // DispatchSourceTimer를 쓴다 — GCD 직렬 큐 스레드의 RunLoop는 기본적으로 돌지
        // 않아 Foundation Timer가 발동하지 않았다. keep-alive(0xcb30, 4초)가 서버로 전혀
        // 나가지 않으면 초기 3세그 버스트 뒤 연결이 끊긴다(2026-10-16 시뮬레이터 실측).
        let ka = DispatchSource.makeTimerSource(queue: queue)
        ka.schedule(deadline: .now() + 4, repeating: 4)
        ka.setEventHandler { [weak self] in
            guard let self = self, self.running else { return }
            var b = Data(capacity: 16)
            b.appendLE(UInt32(self.quality.rawValue))
            let back: UInt64 = self.nextFrame > 30 ? self.nextFrame - 30 : 0
            b.appendLE(back)
            b.appendLE(UInt32(6))
            self.send(command: 0xcb30, body: b)
        }
        ka.resume()
        keepAliveSource = ka

        let mt = DispatchSource.makeTimerSource(queue: queue)
        mt.schedule(deadline: .now() + SOOPNativeReceiver.mediaTimeoutSeconds, repeating: SOOPNativeReceiver.mediaTimeoutSeconds)
        mt.setEventHandler { [weak self] in
            guard let self = self, self.running else { return }
            if Date().timeIntervalSince(self.lastMediaAt) > SOOPNativeReceiver.mediaTimeoutSeconds {
                self.fail(.mediaTimeout)
            }
        }
        mt.resume()
        mediaSource = mt
    }

    static let mediaTimeoutSeconds: TimeInterval = 16
    private var lastMediaAt = Date()

    private func markMedia() {
        lastMediaAt = Date()
    }

    private func fail(_ error: SOOPNativeError) {
        queue.async { [self] in
            guard running else { return }
            running = false
            keepAliveSource?.cancel(); keepAliveSource = nil
            mediaSource?.cancel(); mediaSource = nil
            connection?.cancel()
            connection = nil
            let cb = onFailure
            DispatchQueue.main.async { cb?(error) }
        }
    }

    func stop() {
        fail(.cancelled)
        // cancelled는 콜백을 올리지 않는다: 정상 종료다.
        queue.async { [self] in
            onFailure = nil
            onMedia = nil
        }
    }
}

// MARK: - 리틀엔디언 헬퍼

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        guard count >= offset + MemoryLayout<T>.size else { return 0 }
        let v = subdata(in: offset..<(offset + MemoryLayout<T>.size)).withUnsafeBytes { $0.load(as: T.self) }
        return T(littleEndian: v)
    }
}
