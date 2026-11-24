import Foundation

// MARK: - MPEG-TS 먹서 (v1)
//
// SOOP 캐시 패킷(0xc748 body)의 원본 H.264 Annex B / AAC ADTS를 TS 세그먼트로 재포장한다.
// 트랜스코딩은 없다. tvOS AVPlayer가 요구하는 조건은 2026-10-03 사이클 §1-4에서 실측했다:
//   • AUD(NAL 9)를 강제 삽입한다 — SOOP 스트림에는 AUD가 0개고, 없으면 readyToPlay에 도달하지 못한다.
//   • PAT/PMT는 매 세그먼트 시작에 넣는다 — 첫 세그먼트에만 두면 라이브 중간 합류가 실패한다.
//   • PCR은 불필요하다(있어도 무해).
//   • 3세그먼트를 확보한 뒤 재생을 시작하면 stall이 없다(플레이리스트 노출 시점 관리).
//
// 시간축: 패킷 dts(100ns 단위)에서 첫 도착값 − 1초를 원점으로 잡는다(오디오 512ms 묶음이
// 첫 영상 dts보다 먼저 올 수 있다 — 참조 구현의 관찰과 동일).
//
// 세그먼트 조립은 도착 순서가 아니라 타임스탬프 기준이다. 오디오 묶음(약 0.5초)은 묶음이 끝난 뒤에
// 보내져 같은 시각의 영상보다 약 0.47초 늦게 도착한다(2026-10-18 공개 방송 16개 실측). 경계 직전
// 묶음이 경계 뒤에 도착하므로, 세그를 IDR에서 바로 닫으면 그 묶음이 갈 곳이 없다 — 예전 구현은
// 이것을 버려 2초 세그마다 묶음 하나(오디오의 약 25%)를 잃었다. 경계 이전 오디오가 다 올 때까지
// 세그를 열어 두었다가 시각순으로 섞어 내보낸다.

final class TSMuxer {

    struct Segment {
        let data: Data
        let sequence: Int
        /// 세그먼트 실제 길이(ms) — EXTINF는 이 값으로. 실서버 1080p60은 keyint 간격이
        /// 2초에 가까워 세그가 2초가 되는데 EXTINF 1.0 고정이면 Apple이 세그를 불완전으로
        /// 보고 -12976으로 거부한다(2026-10-17 실측).
        let durationMS: Int
        /// 이 세그 앞에서 방송 송출이 다시 시작됐다 — 플레이리스트에 EXT-X-DISCONTINUITY를 붙인다.
        let discontinuity: Bool
    }

    private(set) var videoFrames = 0
    private(set) var audioFrames = 0
    private var duplicates = 0
    // -1 초기화(참조 구현과 동일 개념): 첫 패킷 seq=0도 중복으로 오판하지 않게.
    private var lastVideoSeq: UInt64 = UInt64.max
    private var lastAudioSeq: UInt64 = UInt64.max
    private var origin: UInt64?
    private var sps: Data?
    private var pps: Data?

    // TS 상태
    private var ccPAT: UInt8 = 0
    private var ccSDT: UInt8 = 0
    private var ccPMT: UInt8 = 0
    private var ccVideo: UInt8 = 0
    private var ccAudio: UInt8 = 0
    private let videoPID: UInt16 = 0x100
    private let audioPID: UInt16 = 0x101
    private let pmtPID: UInt16 = 0x1000
    private var wroteAudioConfig = false
    /// 오디오 PTS 단조 보장용(패킷 경계를 넘어 유지).
    private var lastAudioPTSTicks: Int64 = -1
    /// 마지막 비디오 dts(틱) — 100ns→틱 환산 반올림 역전 방지.
    private var lastVideoDtsTicks: UInt64 = 0
    private var sawFirstVideoDts = false

