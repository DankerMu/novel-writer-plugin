#!/usr/bin/env bash
#
# Deterministic-ish Chinese NER extractor (M3+ extension point).
#
# Usage:
#   run-ner.sh <chapter.md>
#
# Output:
#   stdout JSON (exit 0 on success)
#
# Exit codes:
#   0 = success (valid JSON emitted to stdout)
#   1 = validation failure (bad args, missing files)
#   2 = script exception (unexpected runtime error)
#
# Notes:
# - This script is designed to be fast and regression-friendly (stable output ordering).
# - It is NOT a perfect NER model. It emits candidates + evidence snippets for LLM verification.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: run-ner.sh <chapter.md>" >&2
  exit 1
fi

chapter_path="$1"

if [ ! -f "$chapter_path" ]; then
  echo "run-ner.sh: chapter file not found: $chapter_path" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "run-ner.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

if ! "$PYTHON" -c "import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)" 2>/dev/null; then
  echo "run-ner.sh: python3 >= 3.7 is required" >&2
  exit 2
fi

"$PYTHON" - "$chapter_path" <<'PY'
import json
import re
import sys
from dataclasses import dataclass, field
from typing import Callable, Dict, Iterable, List, Optional, Sequence, Set, Tuple, Union


def _die(msg: str, exit_code: int) -> None:
    sys.stderr.write(msg.rstrip() + "\n")
    raise SystemExit(exit_code)


def _truncate(s: str, limit: int = 160) -> str:
    s = s.strip()
    if len(s) <= limit:
        return s
    return s[: limit - 1] + "…"


def _strip_markdown_lines(lines: Sequence[str]) -> List[Tuple[int, str]]:
    """
    Best-effort strip of non-narrative markdown:
    - code fences
    - headings
    - horizontal rules
    """
    out: List[Tuple[int, str]] = []
    in_fence = False
    for idx, raw in enumerate(lines, start=1):
        line = raw.rstrip("\n")
        stripped = line.strip()

        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        if stripped.startswith("#"):
            continue
        if stripped in {"---", "___", "***"}:
            continue

        if not stripped:
            continue

        out.append((idx, line))
    return out


LOCATION_SUFFIXES = [
    "城",
    "镇",
    "村",
    "山",
    "岭",
    "谷",
    "林",
    "森林",
    "原",
    "原野",
    "宫",
    "殿",
    "府",
    "楼",
    "阁",
    "寺",
    "观",
    "院",
    "洞",
    "湖",
    "海",
    "江",
    "河",
    "关",
    "门",
    "岛",
    "州",
    "国",
    "郡",
    "坊",
    "街",
    "巷",
    "庄",
    "堡",
    "营",
    "港",
    "岸",
    "崖",
    "狱",
]

LOCATION_PREFIX_TRIGGERS = [
    # prepositions / verbs that often prefix a location mention
    "来到",
    "到了",
    "到达",
    "进入",
    "踏入",
    "走进",
    "走入",
    "抵达",
    "赶到",
    "前往",
    "奔向",
    "穿过",
    "越过",
    "飞入",
    "潜入",
    "驶入",
    "闯入",
    "返回",
    "回到",
    "离开",
    "在",
    "于",
    "往",
    "向",
    "朝",
]

SPEECH_VERBS = [
    "说道",
    "问道",
    "答道",
    "笑道",
    "冷笑",
    "喝道",
    "低声",
    "轻声",
    "沉声",
    "喃喃",
    "叹道",
    "怒道",
    "喊道",
]

SPEECH_ENDINGS = [
    "说道",
    "问道",
    "答道",
    "笑道",
    "喝道",
    "叹道",
    "怒道",
    "喊道",
    "道",
]

SPEECH_MODIFIERS = [
    "低声",
    "轻声",
    "沉声",
    "喃喃",
    "冷笑",
    "怒",
    "叹",
    "喝",
    "笑",
]

