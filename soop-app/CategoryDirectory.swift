import UIKit

// MARK: - SOOP 카테고리 디렉토리 (스크래핑 결과)
//
// `https://www.sooplive.com/directory/category` 페이지에서 스크래핑한 120개 카테고리.
// 각 카테고리는 SOOP가 정한 이름을 사용하고, 알려진 BJID 목록을 가진다.
// 카테고리 페이지가 client-side rendering이라 Swift에서 직접 fetch 불가 →
// 빌드 시 Chrome으로 사전 스크래핑한 BJID 풀을 하드코딩.

struct CategoryEntry {
    let name: String        // 사용자 표시용 한글 이름
    let emoji: String       // 카테고리 대표 이모지
    let bjIds: [String]     // 이 카테고리의 알려진 BJID들 (비어있으면 미지원)
}

enum CategoryDirectory {

    /// 그랜드 테프트 오토 V — 약 14만명 시청 1위 카테고리
    static let gtaBJIDs = [
        "khm11903","phonics1","rrvv17","devil0108","b13246","yuambo","spbabobj","joey1114",
        "gksdidqksxn","legendhyuk","243000","rkdakstlr911","yjkim5500","galsa","vlfvlf789",
        "dlsn9911","townboy","danchu17","wnstn0905","kymakyma","tjrdbs999","singgyul","vf3366",
        "bach023","jey422","sunglim001","actret","qn308dud","xodud1898","honeys2","cnsgkcnehd74",
        "he0901","jaeparkk","busky3","toocat030","gyeonjahee","nj8893","aa6232","030jjj",
        "patiiz","nmangoquince","yjk011599","girlbbo","aksen7833","kgoyangyeeee","joyjo2",
        "rhakdncjs90","sksgml16","candyrang00","lalapin","sie4yu","sl0724","gofl2237","cctvno",
        "maoruyakr","yeopuu","gkdlqk13","doormomo","kmj05317","zkwks4413"
    ]

    /// 토크/캠방
    static let talkBJIDs = [
        "wnnw","golaniyule0","juju0228","mj0128","pyh3646","feel0100","dearhal","nanajam",
        "roket0829","seosils2","0823kdh","suhi370erw","parang1995","suyeun0312","wannabe33",
        "kpcwjkill02","ayoona","siiyeon","dbsek28","sunaang","dlswldus107","daybymin","kmj87990",
        "kaja0011","lcy011027","viviana7","qpqpro","leeso0403","yujin0117","pon07131","tkxkd9187",
        "wnfkrhs","0929kelly","joahe2","jts0802","chocho12","seon9605","jeehyeoun","dhgdgf",
        "zbxlzzz","sdgk78","fall0715","gusdk2362","juju0081","gorh004","bc3yu2fl","gpgpgpgpgpgp",
        "rrrr4719","malguman","nanaringhi","lindao3o","star49","9hari8","wjddlsxo12","oosuoey",
        "jujuing","dlsgk1763","churros05","tls0308973","jmk5883"
    ]

    /// 버추얼 (버튜버)
    static let virtualBJIDs = [
        "viichan6","mygomiee","nangnan","yangdoki","9ambler","vcheong","choelssu","qweasd3456",
        "mawang0216","maluckitty","beemong","lilgochun","nwakdifl1","insome0319","alice427",
        "eze1017","rkqwlssus","toryvac","haroha","kyaang123","mingturn97","nslah830",
        "dnwnwjdqhr53","earlgre0u0","mocamu2","os3n0o","llangkko0429","nokcho999","navixx",
        "yourdarky","meuuu3","qqshid","17282486","chachki","lilith1211","yoonesaem","duvl123",
        "vllageserah","shaaee","jeongwazzang","youxhh","bureu2002","muse0116","callmeharuby",
        "mi0mi0","kjhh0029","ozan201","deliouswe","gosummer","manlebreadtv","idenq9","ooonae",
        "choiagain","chelseanya","sjsr4611","nyanyavkr2","ugameming","50loing","chibi12","eirene0326"
    ]