    // 세그먼트 상태
    /// 아직 세그먼트로 내보내지 않은 PES. ticks는 비디오 dts / 오디오 pts(90kHz).
    private struct PendingPES {
        let ticks: UInt64
        let isVideo: Bool
        let pes: Data
    }
    private var pendingPES: [PendingPES] = []
    /// 세그먼트 경계(IDR dts 틱). cuts[0]은 아직 내보내지 않은 가장 오래된 세그의 시작이다.
    private var cuts: [UInt64] = []
    /// 지금까지 받은 오디오 묶음의 최대 PTS. 오디오는 시각순으로 오므로 이 값이 경계를 넘으면
    /// 그 경계 이전 오디오는 전부 도착한 것이다.
    private var latestAudioTicks: UInt64?
    /// 오디오 대기 한도. 오디오가 끊긴 방송에서도 세그가 멈추지 않게, 영상이 경계를 이만큼 지나면
    /// 오디오를 더 기다리지 않고 닫는다.
    private static let audioWaitTicks: UInt64 = 2 * 90_000
    private var segmentIndex = 0
    /// 송출 재시작 뒤 첫 세그에 discontinuity를 실어야 하는지.
    private var pendingDiscontinuity = false

    /// 세그먼트 길이(초). 2026-10-03 실험에서 1초 세그먼트로 stall 0을 확인했다.
    var segmentDurationMS = 1000

    /// 완성된 세그먼트가 나올 때마다 호출된다(이미 이전 세그먼트는 닫혀 있다).
    var onSegment: ((Segment) -> Void)?

    // MARK: - 패킷 수신

    /// SOOPNativeReceiver가 준 0xc748 body 전체.
    func feed(_ body: Data) {
        guard body.count >= 69 else { return }
        let version = body.readLE16(at: 0)
        let headerSize = Int(body.readLE16(at: 2))
        let extensionSize = Int(body.readLE32(at: 4))
        let rawSize = Int(body.readLE32(at: 8))
        guard version == 1, headerSize >= 69 else { return }
        let start = headerSize + extensionSize
        guard start + rawSize <= body.count, rawSize > 0 else { return }

        let kind = body[40]
        let raw = body.subdata(in: start..<(start + rawSize))

        if kind == 73 || kind == 80 {
            let sequence = body.readLE64(at: 20)
            let dts = body.readLE64(at: 41)
            if isRestart(sequence: sequence, last: lastVideoSeq, resendWindow: 1000, dts100ns: dts) { restartTimeline() }
            guard lastVideoSeq == .max || sequence > lastVideoSeq else { duplicates += 1; return }
            lastVideoSeq = sequence
            let cts = Int32(truncatingIfNeeded: body.readLE64(at: 57))
            feedVideo(raw: raw, dts100ns: dts, cts100ns: cts)
        } else if kind == 65 {
            let sequence = body.readLE64(at: 20)
            let dts = body.readLE64(at: 41)
            if isRestart(sequence: sequence, last: lastAudioSeq, resendWindow: 100, dts100ns: dts) { restartTimeline() }
            guard lastAudioSeq == .max || sequence > lastAudioSeq else { duplicates += 1; return }
            lastAudioSeq = sequence
            feedAudio(raw: raw, dts100ns: dts)
        }
    }

    // MARK: - 송출 재시작
    //
    // BJ가 송출을 끊었다 다시 켜면 같은 연결로 시퀀스·프레임 번호·타임스탬프가 처음부터 다시 오고 해상도·
    // 샘플레이트도 바뀔 수 있다(2026-10-18 15분 실측: 영상 seq 170676→55, dts 2844초→2.3초,
    // 1080p60→720p30, 오디오 48k→44.1k). 예전엔 시퀀스 중복 검사가 이후 패킷을 전부 버려 화면이 멈추고
    // 소리가 다시 나오지 않았다(수신은 계속돼 16초 무수신 폴백도 걸리지 않음).
    // keep-alive 재전송은 영상 약 30·오디오 1~2개만 되돌아오므로 그보다 훨씬 큰 역행만 재시작으로 본다.

    private func isRestart(sequence: UInt64, last: UInt64, resendWindow: UInt64, dts100ns: UInt64) -> Bool {
        if last != .max, last > sequence, last - sequence > resendWindow { return true }
        // 원점(첫 dts − 1초)보다 이른 타임스탬프는 재전송으로 나올 수 없다 — 새 시간축이다.
        if let o = origin, dts100ns < o { return true }
        return false
    }

    /// 남은 내용을 내보내고 시간축을 새로 잡는다. 다음 세그는 EXT-X-DISCONTINUITY로 표시한다.
    private func restartTimeline() {
        finishSegment()
        pendingPES.removeAll()
        origin = nil
        sps = nil
        pps = nil
        lastVideoSeq = .max
        lastAudioSeq = .max
        lastAudioPTSTicks = -1
        lastVideoDtsTicks = 0
        sawFirstVideoDts = false
        latestAudioTicks = nil
        pendingDiscontinuity = segmentIndex > 0   // 아직 아무것도 안 내보냈으면 표시할 경계가 없다
    }