COMMON_SURNAMES_1: Set[str] = set(
    list(
        "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦尤许何吕施张孔曹严华金魏陶姜戚谢邹喻柏水窦章云苏潘葛奚范彭郎鲁韦昌马苗凤花方俞任袁柳酆鲍史唐费廉岑薛雷贺倪汤滕殷罗毕郝邬安常乐于时傅皮卞齐康伍余元卜顾孟平黄和穆萧尹姚邵湛汪祁毛禹狄米贝明臧计伏成戴谈宋茅庞熊纪舒屈项祝董梁杜阮蓝闵席季麻强贾路娄危江童颜郭梅盛林刁钟徐邱骆高夏蔡田樊胡凌霍虞万支柯昝管卢莫经房裘缪干解应宗丁宣贲邓郁单杭洪包诸左石崔吉龚程嵇邢滑裴陆荣翁荀羊於惠甄曲家封芮羿储靳汲邴糜松井段富巫乌焦巴弓牧隗山谷车侯宓蓬全郗班仰秋仲伊宫宁仇栾暴甘钭厉戎祖武符刘景詹束龙叶幸司韶郜黎蓟薄印宿白怀蒲邰从鄂索咸籍赖卓蔺屠蒙池乔阴欎胥能苍双闻莘党翟谭贡劳逄姬申扶堵冉宰郦雍却璩桑桂濮牛寿通边扈燕冀郏浦尚农温别庄晏柴瞿阎充慕连茹习宦艾鱼容向古易慎戈廖庾终暨居衡步都耿满弘匡国文寇广禄阙东欧殳沃利蔚越夔隆师巩厍聂晁勾敖融冷訾辛阚那简饶空曾毋沙乜养鞠须丰巢关蒯相查后荆红游竺权逯盖益桓公"
    )
)

COMMON_SURNAMES_2: Set[str] = {
    "欧阳",
    "司马",
    "上官",
    "诸葛",
    "东方",
    "南宫",
    "西门",
    "令狐",
    "皇甫",
    "尉迟",
    "公孙",
    "慕容",
    "长孙",
    "夏侯",
    "轩辕",
    "钟离",
    "宇文",
    "司徒",
    "司空",
    "太史",
    "端木",
    "申屠",
    "公羊",
    "澹台",
    "公冶",
    "宗政",
    "濮阳",
    "淳于",
    "单于",
    "太叔",
    "仲孙",
}

CHAR_STOPWORDS: Set[str] = {
    # very common generic mentions
    "主角",
    "众人",
    "众",
    "众妖",
    "众修",
    "人群",
    "大家",
    "所有人",
    "他们",
    "她们",
    "我们",
    "你们",
    "自己",
    "此时",
    "这一刻",
    "片刻",
    "不久",
    "然后",
    "忽然",
    "突然",
    "因为",
    "所以",
    "同时",
    "于是",
    "但是",
    "不过",
    "如果",
    "只是",
    "仍然",
    "仿佛",
    "宛如",
    "莫名",
}


TIME_RELATIVE = [
    "翌日",
    "次日",
    "当日",
    "当晚",
    "今夜",
    "昨夜",
    "清晨",
    "黎明",
    "天明",
    "天亮",
    "正午",
    "午后",
    "黄昏",
    "傍晚",
    "夜里",
    "午夜",
    "半夜",
    "三更",
    "片刻后",
    "不久后",
    "数日后",
    "几日后",
    "三日后",
]


EVENT_TRIGGERS = [
    "爆发",
    "开战",
    "大战",
    "决战",
    "身亡",
    "死亡",
    "失踪",
    "现身",
    "出现",
    "突破",
    "晋升",
    "崩塌",
    "坍塌",
    "倒塌",
    "结盟",
    "背叛",
    "叛变",
    "揭露",
    "曝光",
    "宣布",
    "宣告",
]


@dataclass
class Mention:
    line: int
    snippet: str


@dataclass
class Entity:
    text: str
    confidence: str
    mentions: List[Mention] = field(default_factory=list)


