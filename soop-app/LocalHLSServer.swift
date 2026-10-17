import Foundation
import Network

// MARK: - 루프백 HLS 서버 (v1)
//
// TSMuxer가 만든 세그먼트를 127.0.0.1에서 HLS로 제공한다. AVPlayer는 리소스 로더로
// 세그먼트를 공급받을 수 없다(CoreMediaError -12881 — 2026-10-03 §1-4 실측)므로
// 루프백 HTTP 리스너가 필수다.
//
// 바인딩: NWListener는 기본값과 acceptLocalOnly=true 모두 '*:port'에 붙는다(실측).
// requiredLocalEndpoint = 127.0.0.1을 줘야만 루프백 전용이 된다. tvOS에는 Local Network
// 보호가 없으므로(TN3179) 이 설정이 유일한 방어선이다. 변경 금지.
//
// 응답은 재생목록·세그먼트뿐. 임의 파일 서빙 없음, 경로 화이트리스트 고정.

final class LocalHLSServer {

    struct Playlist {
        var targetDurationMS = 1000
        var segments: [Int] = []      // 노출할 세그먼트 시퀀스(최근 N개)
        var mediaSequenceBase = 0
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "soop.localhls")
    private var segments: [Int: Data] = [:]
    private var playlist = Playlist()
    private let maxKept = 12          // 서버에 남길 최근 세그먼트 수
    private var maxSegDurationMS = 1000
    private var segDurationMS: [Int: Int] = [:]
    /// 플레이리스트에 노출하는 세그먼트 수. MEDIA-SEQUENCE는 '노출 창이 밀릴 때' 함께 올라가야
    /// 한다 — 노출은 6개인데 12개까지 base를 유지하면 같은 MEDIA-SEQUENCE의 엔트리가 바뀌어
    /// Apple StreamPlaylist가 -12312(URL not match)로 스트림을 끊는다(2026-10-16 시뮬레이터 실측).
    private let playlistWindow = 6
    private(set) var port: UInt16 = 0

    var onReady: (() -> Void)?

    // MARK: - 라이프사이클

    func start() {
        let params = NWParameters.tcp
        // 루프백 전용 바인드 — 필수(위 주석). allowLocalEndpointReuse로 재시작 충돌을 피한다.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 0)
        params.allowLocalEndpointReuse = true

        do {
            let l = try NWListener(using: params)
            listener = l
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn: conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.port = l.port?.rawValue ?? 0
                    self?.onReady?()
                }
            }
            l.start(queue: queue)
        } catch {
            print("[LocalHLS] listener failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [self] in
            segments.removeAll()
            playlist = Playlist()
        }
    }

    /// 재생 URL. 리스너 준비 전이면 nil.
    var playlistURL: URL? {
        port > 0 ? URL(string: "http://127.0.0.1:\(port)/index.m3u8") : nil
    }

    // MARK: - 세그먼트 공급

    func append(segment: TSMuxer.Segment) {
        queue.async { [self] in
            segments[segment.sequence] = segment.data
            if segment.durationMS > maxSegDurationMS { maxSegDurationMS = segment.durationMS }
            segDurationMS[segment.sequence] = segment.durationMS
            playlist.segments.append(segment.sequence)
            if playlist.segments.count > maxKept {
                let dropped = playlist.segments.removeFirst()
                segments.removeValue(forKey: dropped)
            }
            // 노출 창(6)을 벗어난 세그부터 MEDIA-SEQUENCE 진행 — 노출 목록과 base가 항상 일치.
            while playlist.segments.count > playlistWindow {
                playlist.mediaSequenceBase += 1
                playlist.segments.removeFirst()
            }
        }
    }

    // MARK: - HTTP 처리 (최소 구현)

    private func handle(conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(conn: conn)
    }

    private func receiveRequest(conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, let head = String(data: data.prefix(2048), encoding: .utf8),
               let path = head.split(separator: " ").dropFirst().first.map(String.init) {
                self.respond(conn: conn, path: path)
            } else if error == nil && !isComplete {
                self.receiveRequest(conn: conn)
            } else {
                conn.cancel()
            }
        }
    }

    private func respond(conn: NWConnection, path rawPath: String) {
        // 쿼리스트링 제거 + 경로 정규화(../ 차단)
        let path = (rawPath.split(separator: "?").first.map(String.init) ?? rawPath)
        guard !path.contains("..") else { conn.cancel(); return }

        if path == "/index.m3u8" {
            send(conn: conn, body: playlistData(), contentType: "application/vnd.apple.mpegurl")
        } else if path.hasPrefix("/seg-"), path.hasSuffix(".ts"),
                  let seqStr = path.dropFirst("/seg-".count).dropLast(3).data(using: .ascii),
                  let seq = Int(String(data: seqStr, encoding: .ascii) ?? ""),
                  let body = segments[seq] {
            send(conn: conn, body: body, contentType: "video/mp2t")
        } else {
            let notFound = "404".data(using: .utf8) ?? Data()
            send(conn: conn, body: notFound, contentType: "text/plain", status: "404 Not Found")
        }
    }

    private func playlistData() -> Data {
        var lines: [String] = ["#EXTM3U", "#EXT-X-VERSION:3",
                               "#EXT-X-TARGETDURATION:\(max(1, (maxSegDurationMS + 999) / 1000))",
                               "#EXT-X-MEDIA-SEQUENCE:\(playlist.mediaSequenceBase)"]
        for seq in playlist.segments.suffix(playlistWindow) {
            lines.append(String(format: "#EXTINF:%.3f,", Double(segDurationMS[seq] ?? maxSegDurationMS) / 1000.0))
            lines.append("seg-\(seq).ts")
        }
        return lines.joined(separator: "\n").appending("\n").data(using: .utf8) ?? Data()
    }

    private func send(conn: NWConnection, body: Data, contentType: String, status: String = "200 OK") {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var out = head.data(using: .utf8) ?? Data()
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