    /// 리그 오브 레전드
    static let lolBJIDs = [
        "leesh2148","choi15778","ansguswns519","xoals137","rlantnghks","pig2704","1004suna",
        "dkrn56","pokimasiso","son4069","ogm0905","killgusdnk","dudadi770","axiaxi","song1218",
        "dbdb56","dkcjfhrm","910317","naong2bbang","sirazz","skqhd823","mingee1030","pillzohwang",
        "wlal5857","yoma1515","kpsc3115","msfeather","aarisy","han00606","s425park","kdlwndudwow"
    ]

    /// 스타크래프트
    static let starcraftBJIDs = [
        "jaedong23","tjdeosks","kkmkhh1234","soju2022","seemin88","firebathero","jackhan8888",
        "jihoon002","rlekfu6","wlswn6565","qkrgkdms01","ehgmldud1233","snfjdro369","2meonjin",
        "forweourus","jiwooris2","ys9024","goni2677","diniowo","jooyoung0040","alaelddl97",
        "queenzu","wlgua7272","bwstar","wittyku","queen030","agah1106","tndkekdy","70jeontaekyu",
        "wjddmstj79","yuna1024","hby0724","owoouoowo","understay"
    ]

    /// PUBG: 배틀그라운드
    static let pubgBJIDs = [
        "lovely5959","gudcjf604","syfan12","park19734","na2un","sky2713","wkek1809","hyn8210",
        "damin0714","yuji0703","liloolil","doorosy","wkdghks99","suhee0051","airshowerse",
        "apaceh2401","leejo0526","ecec39","youngjjang96","goodi3355","dragonk21","love1uu",
        "yeonjin622","qw0949","bej5885","hylobhy","cococ11","ggobugi1312","bokchinuna","h37u0n2",
        "yyk3390","lima110","wlfuse","ssw6973"
    ]

    /// 서든어택
    static let suddenBJIDs = [
        "enlwlf1","gj4237","slayer","rlawlgns3530","poou123456","rmsgh7263","hikikojjang","khje741",
        "dhrehdwkqk12","fnvl777","sksvkeh89","dycc7683","oooooii","gkska1","minjing7892","dbgk05",
        "seulgi3796","dltudamls1","wendy975","lej2278","wndfud","cnpswnd","yoon2233","x5004j",
        "hahb419","mcgh1000","hanm4601","gmldyd7895","leesol3278","hiru234","knhl6310","rlatnals12",
        "duswl342","wnslttm123"
    ]

    /// 먹방/쿡방
    static let mukbangBJIDs = [
        "alwl1047","eunz1nara","ssy06072","chltjdud0519","kingblue1","saw23ddwdj","n4n4aas",
        "chocochanel","enzon3028","d3dz91","2boo2boo","wkdalgusrla","qnldkq","gnsdn93","solve1004",
        "ssoollac","woorim0210","semosemo77","uni0627","testzomo","min2282","yhs3805","gusdn88",
        "hbtfidi","kmykim","kbs824","dbstjd9866","sojj88","jinhae81","kkm4957","ghddudghk486",
        "kfhsuwb007","ksung6537","nopenjjun112"
    ]

    /// 취미
    static let hobbyBJIDs = [
        "eunyoung1238","hrlim95","fiqarm","lhtlgm","hjeon234","kakaak2457","000609","mudexxx",
        "zxy008","kwindowindo","music1220","letter0624","quswldms0214","ljs980718","tlsdudrb321",
        "korea38388","dksakwhs","aiongosu","jhpark8002","21ccybwer","gkstjdtn102","pjm0860",
        "sung5099","krlawjddma77","goaway1004","inylee","jh05114","mynopk1579","nnko8456","rpal00",
        "wjdgns5906","worhkd12","arbitraryekr","aksdnekd1"
    ]

    /// 주식
    static let stockBJIDs = [
        "rlatldgus","hipiii","dlqudgk1227","ovoa3316","napunzzell","eunho50","supersuper79",
        "gmlwjd1723","iianzz"
    ]

    /// 뮤직/댄스
    static let musicDanceBJIDs = [
        "hwt1014","m0m0313","asq1177","tmdgns777","dockyong","ssongdani","rlaal6130","woo191404",
        "ehdqobig89","euebie","seuls2","tlsgml9394","bjinoa","youb611","rosehcoi95","hanb1128",
        "hongkh1004","midi0405","tismdp","ycl2039","yh102756","asda9789","aoejd7958","kimpooh0707",
        "dhfdls44444","jby0037","sumini10","geegooin86","s0ngaji123","sky7231","wkdtjdzz1",
        "a9fdxyw9wfs","kimzero","opopo1112"
    ]