def _confidence_for_time(token: str) -> str:
    if re.search(r"[0-9一二三四五六七八九十百千]+(年|月|日|天|旬|更|刻)", token):
        return "high"
    if token in TIME_RELATIVE:
        return "medium"
    return "low"


def _confidence_for_location(token: str) -> str:
    for suf in LOCATION_SUFFIXES:
        if token.endswith(suf) and len(token) >= 3:
            return "high"
    if token.startswith("【") and token.endswith("】"):
        return "medium"
    return "low"


def _confidence_for_character(name: str, freq: int, speech_hits: int) -> str:
    if speech_hits >= 2:
        return "high"
    if freq >= 4:
        return "medium"
    return "low"


def _confidence_for_event(token: str) -> str:
    if any(token.endswith(t) for t in EVENT_TRIGGERS):
        return "medium"
    return "low"


def _add_mention(store: Dict[str, List[Mention]], key: str, line_no: int, snippet: str, cap: int = 5) -> None:
    mentions = store.setdefault(key, [])
    if len(mentions) >= cap:
        return
    snippet = _truncate(snippet)
    if any(m.line == line_no and m.snippet == snippet for m in mentions):
        return
    mentions.append(Mention(line=line_no, snippet=snippet))


def _sort_entities(entities: List[Entity]) -> List[Entity]:
    # stable ordering: by mention count desc, then by text
    return sorted(entities, key=lambda e: (-len(e.mentions), e.text))


def _extract_time_markers(lines: List[Tuple[int, str]]) -> Tuple[Dict[str, int], Dict[str, List[Mention]]]:
    counts: Dict[str, int] = {}
    mentions: Dict[str, List[Mention]] = {}

    patterns = [
        # explicit year + optional season
        re.compile(r"(?:第)?[0-9一二三四五六七八九十百千]{1,4}年(?:[春夏秋冬](?:初|中|末)?)?"),
        # month/day-ish
        re.compile(r"(?:第)?[0-9一二三四五六七八九十]{1,3}(?:月|日|天|旬)"),
        # relative tokens
        re.compile(r"(" + "|".join(map(re.escape, TIME_RELATIVE)) + r")"),
    ]

    for line_no, line in lines:
        for pat in patterns:
            for m in pat.findall(line):
                token = m if isinstance(m, str) else m[0]
                token = token.strip()
                if not token:
                    continue
                counts[token] = counts.get(token, 0) + 1
                _add_mention(mentions, token, line_no, line)

    return counts, mentions


def _extract_locations(lines: List[Tuple[int, str]]) -> Tuple[Dict[str, int], Dict[str, List[Mention]]]:
    counts: Dict[str, int] = {}
    mentions: Dict[str, List[Mention]] = {}

    suffix_re = "|".join(sorted(map(re.escape, LOCATION_SUFFIXES), key=len, reverse=True))
    pat = re.compile(rf"([\u3400-\u9fff]{{2,10}}(?:{suffix_re}))")
    bracket_pat = re.compile(r"【([^】]{2,12})】")

    weak_single = {"在", "于", "到", "往", "向", "朝"}
    strict_candidate_pat = re.compile(rf"^[\u3400-\u9fff]{{2,10}}(?:{suffix_re})$")
    loose_candidate_pat = re.compile(rf"^[\u3400-\u9fff]{{1,10}}(?:{suffix_re})$")

    def normalize(token: str) -> str:
        token = token.strip()
        if not token:
            return token

        # Strip the earliest trigger found in the token, but avoid
        # corrupting real location names that start with a preposition-like
        # character (e.g. "向阳村", "朝阳城", "于都城").
        best_pos: Optional[int] = None
        best_end: Optional[int] = None
        for trig in LOCATION_PREFIX_TRIGGERS:
            idx = token.find(trig)
            if idx == -1:
                continue
            end = idx + len(trig)
            if end >= len(token):
                continue

            candidate = token[end:]
            if not candidate:
                continue

            is_weak = len(trig) == 1 and trig in weak_single
            if is_weak:
                # Only strip weak single-char triggers when the remainder still
                # looks like a >=3-char place name (>=2 chars before suffix).
                if not strict_candidate_pat.match(candidate):
                    continue
            else:
                if not loose_candidate_pat.match(candidate):
                    continue

            if best_pos is None or idx < best_pos or (idx == best_pos and end > best_end):
                best_pos = idx
                best_end = end

        if best_end is not None and best_end < len(token):
            token = token[best_end:]

        return token

    for line_no, line in lines:
        for token in pat.findall(line):
            token = normalize(token)
            if not token:
                continue
            if not any(token.endswith(suf) for suf in LOCATION_SUFFIXES):
                continue
            counts[token] = counts.get(token, 0) + 1
            _add_mention(mentions, token, line_no, line)

        for inner in bracket_pat.findall(line):
            inner = inner.strip()
            if not inner:
                continue
            # only treat bracket tokens as location if it looks like one
            if any(inner.endswith(suf) for suf in LOCATION_SUFFIXES):
                token = f"【{inner}】"
                counts[token] = counts.get(token, 0) + 1
                _add_mention(mentions, token, line_no, line)

    return counts, mentions


