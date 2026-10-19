-- Libs/ForeverLFG/Lang/koKR.lua
-- Korean for the chat parser: Korean players post on Forever's English
-- shards (found in game), in Hangul, with the dungeons' Korean names and
-- nicknames ("성불", "통곡", "폐광"), the recruiting words ("모셔요",
-- "구합니다", "가실 분"), roles with their counts written on ("탱1", "딜2").
-- Korean writes words together ("통곡가실"), so phrases match anywhere in
-- a line (the parser does that for every non-Latin script).
-- Tuned on recorded chat (2026-10-15: 67 Korean lines, /suu probe lfg
-- record, tools/lfg_parse.lua --lang koKR); only names that are certain;
-- what players type besides them grows with more recorded lines.

local _, ns = ...
local LFG = ns.LFG

-- Roles with a count written on ("탱1", "딜 2", "힐러1"): that many open.
-- Whole words only (Lua's "?" would apply to one byte of a Hangul letter).
local COUNTED = { { "탱커님", "tank" }, { "탱커", "tank" }, { "탱", "tank" }, { "힐러님", "healer" }, { "힐러", "healer" },
                  { "힐", "healer" }, { "딜러님", "damage" }, { "딜러", "damage" }, { "딜", "damage" } }

LFG.Lang.Register("koKR", {
    script = "hangul",
    words = {
        -- a group looking for players: "모셔요" (we welcome), "구합니다"
        -- (we're looking for), "가실 분" (who'll come along)
        group = { "모셔요", "모십니다", "모십니당", "모심니다", "모심", "모셔", "구합니다", "구해요", "구함",
                  "급구", "구인", "가실분", "가실 분", "가시는분", "가시는 분", "가실", "오실분", "오실 분", "오시면 바로 출발",
                  "바로출발", "바로 출발" },
        -- a player looking for a group: "파티 구해요" (looking for a party),
        -- "껴주세요" (let me in), "갑니다" (I'm going to …)
        player = { "파티 구합니다", "파티 구해요", "파티 구함", "팟 구해요", "팟 구함", "자리 있나요",
                   "자리있나요", "껴주세요", "껴 주세요", "데려가 주세요", "데려가주세요", "구직", "갑니다", "갈게요" },
        -- not group content: guilds, trading, carries
        noise = { "길드원", "길드 초대", "길드 모집", "길드", "삽니다", "팝니다", "판매", "구매", "버스", "작업장" },
        roles = {
            tank = { "탱커님", "탱커", "탱", "방전" },
            healer = { "힐러님", "힐러", "힐", "신사", "회드" },
            damage = { "딜러님", "딜러", "원딜", "근딜", "캐스터", "딜" },
        },
        classes = {
            WARRIOR = { "전사" },
            PALADIN = { "성기사", "성기" },
            HUNTER = { "사냥꾼", "냥꾼" },
            ROGUE = { "도적", "도둑" },
            PRIEST = { "사제" },
            SHAMAN = { "주술사", "주술" },
            MAGE = { "마법사", "법사" },
            WARLOCK = { "흑마법사", "흑마" },
            DRUID = { "드루이드", "드루" },
        },
    },
    -- counts written on a role, and a player's level before their class
    -- ("22 사제 통곡의동굴 갑니다")
    Extract = function(hay, r, hits, norm)
        local open = 0
        local text = norm
        for _, c in ipairs(COUNTED) do
            text = text:gsub(c[1] .. " ?(%d)", function(n)
                open = open + tonumber(n)
                r.roles[c[2]] = true
                return " "
            end)
        end
        if open > 0 then r.need = r.need or open; hits.group = true end
        if not r.level then
            for class, list in pairs({ WARRIOR = { "전사" }, PALADIN = { "성기사" }, HUNTER = { "사냥꾼" },
                                       ROGUE = { "도적" }, PRIEST = { "사제" }, SHAMAN = { "주술사" },
                                       MAGE = { "마법사", "법사" }, WARLOCK = { "흑마법사", "흑마" },
                                       DRUID = { "드루이드", "드루" } }) do
                for _, w in ipairs(list) do
                    local lvl = norm:match(" (%d%d?) ?" .. w)
                    if lvl and tonumber(lvl) <= 70 then
                        r.level = { tonumber(lvl), tonumber(lvl) }
                        r.classes[class] = true
                    end
                end
            end
        end
    end,
    activities = {
        ["dungeon:rfc"] = { "성난불길의 협곡", "성난불길", "성불" },
        ["dungeon:wc"] = { "통곡의 동굴", "통곡의동굴", "통곡" },
        ["dungeon:dm"] = { "죽음의 폐광", "죽음의폐광", "폐광" },
        ["dungeon:sfk"] = { "그림자송곳니 성채", "그림자송곳니", "송곳니 성채", "송곳니", "그송" },
        ["dungeon:bfd"] = { "검은심연의 나락", "심연의 나락", "심연 나락", "심연나락", "심연", "검심" },
        ["dungeon:stocks"] = { "스톰윈드 지하감옥", "지하감옥" },
        ["dungeon:gnomer"] = { "놈리건" },
        -- "우리" alone is also "we": only the full name or "우리 가실"
        ["dungeon:rfk"] = { "가시덩굴 우리", "우리 가실", "우리가실" },
        ["dungeon:smgy"] = { "붉은십자군 수도원 묘지", "수도원 묘지", "묘지" },
        ["dungeon:smlib"] = { "붉은십자군 수도원 도서관", "수도원 도서관", "도서관" },
        ["dungeon:smarm"] = { "붉은십자군 수도원 무기고", "수도원 무기고", "무기고" },
        ["dungeon:smcath"] = { "붉은십자군 수도원 대성당", "수도원 대성당", "대성당" },
        ["dungeon:sm"] = { "붉은십자군 수도원", "붉은수도원", "수도원" },
        ["dungeon:rfd"] = { "가시덩굴 구릉" },
        ["dungeon:ulda"] = { "울다만" },
        ["dungeon:zf"] = { "줄파락" },
        ["dungeon:mara"] = { "마라우돈" },
        ["dungeon:st"] = { "아탈학카르 신전", "아탈학카르", "가라앉은 사원" },
        ["dungeon:brd"] = { "검은바위 나락" },
        ["dungeon:lbrs"] = { "검은바위 첨탑 하층", "첨탑 하층" },
        ["dungeon:ubrs"] = { "검은바위 첨탑 상층", "첨탑 상층" },
        ["dungeon:diremaul"] = { "혈투의 전장", "혈투" },
        ["dungeon:strat"] = { "스트라솔름", "스트라" },
        ["dungeon:scholo"] = { "스칼로맨스", "스칼로" },
        ["dungeon:lordaeron"] = { "로데론의 폐허", "로데론 폐허", "로데론" },
        ["dungeon:dalaran"] = { "달라란" },
        ["raid:mc"] = { "화산 심장부", "화산심장부", "화심" },
        ["raid:ony"] = { "오닉시아의 둥지", "오닉시아", "오닉" },
        ["raid:bwl"] = { "검은날개 둥지", "검은날개둥지", "검둥" },
        ["raid:zg"] = { "줄구룹" },
        ["raid:aq20"] = { "안퀴라즈 폐허" },
        ["raid:aq40"] = { "안퀴라즈 사원" },
        ["raid:naxx"] = { "낙스라마스", "낙스" },
        ["boss:azuregos"] = { "아주어고스" },
        ["boss:kazzak"] = { "카자크" },
        ["zone:wetlands"] = { "저습지" },
        ["zone:barrens"] = { "불모의 땅", "불모" },
        ["zone:ashenvale"] = { "잿빛 골짜기" },
        ["zone:stranglethorn"] = { "가시덤불 골짜기", "가시덤불" },
        ["zone:duskwood"] = { "그늘숲" },
        ["zone:westfall"] = { "서부 몰락지대" },
        ["zone:durotar"] = { "듀로타" },
        ["zone:mulgore"] = { "멀고어" },
        ["zone:arathi"] = { "아라시 고원" },
        ["zone:hillsbrad"] = { "힐스브래드 구릉지" },
        ["zone:tirisfal"] = { "티리스팔 숲" },
        ["zone:silverpine"] = { "은빛소나무 숲" },
    },
})