    /// 발로란트
    static let valorantBJIDs = [
        "t3xturekr","dobby1031","bks04192","baeksoon2","poos69","kahwa07","viperdemon","dbsthdus111",
        "djfrha","jinsol6030","kangjw0324","dhtndk11","sk7442","psi050217","ghkdus05","mirieregulus",
        "wg1646","karieshug","dndnqlql","jeongjago","ctrotcs000","tnqlsdlwlfhd","sharena3466",
        "wnsdn1219","gus9107","hyepngseok63","gooriv","qlsdk046","ehdms0802","ghwnstkwk","jkh0294",
        "jss1542","wjdqhfl123","donguk13"
    ]

    /// SOOP에서 스크래핑한 120개 카테고리. emoji는 직접 매핑.
    /// BJID 풀이 있는 카테고리는 라이브 목록 표시 가능, 비어있으면 "준비 중".
    static let all: [CategoryEntry] = [
        // 인기 게임
        CategoryEntry(name: "그랜드 테프트 오토 V", emoji: "🚗", bjIds: gtaBJIDs),
        CategoryEntry(name: "토크/캠방",          emoji: "🎙",  bjIds: talkBJIDs),
        CategoryEntry(name: "버추얼",             emoji: "🦄",  bjIds: virtualBJIDs),
        CategoryEntry(name: "당구",               emoji: "🎱",  bjIds: []),
        CategoryEntry(name: "스타크래프트",       emoji: "⚔️",  bjIds: starcraftBJIDs),
        CategoryEntry(name: "PUBG: 배틀그라운드", emoji: "🔫",  bjIds: pubgBJIDs),
        CategoryEntry(name: "서든어택",           emoji: "💥",  bjIds: suddenBJIDs),
        CategoryEntry(name: "리그 오브 레전드",   emoji: "🏆",  bjIds: lolBJIDs),
        CategoryEntry(name: "메이플스토리 월드", emoji: "🍁",  bjIds: []),
        CategoryEntry(name: "종합게임",           emoji: "🎮",  bjIds: []),
        // 기타
        CategoryEntry(name: "취미",               emoji: "🎨",  bjIds: hobbyBJIDs),
        CategoryEntry(name: "주식",               emoji: "📈",  bjIds: stockBJIDs),
        CategoryEntry(name: "여행",               emoji: "✈️",  bjIds: []),
        CategoryEntry(name: "천원돌파 그렌라간", emoji: "💎",  bjIds: []),
        CategoryEntry(name: "발로란트",           emoji: "🎯",  bjIds: valorantBJIDs),
        CategoryEntry(name: "전략적 팀 전투",     emoji: "♟",   bjIds: []),
        CategoryEntry(name: "메이플스토리",       emoji: "🍃",  bjIds: []),
        CategoryEntry(name: "먹방/쿡방",          emoji: "🍔",  bjIds: mukbangBJIDs),
        CategoryEntry(name: "뮤직/댄스",          emoji: "🎵",  bjIds: musicDanceBJIDs),
        CategoryEntry(name: "마인크래프트",       emoji: "🧱",  bjIds: []),
        CategoryEntry(name: "음악 스트리밍",      emoji: "🎧",  bjIds: []),
        CategoryEntry(name: "FC 온라인",          emoji: "⚽️", bjIds: []),
        CategoryEntry(name: "암호화폐",           emoji: "🪙",  bjIds: []),
        CategoryEntry(name: "아이온 2",           emoji: "⚡️", bjIds: []),
        CategoryEntry(name: "러스트",             emoji: "🔧",  bjIds: []),
        CategoryEntry(name: "더빙/라디오",        emoji: "📻",  bjIds: []),
        CategoryEntry(name: "리니지 클래식",      emoji: "🗡",  bjIds: []),
        CategoryEntry(name: "중립",               emoji: "⚾️", bjIds: []),
        CategoryEntry(name: "아키텍트",           emoji: "🏰",  bjIds: []),
        CategoryEntry(name: "월드 오브 워크래프트", emoji: "🛡", bjIds: []),
        CategoryEntry(name: "메이저",             emoji: "📺",  bjIds: []),
        CategoryEntry(name: "로스트아크",         emoji: "🌟",  bjIds: []),
        CategoryEntry(name: "스페셜포스",         emoji: "🎖",  bjIds: []),
        CategoryEntry(name: "오버워치",           emoji: "🦸",  bjIds: []),
        CategoryEntry(name: "테일즈런너",         emoji: "🏃",  bjIds: []),
        CategoryEntry(name: "시사",               emoji: "📰",  bjIds: []),
        CategoryEntry(name: "서브노티카 2",       emoji: "🌊",  bjIds: []),
        CategoryEntry(name: "스타크래프트 II",    emoji: "🛸",  bjIds: []),
        CategoryEntry(name: "YTN LIVE",          emoji: "📡",  bjIds: []),
        CategoryEntry(name: "워크래프트 III",     emoji: "🐉",  bjIds: []),
        CategoryEntry(name: "천하제일상 거상",    emoji: "💰",  bjIds: []),
        CategoryEntry(name: "리니지",             emoji: "🔮",  bjIds: []),
        CategoryEntry(name: "토크/분석",          emoji: "🗣",  bjIds: []),
        CategoryEntry(name: "레트로게임",         emoji: "👾",  bjIds: []),
        CategoryEntry(name: "승리의 여신: 니케",  emoji: "✨",  bjIds: []),
        CategoryEntry(name: "KIA",               emoji: "🐯",  bjIds: []),
        CategoryEntry(name: "모바일 종합게임",    emoji: "📱",  bjIds: []),
        CategoryEntry(name: "던전앤파이터",       emoji: "🐲",  bjIds: []),
        CategoryEntry(name: "지식",               emoji: "📚",  bjIds: []),
        CategoryEntry(name: "낚시/아웃도어",      emoji: "🎣",  bjIds: []),
        CategoryEntry(name: "카트라이더 러쉬플러스", emoji: "🏎", bjIds: []),
        CategoryEntry(name: "명조: 워더링 웨이브", emoji: "🌪", bjIds: []),
        CategoryEntry(name: "미술",               emoji: "🖼",  bjIds: []),
        CategoryEntry(name: "도타2",              emoji: "🦅",  bjIds: []),
        CategoryEntry(name: "운세",               emoji: "🔮",  bjIds: []),
        CategoryEntry(name: "디아블로 II",        emoji: "👹",  bjIds: []),
        CategoryEntry(name: "철권 8",             emoji: "🥊",  bjIds: []),
        CategoryEntry(name: "연합뉴스",           emoji: "📻",  bjIds: []),
        CategoryEntry(name: "프리스타일",         emoji: "🏀",  bjIds: []),
        CategoryEntry(name: "펫방",               emoji: "🐶",  bjIds: []),
        CategoryEntry(name: "자습",               emoji: "📝",  bjIds: []),
        CategoryEntry(name: "마비노기 모바일",    emoji: "🌸",  bjIds: []),
        CategoryEntry(name: "아이온",             emoji: "👼",  bjIds: []),
        CategoryEntry(name: "TV CHOSUN",         emoji: "📺",  bjIds: []),
        CategoryEntry(name: "마인드 스포츠",      emoji: "♠️",  bjIds: []),
        CategoryEntry(name: "바람의나라",         emoji: "🌬",  bjIds: []),
        CategoryEntry(name: "검정고무신",         emoji: "👞",  bjIds: []),
        CategoryEntry(name: "Once Human",        emoji: "🌍",  bjIds: []),
        CategoryEntry(name: "JTBC",              emoji: "📺",  bjIds: []),
        CategoryEntry(name: "리니지M",            emoji: "📱",  bjIds: []),
        CategoryEntry(name: "델타포스",           emoji: "🪖",  bjIds: []),
        CategoryEntry(name: "해외주식",           emoji: "💵",  bjIds: []),
        CategoryEntry(name: "아크 레이더스",      emoji: "🚁",  bjIds: []),
        CategoryEntry(name: "로블록스",           emoji: "🧊",  bjIds: []),
        CategoryEntry(name: "파이널 판타지 14",   emoji: "🌹",  bjIds: []),
        CategoryEntry(name: "피트니스",           emoji: "💪",  bjIds: []),
        CategoryEntry(name: "R.E.P.O.",         emoji: "👻",  bjIds: []),
        CategoryEntry(name: "종교",               emoji: "🕊",  bjIds: []),
        CategoryEntry(name: "마구마구",           emoji: "⚾️", bjIds: []),
        CategoryEntry(name: "LCK",               emoji: "🏆",  bjIds: []),
        CategoryEntry(name: "바이오하자드 레퀴엠", emoji: "🧟", bjIds: []),
        CategoryEntry(name: "버블파이터",         emoji: "💧",  bjIds: []),
        CategoryEntry(name: "데드 바이 데이라이트", emoji: "🪦", bjIds: []),
        CategoryEntry(name: "사이퍼즈",           emoji: "🌀",  bjIds: []),
        CategoryEntry(name: "프리미어리그",       emoji: "🏟",  bjIds: []),
        CategoryEntry(name: "이터널 리턴",        emoji: "♾",   bjIds: []),
        CategoryEntry(name: "디아블로 IV",        emoji: "🔥",  bjIds: []),
        CategoryEntry(name: "월드 오브 워쉽",     emoji: "🚢",  bjIds: []),
        CategoryEntry(name: "슬레이 더 스파이어 2", emoji: "🃏", bjIds: []),
        CategoryEntry(name: "노래방",             emoji: "🎤",  bjIds: []),
        CategoryEntry(name: "코어 키퍼",          emoji: "⛏",   bjIds: []),
        CategoryEntry(name: "더 킹 오브 파이터즈 98", emoji: "🥋", bjIds: []),
        CategoryEntry(name: "디아블로 III",       emoji: "😈",  bjIds: []),
        CategoryEntry(name: "모여봐요 동물의 숲", emoji: "🌳",  bjIds: []),
        CategoryEntry(name: "프라시아 전기",      emoji: "🌌",  bjIds: []),
        CategoryEntry(name: "스트리트 파이터 6",  emoji: "👊",  bjIds: []),
        CategoryEntry(name: "스플릿 픽션",        emoji: "🎬",  bjIds: []),
        CategoryEntry(name: "명일방주: 엔드필드", emoji: "🌠",  bjIds: []),
        CategoryEntry(name: "MBN",               emoji: "📺",  bjIds: []),
        CategoryEntry(name: "서머너즈 워",        emoji: "🐉",  bjIds: []),
        CategoryEntry(name: "라그나로크 온라인",  emoji: "🗿",  bjIds: []),
        CategoryEntry(name: "붉은사막",           emoji: "🏜",  bjIds: []),
        CategoryEntry(name: "다크에덴",           emoji: "🌑",  bjIds: []),
        CategoryEntry(name: "이스케이프 프롬 타르코프", emoji: "🎒", bjIds: []),
        CategoryEntry(name: "카운터 스트라이크 온라인", emoji: "🎯", bjIds: []),
        CategoryEntry(name: "파생",               emoji: "📊",  bjIds: []),
        CategoryEntry(name: "WWE",               emoji: "🤼",  bjIds: []),
        CategoryEntry(name: "카운터 스트라이크 2", emoji: "💣", bjIds: []),
        CategoryEntry(name: "크레이지 아케이드",  emoji: "💥",  bjIds: []),
        CategoryEntry(name: "아이작의 번제",      emoji: "👶",  bjIds: []),
        CategoryEntry(name: "삼국지 14",          emoji: "🏯",  bjIds: []),
        CategoryEntry(name: "어쌔신 크리드 섀도우스", emoji: "🥷", bjIds: []),
        CategoryEntry(name: "모터스포츠",         emoji: "🏁",  bjIds: []),
        CategoryEntry(name: "포켓몬스터 스칼렛/바이올렛", emoji: "⚡️", bjIds: []),
        CategoryEntry(name: "R2",                emoji: "🤖",  bjIds: []),
        CategoryEntry(name: "엘든 링",            emoji: "💍",  bjIds: []),
        CategoryEntry(name: "구스 구스 덕",       emoji: "🦆",  bjIds: []),
        CategoryEntry(name: "테일즈위버",         emoji: "📖",  bjIds: []),
        CategoryEntry(name: "프래그마타",         emoji: "🛰",  bjIds: []),
        CategoryEntry(name: "국내선물",           emoji: "💎",  bjIds: []),
    ]
}