def _extract_character_candidates(lines: List[Tuple[int, str]]) -> Tuple[Dict[str, int], Dict[str, int], Dict[str, List[Mention]]]:
    counts: Dict[str, int] = {}
    speech_hits: Dict[str, int] = {}
    mentions: Dict[str, List[Mention]] = {}

    # Prefer patterns like "林枫(沉声)道/说道/问道..." for high-confidence names.
    speech_suffix_re = "|".join(map(re.escape, SPEECH_ENDINGS))
    speech_mod_re = "|".join(map(re.escape, SPEECH_MODIFIERS))
    speech_name_pat = re.compile(
        rf"(?:^|(?<=[，。！？；：、\s\"「『（]))([\u3400-\u9fff]{{2,3}})(?:(?:{speech_mod_re}))?(?:{speech_suffix_re})"
    )

    token_pat = re.compile(r"([\u3400-\u9fff]{2,3})")

    for line_no, line in lines:
        # high-confidence: name + speech verb patterns
        for token in speech_name_pat.findall(line):
            token = token.strip()
            if not token or token in CHAR_STOPWORDS:
                continue
            counts[token] = counts.get(token, 0) + 2
            speech_hits[token] = speech_hits.get(token, 0) + 2
            _add_mention(mentions, token, line_no, line)

        has_speech = any(v in line for v in SPEECH_VERBS) or ("“" in line and "”" in line)
        for token in token_pat.findall(line):
            if token in CHAR_STOPWORDS:
                continue
            if any(token.endswith(suf) for suf in LOCATION_SUFFIXES):
                continue
            if re.match(r"^[春夏秋冬][初中末]?$", token) or re.match(r"^(?:初|仲|暮|孟)[春夏秋冬]$", token):
                continue
            if token.endswith("道") and token not in {"道长"}:
                continue
            if token[-1] in {"低", "轻", "沉", "喃", "冷", "怒", "叹", "喝", "笑"}:
                continue

            # surname heuristic: reduce noise from arbitrary 2-3 char phrases
            if len(token) == 2 and token[0] not in COMMON_SURNAMES_1:
                continue
            if len(token) == 3 and token[:2] not in COMMON_SURNAMES_2 and token[0] not in COMMON_SURNAMES_1:
                continue

            counts[token] = counts.get(token, 0) + 1
            if has_speech:
                speech_hits[token] = speech_hits.get(token, 0) + 1
            _add_mention(mentions, token, line_no, line)

    # filter: require min frequency
    kept = {k for k, v in counts.items() if v >= 2 or speech_hits.get(k, 0) >= 1}
    counts = {k: counts[k] for k in kept}
    # keep mentions only for kept tokens
    mentions = {k: mentions[k] for k in kept if k in mentions}
    speech_hits = {k: speech_hits.get(k, 0) for k in kept}

    return counts, speech_hits, mentions