    // MARK: - 영상 (Annex B → PES)

    private func feedVideo(raw: Data, dts100ns: UInt64, cts100ns: Int32) {
        // 원점 = 첫 dts − 1초(10,000,000 × 100ns). 0.1초로 잡혀 있어 오디오가 영상보다 0.1초 넘게
        // 먼저 오는 방송에서 첫 오디오 PTS가 음수 → 0으로 잘렸다(2026-10-18 실측).
        if origin == nil { origin = dts100ns >= 10_000_000 ? dts100ns - 10_000_000 : 0 }
        // 90kHz 틱 직접 계산(100ns * 9 / 1000). ms 왕복 반올림이 PTS 겹침을 만들었다(2026-10-12 실측).
        let originTicks = origin! * 9 / 1000
        var dtsTicks = dts100ns * 9 / 1000 - originTicks
        if !sawFirstVideoDts { lastVideoDtsTicks = dtsTicks; sawFirstVideoDts = true }
        // cts도 dts와 같은 100ns 단위다(참조 구현 cts/10_000 = ms). 예전엔 9/10_000으로 환산해
        // B-frame 오프셋이 1/10이 됐고, B-frame 방송(공개 방송 16개 중 6개)에서 영상이
        // 표시 순서가 뒤섞인 채 오디오보다 최대 수십 ms 앞서 나왔다(2026-10-18 실측).
        var ptsTicks = dtsTicks + UInt64(truncatingIfNeeded: Int64(cts100ns) * 9 / 1000)
        // 서버 dts는 100ns 해상도 — 틱 환산 정수나눗셈에서 서로 다른 dts가 같은 틱이 되거나
        // 1틱 역전할 수 있다(2026-10-17 실측: 'dts 119 >= 118'). Apple은 1틱 역전도 거부한다.
        if dtsTicks <= lastVideoDtsTicks { dtsTicks = lastVideoDtsTicks + 1 }
        if ptsTicks < dtsTicks { ptsTicks = dtsTicks }   // B-frame도 dts 이전일 수 없다
        lastVideoDtsTicks = dtsTicks

        let nals = splitAnnexB(raw)
        var keyframe = false
        for nal in nals {
            let type = nal.isEmpty ? 0 : (nal[0] & 0x1f)
            if type == 7 { sps = nal }
            if type == 8 { pps = nal }
            if type == 5 { keyframe = true }
        }
        guard let s = sps, let p = pps else { return }   // SPS/PPS 도달 전까지는 먹지 않는다(참조와 동일)

        // 세그먼트 경계: 열린 세그가 길이를 채웠고 이번 프레임이 IDR → 이 프레임부터 새 세그먼트.
        // (경계를 '닫은 뒤 프레임'이 아니라 '닫는 시점의 IDR'로 잡아야 세그먼트 첫 프레임이 IDR가 된다.)
        if keyframe, cuts.last.map({ dtsTicks - $0 >= UInt64(segmentDurationMS) * 90 }) ?? true {
            cuts.append(dtsTicks)
        }
        guard !cuts.isEmpty else { return }   // 첫 IDR 전 프레임으로는 세그를 시작할 수 없다

        // AUD 없이는 AVPlayer가 재생을 시작하지 못한다(2026-10-03 실측). 모든 접근 단위 앞에 삽입.
        var pes = Data()
        pes.appendAnnexB(Data([0x09, 0xf0]))               // AUD, pic_type=any
        if keyframe {
            pes.appendAnnexB(s)
            pes.appendAnnexB(p)
        }
        for nal in nals {
            let type = nal.isEmpty ? 0 : (nal[0] & 0x1f)
            if type == 7 || type == 8 { continue }        // 위에서 이미 넣었다
            pes.appendAnnexB(nal)
        }

        // B-frame(cts≠0) 프레임만 PTS+DTS를 싣는다. B-frame 없는 프레임에 DTS 필드를
        // 강제로 싣으면 Apple mpeg2parser가 트랙 파싱 직후 -12976으로 죽는다
        // (2026-10-17 시뮬레이터 실측 — PTS만 싣는 순간 재생 개시).
        let hasBFrame = cts100ns != 0
        pendingPES.append(PendingPES(
            ticks: dtsTicks, isVideo: true,
            pes: pesPayload(data: pes, streamID: 0xe0, ptsTicks: ptsTicks, dtsTicks: hasBFrame ? dtsTicks : nil, unbounded: true)
        ))
        videoFrames += 1
        emitReadySegments()
    }

