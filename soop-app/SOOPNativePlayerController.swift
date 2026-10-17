import Foundation
import AVKit

// MARK: - 네이티브 재생 컨트롤러 (v1)
//
// SOOPNativeReceiver + TSMuxer + LocalHLSServer를 묶어 하나의 재생 세션으로 만든다.
// PlayerViewController는 이 컨트롤러의 playlistURL을 AVPlayer에 넘기기만 하면 된다.
//
// 보호 장치(docs/20261010 §2-3):
//   • start()는 게이트 통과 방송만 받는다(호출부 PlayerViewController가 StreamInfo로 검증).
//   • 실패(할당·연결·핸드셰이크·16초 무프레임)는 onFallback으로 알리고 스스로 정리된다.
//   • 세그먼트 3개가 쌓이기 전까지는 playlistURL을 노출하지 않는다(stall 0 — 2026-10-03 실측).

final class SOOPNativePlayerController: @unchecked Sendable {

    private let receiver: SOOPNativeReceiver
    private let muxer = TSMuxer()
    private let server = LocalHLSServer()
    private let queue = DispatchQueue(label: "soop.native.controller")
    private var started = false
    private var emittedSegments = 0

    /// 폴백 사유. 컨트롤러는 이미 정리된 상태로 넘어온다.
    var onFallback: ((SOOPNativeError) -> Void)?
    /// 플레이리스트가 처음 노출 가능해진 시점(세그먼트 3개 확보).
    var onPlaylistReady: (() -> Void)?

    /// 실제 디코딩 해상도 배지 갱신용(옵션). 먹서가 SPS를 볼 때 부른다.
    var onResolutionChange: ((Int, Int) -> Void)?

    init(quality: SOOPNativeQuality = .p1080) {
        receiver = SOOPNativeReceiver(quality: quality)
    }

    var isRunning: Bool { started && receiver.isActive }

    // MARK: - 세션

    func start(bjId: String, broadNo: String) {
        queue.async { [self] in
            guard !started else { return }
            started = true

            receiver.onMedia = { [weak self] body in
                guard let self = self else { return }
                self.muxer.feed(body)
            }
            receiver.onFailure = { [weak self] error in
                guard let self = self else { return }
                self.queue.async {
                    guard self.started else { return }
                    self.teardown()
                    let cb = self.onFallback
                    DispatchQueue.main.async {
                        if case .cancelled = error { } else { cb?(error) }
                    }
                }
            }
            muxer.onSegment = { [weak self] segment in
                guard let self = self else { return }
                self.server.append(segment: segment)
                self.emittedSegments += 1
                if self.emittedSegments == 3 {
                    let cb = self.onPlaylistReady
                    DispatchQueue.main.async { cb?() }
                }
            }

            server.start()

            Task {
                do {
                    let assignment = try await SOOPNativeReceiver.assignServer(bjId: bjId, broadNo: broadNo)
                    let number = UInt64(broadNo) ?? 0
                    guard number > 0 else { throw SOOPNativeError.protocolError("bad broadNo") }
                    queue.async { self.receiver.start(assignment: assignment, broadNo: number) }
                } catch {
                    queue.async {
                        guard self.started else { return }
                        self.teardown()
                        let cb = self.onFallback
                        let nativeError = (error as? SOOPNativeError) ?? .connectionFailed(error)
                        DispatchQueue.main.async { cb?(nativeError) }
                    }
                }
            }
        }
    }

    /// 방송 종료·사용자 종료. 콜백 없이 조용히 정리한다.
    func stop() {
        queue.async { [self] in
            guard started else { return }
            teardown()
        }
    }

    private func teardown() {
        receiver.stop()
        server.stop()
        started = false
    }

    // MARK: - 플레이어 인터페이스

    /// 3세그먼트 확보 + 리스너 준비가 되면 유효.
    var playlistURL: URL? {
        emittedSegments >= 3 ? server.playlistURL : nil
    }

    /// 원본 화질 라벨(배지·메뉴용).
    var qualityLabel: String { receiver.qualityLabel }
}