def _extract_events(lines: List[Tuple[int, str]]) -> Tuple[Dict[str, int], Dict[str, List[Mention]]]:
    counts: Dict[str, int] = {}
    mentions: Dict[str, List[Mention]] = {}

    trigger_re = "|".join(map(re.escape, EVENT_TRIGGERS))
    pat = re.compile(rf"([\u3400-\u9fff]{{2,8}}(?:{trigger_re}))")

    for line_no, line in lines:
        for token in pat.findall(line):
            token = token.strip()
            if not token:
                continue
            if token in CHAR_STOPWORDS:
                continue
            counts[token] = counts.get(token, 0) + 1
            _add_mention(mentions, token, line_no, line)

    # limit extremely noisy outputs
    counts = {k: v for k, v in counts.items() if len(k) <= 18}
    mentions = {k: mentions[k] for k in counts.keys() if k in mentions}
    return counts, mentions


def _build_entities(
    counts: Dict[str, int],
    mentions: Dict[str, List[Mention]],
    confidence_fn: Union[Callable[[str], str], Callable[[str, int, int], str]],
    extra: Optional[Dict[str, int]] = None,
    limit: int = 30,
) -> List[Entity]:
    items: List[Tuple[str, int]] = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    out: List[Entity] = []
    for text, _cnt in items:
        if len(out) >= limit:
            break
        ms = mentions.get(text, [])
        conf = confidence_fn(text) if extra is None else confidence_fn(text, counts[text], extra.get(text, 0))
        out.append(Entity(text=text, confidence=conf, mentions=ms))
    return _sort_entities(out)


def main() -> None:
    chapter_path = sys.argv[1]

    try:
        with open(chapter_path, "r", encoding="utf-8-sig") as f:
            raw = f.read()
    except Exception as e:
        _die(f"run-ner.sh: failed to read chapter: {e}", 1)

    raw_lines = raw.splitlines()
    narrative_lines = _strip_markdown_lines(raw_lines)

    time_counts, time_mentions = _extract_time_markers(narrative_lines)
    loc_counts, loc_mentions = _extract_locations(narrative_lines)
    char_counts, char_speech_hits, char_mentions = _extract_character_candidates(narrative_lines)
    event_counts, event_mentions = _extract_events(narrative_lines)

    characters = _build_entities(char_counts, char_mentions, _confidence_for_character, extra=char_speech_hits, limit=30)
    locations = _build_entities(loc_counts, loc_mentions, _confidence_for_location, limit=30)
    time_markers = _build_entities(time_counts, time_mentions, _confidence_for_time, limit=20)
    events = _build_entities(event_counts, event_mentions, _confidence_for_event, limit=20)

    out = {
        "schema_version": 1,
        "chapter_path": chapter_path,
        "entities": {
            "characters": [
                {
                    "text": e.text,
                    "slug_id": None,
                    "confidence": e.confidence,
                    "mentions": [{"line": m.line, "snippet": m.snippet} for m in e.mentions],
                }
                for e in characters
            ],
            "locations": [
                {
                    "text": e.text,
                    "confidence": e.confidence,
                    "mentions": [{"line": m.line, "snippet": m.snippet} for m in e.mentions],
                }
                for e in locations
            ],
            "time_markers": [
                {
                    "text": e.text,
                    # TODO: implement actual time normalization; currently identity mapping
                    "normalized": e.text,
                    "confidence": e.confidence,
                    "mentions": [{"line": m.line, "snippet": m.snippet} for m in e.mentions],
                }
                for e in time_markers
            ],
            "events": [
                {
                    "text": e.text,
                    "confidence": e.confidence,
                    "mentions": [{"line": m.line, "snippet": m.snippet} for m in e.mentions],
                }
                for e in events
            ],
        },
    }

    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"run-ner.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