    // MARK: - 오디오 (ADTS → PES)

    private static let sampleRates: [Int] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]

    private func feedAudio(raw: Data, dts100ns: UInt64) {
        if origin == nil { origin = dts100ns >= 10_000_000 ? dts100ns - 10_000_000 : 0 }
        // 서버는 오디오를 512ms 묶음(여러 ADTS 프레임)으로 보낸다. ffmpeg TS도 묶음당 1 PES를
        // 쓴다 — 프레임별로 쪼개 PES마다 PTS를 주면 Apple mpeg2parser가 -12976으로 거부했다
        // (2026-10-16 tvOS 시뮬레이터 실측). 묶음 전체를 한 PES에 싣는다.
        let originTicks = origin! * 9 / 1000
        let baseTicks = Int64(dts100ns) * 9 / 1000 - Int64(originTicks)
        var ptsTicks = baseTicks
        if ptsTicks <= lastAudioPTSTicks { ptsTicks = lastAudioPTSTicks + 1 }   // 단조 보장
        lastAudioPTSTicks = ptsTicks
        audioFrames += 1
        let pts = UInt64(max(0, ptsTicks))
        // 아직 내보내지 않은 가장 오래된 세그보다 이른 오디오는 버린다. 첫 영상 이전 오디오가 여기에
        // 해당한다 — 세그 첫 비디오보다 앞선 오디오 PTS가 세그 안에 남으면 Apple mpeg2parser가
        // -12976으로 거부한다(2026-10-17 실서버 실측). 이후 세그는 오디오를 기다렸다 닫으므로 버릴 일이 없다.
        guard let oldestStart = cuts.first, pts >= oldestStart else { return }
        pendingPES.append(PendingPES(ticks: pts, isVideo: false,
                                     pes: pesPayload(data: raw, streamID: 0xc0, ptsTicks: pts, dtsTicks: nil)))
        latestAudioTicks = max(latestAudioTicks ?? 0, pts)
        emitReadySegments()
    }

    // MARK: - 세그먼트

    /// 영상 경계가 정해졌고 그 경계 이전 오디오도 다 온(또는 대기 한도를 넘긴) 세그를 순서대로 내보낸다.
    private func emitReadySegments() {
        while cuts.count >= 2 {
            let end = cuts[1]
            let audioArrived = (latestAudioTicks ?? 0) >= end
            let waitedEnough = lastVideoDtsTicks >= end + Self.audioWaitTicks
            guard audioArrived || waitedEnough else { return }
            emitSegment(start: cuts[0], end: end)
            cuts.removeFirst()
        }
    }

    /// [start, end) 시각의 PES를 시각순으로 섞어 세그먼트 하나로 내보낸다. 오디오 묶음은 시작 시각이 속한
    /// 세그에 통째로 들어간다(경계를 넘어 이어지는 부분은 다음 세그 앞쪽 영상과 겹쳐 재생된다).
    private func emitSegment(start: UInt64, end: UInt64) {
        var body = pendingPES.filter { $0.ticks < end }
        pendingPES.removeAll { $0.ticks < end }
        body.sort { ($0.ticks, $0.isVideo ? 0 : 1) < ($1.ticks, $1.isVideo ? 0 : 1) }
        var out = Data()
        out.append(contentsOf: pat())
        out.append(contentsOf: pmt())
        out.append(contentsOf: sdt())
        for p in body {
            if p.isVideo {
                out.append(tsPacketize(payload: p.pes, pid: videoPID, randomAccess: true, cc: &ccVideo, pcrTicks: p.ticks))   // 모든 비디오 PES에 PCR
            } else {
                out.append(tsPacketize(payload: p.pes, pid: audioPID, randomAccess: true, cc: &ccAudio))
            }
        }
        // 길이 = 다음 경계 − 이번 경계(실제 시각). 예전엔 마지막 프레임 길이만큼 짧게 적었다.
        onSegment?(Segment(data: out, sequence: segmentIndex, durationMS: Int((end - start) / 90), discontinuity: pendingDiscontinuity))
        pendingDiscontinuity = false
        segmentIndex += 1
    }

    /// 남은 내용을 모두 세그먼트로 내보낸다. 호출부가 방송 종료 등으로 강제로 닫을 때 쓴다.
    func finishSegment() {
        while cuts.count >= 2 {
            emitSegment(start: cuts[0], end: cuts[1])
            cuts.removeFirst()
        }
        guard let start = cuts.first, !pendingPES.isEmpty else { return }
        emitSegment(start: start, end: max(lastVideoDtsTicks, latestAudioTicks ?? 0) + 1)
        cuts.removeAll()
    }

    var hasEmittedAnySegment: Bool { segmentIndex > 0 }

    // MARK: - PSI CRC

    /// ISO/IEC 13818-1 CRC32-MPEG. Apple demuxer는 PSI CRC를 검증한다(2026-10-12 하니스 실측 —
    /// CRC 0이면 AVPlayer가 PAT를 폐기해 스트림을 발견하지 못했다). ffmpeg는 검증하지 않아 이전 하니스가 통과했다.
    static func psiCRC(_ section: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in section {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 {
                if crc & 0x8000_0000 != 0 {
                    crc = (crc << 1) ^ 0x04C1_1DB7
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    private static func beBytes(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }

    // MARK: - TS 패킷 생성

    private func pat() -> Data {
        var p = Data()
        // pointer_field는 wrap()이 packet[4]에 싣는다 — 여기 또 넣으면 이중 pointer로
        // section이 1바이트 밀려 CoreMedia(-12971)가 PAT/PMT를 폐기한다(2026-10-16 시뮬레이터 실측).
        var section: [UInt8] = [
            0x00, 0xb0, 0x0d,                             // table_id, section_syntax+length=13
            0x00, 0x01,                                   // transport_stream_id
            0xc1, 0x00, 0x00,                             // version/current, section 0, last 0
            0x00, 0x01,                                   // program_number 1
            UInt8((pmtPID >> 8) & 0x1f) | 0xe0, UInt8(pmtPID & 0xff),  // reserved(111)+PMT_PID 상위 5비트
        ]
        section += Self.beBytes(Self.psiCRC(section[...]))
        p.append(contentsOf: section)
        return wrap(payload: p, pid: 0, cc: &ccPAT, pointer: false)
    }

    /// SDT 최소형 — ffmpeg TS도 세그 첫 패킷에 싣는다(2026-10-17 대조 실측).
    private func sdt() -> Data {
        var section: [UInt8] = [
            0x42, 0xf0, 0x1d,                             // table_id=SDT actual, len=29(본체25+CRC4)
            0x00, 0x01, 0xc1, 0x00, 0x00,                 // tsid, version, sec, last
            0x00, 0x01, 0x00,                             // original_network_id, reserved
            0x00, 0x01,                                   // service_id 1
            0xfc, 0x00, 0x0c,                             // reserved+EIT flags, descriptors loop=12
            0x48, 0x0a,                                   // service_descriptor, len=10
            0x04, 0x53, 0x6f, 0x6f, 0x70,                 // provider "Soop"
            0x04, 0x6c, 0x69, 0x76, 0x65,                 // name "live"
        ]
        section += Self.beBytes(Self.psiCRC(section[...]))
        var p = Data()
        p.append(contentsOf: section)
        return wrap(payload: p, pid: 0x11, cc: &ccSDT, pointer: false)
    }

    /// PSI 패이로드를 단일 TS 패킷으로 싼다(184바이트 이내).
    /// 빈 공간은 adaptation field stuffing으로 막는다 — 0xFF를 payload 영역에 그대로 두면
    /// afc=1에서 Apple mpeg2parser가 가짜 후속 섹션으로 읽어 -12976을 낸다(2026-10-16 실측).
    private func wrap(payload: Data, pid: UInt16, cc: inout UInt8, pointer: Bool) -> Data {
        var packet = [UInt8](repeating: 0, count: 188)
        packet[0] = 0x47
        packet[1] = 0x40 | UInt8((pid >> 8) & 0x1f)   // PUSI
        packet[2] = UInt8(pid & 0xff)
        let n = min(payload.count, 183)
        // payload 183바이트 초과 시 AF 없이 pointer(1)+payload(183) = 184 꽉 참.
        if n >= 183 {
            packet[3] = 0x10 | (cc & 0x0f)
            packet[4] = 0x00                           // pointer_field=0
            for (i, b) in payload.prefix(183).enumerated() { packet[5 + i] = b }
        } else {
            // AF: [4]=AFlen, [5]=flags(0), [6...]=0xFF stuffing, payload는 AF 뒤
            packet[3] = 0x30 | (cc & 0x0f)             // AF + payload
            let leftover = 184 - 1 - n                 // pointer(1) + payload(n) 제외한 나머지
            packet[4] = UInt8(leftover - 1)
            packet[5] = 0
            for j in 6..<(4 + leftover) { packet[j] = 0xFF }
            packet[4 + leftover] = 0x00                // pointer_field=0
            let bytes = [UInt8](payload.prefix(n))
            for (i, b) in bytes.enumerated() { packet[5 + leftover + i] = b }
        }
        cc = (cc + 1) & 0x0f
        return Data(packet)
    }

    private func pmt() -> Data {
        var p = Data()
        // pointer_field는 wrap()이 담당(pat와 동일한 이중-pointer 결함 방지).
        var section: [UInt8] = [
            0x02, 0xb0, 0x17,                             // table_id=program_map, length=23
            0x00, 0x01,                                   // program_number
            0xc1, 0x00, 0x00,                             // version, section, last
            0xe0 | UInt8((videoPID >> 8) & 0x1f), UInt8(videoPID & 0xff),  // PCR_PID=video
            0xf0, 0x00,                                   // program_info_length=0
            // ES_PID 상위바이트는 reserved(111)+PID 상위 5비트 — 0xE0 마스크 없이 0x01로 두면
            // ffmpeg는 봐주지만 Apple mpeg2parser가 -12976으로 거부한다(2026-10-16 시뮬레이터 실측).
            0x1b, 0xe0 | UInt8((videoPID >> 8) & 0x1f), UInt8(videoPID & 0xff), 0xf0, 0x00,  // H.264
            0x0f, 0xe0 | UInt8((audioPID >> 8) & 0x1f), UInt8(audioPID & 0xff), 0xf0, 0x00,  // AAC ADTS
        ]
        section += Self.beBytes(Self.psiCRC(section[...]))
        p.append(contentsOf: section)
        return wrap(payload: p, pid: pmtPID, cc: &ccPMT, pointer: false)
    }

    /// PES 패킷(헤더 + payload)을 만든다.
    private func pesPayload(data: Data, streamID: UInt8, ptsTicks: UInt64, dtsTicks: UInt64?, unbounded: Bool = false) -> Data {
        var header = Data()
        header.append(contentsOf: [0x00, 0x00, 0x01, streamID])
        let pts = ptsTicks
        let needDTS = dtsTicks != nil
        let dts = dtsTicks ?? ptsTicks
        let headerDataLen: UInt8 = needDTS ? 10 : 5
        // PES_packet_length는 16비트 — 65,535를 넘는 AU(1080p IDR 등)는 규격상 0(미지정)으로
        // 둔다. 초과값을 그대로 싣으면 오버플로로 잘못된 길이가 기록돼 'PES packet size
        // mismatch' + Apple -12976 corrupt 처리가 된다(2026-10-17 실서버 1080p 실측).
        let computed = 3 + Int(headerDataLen) + data.count
        // 비디오 PES는 길이 미지정(0)으로 통일 — ffmpeg 라이브 muxer와 동일 형태.
        // 실측 plen을 싣으면 Apple mpeg2parser가 세그 파싱 직후 -12976으로 죽었다
        // (2026-10-17 실서버 1080p 실측: IDR만 0/나머지 실측 혼합에서 재현).
        let pesPacketLength = (unbounded || computed > 0xffff) ? 0 : computed
        header.append(contentsOf: [
            UInt8((pesPacketLength >> 8) & 0xff), UInt8(pesPacketLength & 0xff),
            0x80,               // '10' marker
            (needDTS ? 0xC0 : 0x80),  // PTS_DTS_flags: '11'(PTS+DTS) 또는 '10'(PTS만)
            headerDataLen,
        ])
        // ISO 13818-1 PTS/DTS 부호화: '0010' prefix(b0 상위 4bit) + 33bit + marker 비트.
        // prefix 누락 시 디먹서가 PTS를 폐기한다(2026-10-12 하니스 실측 — 첫 PTS가 0x1FFFFFFFF로 디코드됨).
        // PTS만 실을 때 PTS는 '0010'(0x21), PTS+DTS일 때는 PTS '0011'(0x31) + DTS '0001'(0x11)
        // — ISO 13818-1 2.4.3.7. DTS에 0x21을 쓰면 ffmpeg가 DTS 필드 전체를 폐기해 B-frame 스트림의 dts=pts로 오해한다.
        // PTS+DTS인데 PTS를 '0010'으로 두면 ffmpeg는 통과하지만 Apple mpeg2parser는 첫 세그에서 -12976으로
        // 거부해, B-frame 방송(공개 방송 16개 중 6개)은 네이티브 재생이 늘 CDN으로 넘어갔다(2026-10-18 시뮬레이터 실측).
        func tsBase(_ t: UInt64, prefix: UInt8 = 0x21) -> [UInt8] {
            let v = t & 0x1ffffffff           // 33bit
            let b0 = prefix | UInt8(truncatingIfNeeded: (v >> 29) & 0x0e)
            let b1 = UInt8(truncatingIfNeeded: (v >> 22) & 0xff)
            let b2 = UInt8(truncatingIfNeeded: ((v >> 15) & 0x7f) << 1) | 0x01
            let b3 = UInt8(truncatingIfNeeded: (v >> 7) & 0xff)
            let b4 = UInt8(truncatingIfNeeded: (v & 0x7f) << 1) | 0x01
            return [b0, b1, b2, b3, b4]
        }
        header.append(contentsOf: tsBase(pts, prefix: needDTS ? 0x31 : 0x21))
        if needDTS { header.append(contentsOf: tsBase(dts, prefix: 0x11)) }
        header.append(data)
        return header
    }

    /// TS 패킷으로 쪼갠다( payload>184 bytes 시 adaptation field로 정렬).
    private func tsPacketize(payload: Data, pid: UInt16, randomAccess: Bool, cc: inout UInt8, pcrTicks: UInt64? = nil) -> Data {
        var out = Data(capacity: 188 * ((payload.count / 184) + 1))
        var offset = 0
        var first = true
        while offset < payload.count || first {
            var packet = [UInt8](repeating: 0, count: 188)
            packet[0] = 0x47
            packet[1] = UInt8((pid >> 8) & 0x1f) | (first ? 0x40 : 0)   // PUSI는 첫 패킷만
            packet[2] = UInt8(pid & 0xff)
            var bodyStart = 4
            let remaining = payload.count - offset
            // 마지막 패킷의 잔여 공간: adaptation field + 0xFF stuffing으로 채운다(ISO 13818-1 2.4.3.4).
            // 0으로 두면 ffmpeg mpegts 디먹서가 남은 바이트를 다음 PES 조각으로 오인해
            // 'channel element not allocated' 디코드 에러를 냈다(2026-10-12 실측).
            let last = remaining <= 184
            var chunk: Int
            if first && randomAccess, let pcrBase = pcrTicks {
                // AF: PCR(6B)+random_access — PMT가 PCR_PID=video(0x100)를 선언하는데 PCR이
                // 0개면 Apple mpeg2parser가 트랙 파싱 직후 -12976으로 죽는다(2026-10-17 실측).
                // ffmpeg TS도 모든 비디오 PES 시작 패킷에 PCR을 싣는다.
                packet[3] = 0x30 | (cc & 0x0f)   // adaptation+payload
                packet[4] = 7                     // AF length: [5..11] 플래그1+PCR6
                packet[5] = 0x50                  // PCR_flag + random_access_indicator
                packet[6] = UInt8((pcrBase >> 25) & 0xff)
                packet[7] = UInt8((pcrBase >> 17) & 0xff)
                packet[8] = UInt8((pcrBase >> 9) & 0xff)
                packet[9] = UInt8((pcrBase >> 1) & 0xff)
                packet[10] = UInt8(((pcrBase & 1) << 7) | 0x7e)   // reserved(6비트 전부 1)+ext 상위 1비트(0)
                packet[11] = 0x80                    // ext 하위 8비트(0)+marker
                bodyStart = 12
                chunk = min(remaining, 188 - bodyStart)
            } else if first && randomAccess {
                // 오디오: random_access만 싣는다. PCR은 PMT의 PCR_PID(비디오)에만 — 예전엔 오디오 PES마다
                // PCR=0을 실어 비디오 PCR 타임라인과 어긋난 값이 매 묶음 섞였다.
                packet[3] = 0x30 | (cc & 0x0f)
                packet[4] = 1
                packet[5] = 0x40                  // random_access_indicator
                bodyStart = 6
                chunk = min(remaining, 188 - bodyStart)
            } else if last {
                // AF: [4]=AFlen, [5]=flags(0), [6...]=0xFF stuffing — payload를 AF 뒤로 배치
                let cap = 184
                chunk = min(remaining, cap)
                let leftover = cap - chunk
                packet[3] = 0x10 | (cc & 0x0f)   // 기본 afc=1(디폴트 — leftover==0일 때 그대로)
                if leftover >= 2 {
                    packet[3] = 0x30 | (cc & 0x0f)
                    packet[4] = UInt8(leftover - 1)
                    packet[5] = 0
                    for j in 6..<(4 + leftover) { packet[j] = 0xFF }
                    bodyStart = 4 + leftover
                } else if leftover == 1 {
                    // 1바이트만 남으면 AF 없이 단일 stuffing 바이트(0xFF)를 쓸 수 없다 —
                    // afc=3은 AF 최소 2바이트 필요. 이 케이스는 afc=1 + payload 184로 마무리되지
                    // 않도록 chunk를 183으로 줄여 AF 2바이트 확보.
                    chunk -= 1
                    packet[3] = 0x30 | (cc & 0x0f)
                    packet[4] = 1; packet[5] = 0xFF
                    bodyStart = 6
                }
            } else {
                packet[3] = 0x10 | (cc & 0x0f)
                chunk = min(remaining, 184)
            }
            payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for i in 0..<chunk { packet[bodyStart + i] = raw[offset + i] }
            }
            out.append(contentsOf: packet)
            offset += chunk
            first = false
            cc = (cc + 1) & 0x0f
        }
        return out
    }

    // MARK: - 유틸

    private func ms(from100ns v: UInt64) -> Int {
        guard let o = origin else { return 0 }
        return v > o ? Int((v - o) / 10_000) : 0
    }

    private func splitAnnexB(_ data: Data) -> [Data] {
        var nals: [Data] = []
        var start = data.startIndex
        let idx = data.indices
        var i = data.startIndex
        var lastStart = data.startIndex
        while i < data.endIndex - 2 {
            if data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 {
                if i > lastStart {
                    nals.append(data.subdata(in: lastStart..<i))
                }
                lastStart = i + 3
                i += 3
            } else if data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 && i + 3 < data.endIndex && data[i + 3] == 1 {
                if i > lastStart {
                    nals.append(data.subdata(in: lastStart..<i))
                }
                lastStart = i + 4
                i += 4
            } else {
                i += 1
            }
        }
        _ = start
        start = idx.startIndex
        if lastStart < data.endIndex {
            nals.append(data.subdata(in: lastStart..<data.endIndex))
        }
        return nals.filter { !$0.isEmpty }
    }
}

private extension Data {
    mutating func appendAnnexB(_ nal: Data) {
        append(contentsOf: [0, 0, 0, 1])
        append(nal)
    }

    func readLE16(at offset: Int) -> UInt16 {
        guard count >= offset + 2 else { return 0 }
        return UInt16(self[startIndex + offset]) | (UInt16(self[startIndex + offset + 1]) << 8)
    }

    func readLE32(at offset: Int) -> UInt32 {
        guard count >= offset + 4 else { return 0 }
        return UInt32(self[startIndex + offset])
            | (UInt32(self[startIndex + offset + 1]) << 8)
            | (UInt32(self[startIndex + offset + 2]) << 16)
            | (UInt32(self[startIndex + offset + 3]) << 24)
    }

    func readLE64(at offset: Int) -> UInt64 {
        guard count >= offset + 8 else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(self[startIndex + offset + i]) << (8 * UInt64(i))
        }
        return v
    }
}

private extension UnsafeRawBufferPointer {
    func loadBytes(from offset: Int, count: Int) -> [UInt8] {
        guard offset + count <= count else { return [] }
        return [UInt8](self[startIndex + offset..<(startIndex + offset + count)])
    }
}
