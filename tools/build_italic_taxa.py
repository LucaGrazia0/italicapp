#!/usr/bin/env python3
"""ITALIC 8.0 structured taxon parser — v0.8.1."""
from urllib.request import Request,urlopen
from urllib.error import HTTPError,URLError
from html.parser import HTMLParser
from pathlib import Path
import html as htmllib, json, re

BASE="https://italic.units.it/index.php?num={}&procedure=taxonpage"
FIELD_LABELS=["Synonyms:","Distribution:","Description:","Note:","Growth form:",
 "Substrata:","Photobiont:","Reproductive strategy:","Commonnes-rarity:","pH of the substrata:","Solar irradiation:","Aridity:","Eutrophication:","Poleotolerance:","Altitudinal distribution:"]
BELT_LABELS=["Alpine belt:","Subalpine belt:","Oromediterranean belt:","Montane belt:",
 "Submediterranean belt:","Padanian area:","Humid submediterranean belt:",
 "Humid mediterranean belt:","Dry mediterranean belt:"]
SCALE_LABELS=["pH of the substrata","Solar irradiation","Aridity","Eutrophication",
 "Poleotolerance","Altitudinal distribution"]
LABELS=FIELD_LABELS
STOP_MARKERS=["Predictive model","Herbarium samples","INDEX FUNGORUM","Bibliography","Back to top"]

class TextParser(HTMLParser):
    def __init__(self): super().__init__(); self.parts=[]
    def handle_data(self,d):
        d=re.sub(r"\s+"," ",d).strip()
        if d:self.parts.append(d)
    def text(self):return "\n".join(self.parts)

def _clean(v):
    v=htmllib.unescape(v or "")
    v=re.sub(r"\s+"," ",v).strip(" \n\t:")
    for marker in STOP_MARKERS:
        m=re.search(rf"\b{re.escape(marker)}\b",v,re.I)
        if m:v=v[:m.start()].strip()
    return v

def _name_from_html(raw):
    m=re.search(r'<meta\s+property=["\']og:title["\']\s+content=["\']([^"\']+)',raw,re.I)
    if m:return _clean(m.group(1))
    for tag in ("h3","h2","h1"):
        for m in re.finditer(rf"<{tag}\b[^>]*>(.*?)</{tag}>",raw,re.I|re.S):
            name=_clean(re.sub(r"<[^>]+>"," ",m.group(1)))
            if name and "ITALIC" not in name.upper():return name
    return ""

def _label_positions(text):
    found=[]
    for label in LABELS:
        for m in re.finditer(re.escape(label),text):found.append((m.start(),label))
    found.sort()
    # keep first occurrence of each structural label
    out=[];seen=set()
    for x in found:
        if x[1] not in seen:out.append(x);seen.add(x[1])
    return out

def _extract_belts_from_html(raw):
    out={}
    for hm in re.finditer(r"<h6\b[^>]*>(.*?)</h6>",raw,re.I|re.S):
        plain=_clean(re.sub(r"<[^>]+>"," ",hm.group(1)))
        for label in BELT_LABELS:
            key=label[:-1]
            m=re.match(r"^"+re.escape(key)+r"\s*:\s*(.+?)\s*$",plain,re.I)
            if m:out[key]=_clean(m.group(1));break
    return out

def _extract_ecological_scales(raw):
    """Read species-specific highlighted ranges from ITALIC eco tables.
    CSS left/center/right cell classes identify the selected range."""
    out={}
    starts=list(re.finditer(r'<div\s+class=["\']eco-grid-container["\']',raw,re.I))
    for idx,sm in enumerate(starts):
        block=raw[sm.start(): starts[idx+1].start() if idx+1<len(starts) else
                  min(len(raw),sm.start()+12000)]
        hm=re.search(r"<h4[^>]*>(.*?)</h4>",block,re.I|re.S)
        if not hm:continue
        label=_clean(re.sub(r"<[^>]+>"," ",hm.group(1))).rstrip(":")
        if label not in SCALE_LABELS:continue
        selected=[]
        table=re.search(r'<table\s+class=["\']eco-table["\'][^>]*>(.*?)</table>',block,re.I|re.S)
        if not table:continue
        for td in re.finditer(r"<td([^>]*)>(.*?)</td>",table.group(1),re.I|re.S):
            attrs=td.group(1);val=_clean(re.sub(r"<[^>]+>"," ",td.group(2)))
            if not re.fullmatch(r"\d+",val):continue
            cm=re.search(r'class=["\']([^"\']+)["\']',attrs,re.I)
            classes=cm.group(1).split() if cm else []
            if any(c.startswith(("left-cell","center-cell","right-cell","only-cell")) for c in classes):
                selected.append(int(val))
        if selected:
            selected=sorted(set(selected))
            out[label]={"min":min(selected),"max":max(selected),"values":selected}
    return out

def parse_html(i,raw,url=None):
    p=TextParser();p.feed(raw);text=p.text()
    if re.search(r"\bInvalid taxon id\b",text,re.I):raise ValueError("invalid ITALIC taxon id")
    name=_name_from_html(raw)
    if not name:raise ValueError("taxon name not detected")
    if "Description:" not in text and "Growth form:" not in text:
        raise ValueError("not a structured ITALIC taxon page")
    pos=_label_positions(text);vals={}
    for n,(start,label) in enumerate(pos):
        a=start+len(label);b=pos[n+1][0] if n+1<len(pos) else len(text)
        v=_clean(text[a:b])
        if v and label not in vals:vals[label]=v
    syn=[_clean(x) for x in re.split(r";|\s+\|\s+",vals.get("Synonyms:","")) if _clean(x)]
    return {"scientificName":name,"italicId":i,"synonyms":syn,
      "distribution":vals.get("Distribution:"),"description":vals.get("Description:"),
      "note":vals.get("Note:"),"growthForm":vals.get("Growth form:"),
      "substrata":vals.get("Substrata:"),"photobiont":vals.get("Photobiont:"),
      "reproductiveStrategy":vals.get("Reproductive strategy:"),
      "belts":_extract_belts_from_html(raw),
      "ecologicalScales":_extract_ecological_scales(raw),
      "sourceUrl":url or BASE.format(i)}

def download_html(i,timeout=60,user_agent="italicapp-scientific-snapshot/0.8.1"):
    url=BASE.format(i);req=Request(url,headers={"User-Agent":user_agent})
    try:
        with urlopen(req,timeout=timeout) as r:return r.read().decode("utf-8","replace")
    except (HTTPError,URLError) as e:raise RuntimeError(f"request failed: {e}") from e

def fetch(i):return parse_html(i,download_html(i))
