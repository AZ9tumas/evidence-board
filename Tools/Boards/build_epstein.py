"""Expand the existing Epstein board, preserving its card IDs and embedded images.

Usage: python3 Tools/Boards/build_epstein.py [board.evboard]
Sources were reviewed 7 November 2026 (Asia/Kolkata). This is a curated case
overview, not a full-text import or an exhaustive review of the released files.
The update is deterministic and can be rerun on the checked-in board.
"""

import argparse
import json
import math
from pathlib import Path
import uuid


ROOT = Path(__file__).resolve().parents[2]
STAMP = "2026-11-06T20:29:53Z"
NS = uuid.UUID("2888A465-BE75-4346-A49C-294C3A3CB2C6")
IDS = {
    "title": "BF8090FD-F8E0-4F76-826E-8B381FD1904D",
    "rockefeller": "0D00B8A3-7AE8-4861-96E7-A76252D77466",
    "epstein": "6FF215B8-0ED5-4260-8222-092B378E2D53",
    "commission": "4E4805A9-0071-4C20-9165-2A54A893144D",
    "commission_wiki": "244893CF-BB3E-4E13-876D-9ABC8688BC3A",
    "commission_summary": "7B437909-ED9A-4D36-ADEA-65BB93451458",
    "wexner": "6315EECC-4E0C-411B-BEA4-7535149FAD93",
    "victorias_secret": "645AC788-E6A8-4B6B-A9E1-EEAEB1B47E4E",
    "power_of_attorney": "1599780C-790B-4F2C-8372-C4F080912A1C",
    "terms_heading": "90920C40-8DAA-4C51-A5D1-E7E77E1BF470",
    "occult": "80882E27-3E4E-46CF-B12F-283011D931AE",
    "terms": "E579604B-E58C-42E5-A8DF-0829DB99A2B1",
    "schneerson": "EE9AE81F-AFC3-48A8-982B-1A5ABFF5B56E",
    "schneerson_bio": "15FDF91F-2434-4D85-8014-5A761105D5C1",
    "chabad_photo": "E695D062-F5F3-4D84-810C-43A1593FEC15",
    "chabad_wiki": "8EA71D49-E848-4498-8B6F-C952B09F8E0D",
    "chabad_history": "53B98635-5AD4-4E5B-BBAA-D031110D00BF",
}

SOURCES = {
    "E01": ("DOJ · OPR", "2006–2008 investigation: executive summary",
            "https://www.justice.gov/opr/page/file/1336471/dl?inline=",
            "Primary report · November 2020 · PDF pp. 2–3, printed pp. ii–iii: investigation, agreement and guilty plea."),
    "E02": ("DOJ · SDNY", "Jeffrey Epstein charged in Manhattan federal court",
            "https://www.justice.gov/usao-sdny/pr/jeffrey-epstein-charged-manhattan-federal-court-sex-trafficking-minors",
            "Prosecution announcement · 8 July 2019 · Describes allegations in the indictment, not a verdict."),
    "E03": ("DOJ · SDNY", "United States v. Jeffrey Epstein, 19 Cr. 490",
            "https://www.justice.gov/usao-sdny/programs/victim-witness-services/united-states-v-jeffrey-epstein-19-cr-490-rmb",
            "Official case page · Records the 29 August 2019 dismissal following Epstein’s death."),
    "E04": ("DOJ · OPR", "Statement on review of the 2006–2008 investigation",
            "https://www.justice.gov/archives/opa/pr/statement-doj-office-professional-responsibility-report-jeffrey-epstein-2006-2008",
            "Official findings summary · 12 November 2020 · Poor judgment and treatment of victims; no professional misconduct finding."),
    "E05": ("DOJ · SDNY", "Ghislaine Maxwell sentenced to 20 years",
            "https://www.justice.gov/usao-sdny/pr/ghislaine-maxwell-sentenced-20-years-prison-conspiring-jeffrey-epstein-sexually-abuse",
            "Official sentencing announcement · 28 June 2022 · Also records the 29 December 2021 jury verdict."),
    "E06": ("DOJ · Inspector General", "Custody, care and supervision of Jeffrey Epstein",
            "https://oig.justice.gov/sites/default/files/reports/23-085.pdf",
            "Primary report 23-085 · June 2023 · Executive summary, printed pp. i–iv: death investigation and prison failures."),
    "F01": ("U.S. Department of Justice", "Epstein Library",
            "https://www.justice.gov/epstein",
            "Official release portal · Displayed update: 11 September 2026 · Includes search limitations and privacy notice."),
    "F02": ("U.S. Department of Justice", "First phase of declassified files announced",
            "https://www.justice.gov/opa/pr/attorney-general-pamela-bondi-releases-first-phase-declassified-epstein-files",
            "Release announcement · 27 February 2025 · Links to an evidence list, flight logs and redacted lists."),
    "F03": ("U.S. Department of Justice", "DOJ announces nearly 3.5 million released pages",
            "https://www.justice.gov/opa/pr/department-justice-publishes-35-million-responsive-pages-compliance-epstein-files",
            "Release announcement · 30 January 2026 · DOJ’s stated totals and caveats about public submissions."),
    "W01": ("The Wexner Foundation", "Letter from Les",
            "https://www.wexnerfoundation.org/letter-from-les/",
            "First-person account · 8 August 2019 · Wexner describes financial authority, a trusteeship and his account of the separation."),
    "W02": ("Associated Press", "Wexner says he was duped by Epstein",
            "https://apnews.com/article/733833f6d648c09e6b3473eb1cd4009d",
            "Independent reporting · Wexner’s denial of knowledge of abuse and reporting on the financial relationship."),
    "W03": ("SEC · Victoria’s Secret & Co.", "Form 8-K: separation from L Brands",
            "https://www.sec.gov/Archives/edgar/data/1856437/000114036121026649/nt10026698x8_8k.htm",
            "Corporate filing · August 2021 · Victoria’s Secret becomes a separate publicly traded company."),
    "T01": ("The Trilateral Commission", "About the Trilateral Commission",
            "https://www.trilateral.org/about/",
            "Organization’s own history · Founding in 1973 by David Rockefeller; stated purpose and membership model."),
    "R01": ("Chabad.org", "The Rebbe: a brief biography",
            "https://www.chabad.org/therebbe/article_cdo/aid/244372/jewish/The-Rebbe-A-Brief-Biography.htm",
            "Institutional biography · Schneerson’s life, arrival in the U.S. and leadership. Chabad’s own perspective."),
    "R02": ("Chabad.org", "Background: history and ideology",
            "https://www.chabad.org/library/article_cdo/aid/2346204/jewish/Background-History-and-Ideology.htm",
            "Institutional account · Founder, religious philosophy and educational/social-service organizations."),
    "R03": ("Enzo Pace · Horizontes Antropológicos", "Extreme messianism: Chabad and charisma",
            "https://socialsciences.scielo.org/scielo.php?pid=S0104-71832007000100005&script=sci_arttext",
            "Academic analysis · 2007 · Distinguishes followers’ messianic belief from a declaration by Schneerson."),
    "R04": ("Associated Press", "Who was the revered rabbi?",
            "https://apnews.com/article/67e2cf3e81165b4b8491ef67fb72b21f",
            "Independent biographical reporting · Schneerson led Chabad from 1951 until his death in 1994."),
}


def uid(name):
    return IDS.get(name, str(uuid.uuid5(NS, "case:" + name)).upper())


def build(board):
    """Compose a connected investigation board, with the original images as anchors."""
    import copy
    import random
    import textwrap

    previous = {c["id"]: c for c in board["cards"]}
    cards, strings, named = [], [], {}
    rng = random.Random(72)

    def put(name, x, y, w, h, kind, payload, tint=None, rotation=None):
        c = copy.deepcopy(previous.get(uid(name), {"id": uid(name), "createdAt": STAMP}))
        for key in ("text", "image", "web", "tint"):
            c.pop(key, None)
        c.update(type=kind, frame={"x": x, "y": y, "width": w, "height": h},
                 rotation=rotation if rotation is not None else round(rng.uniform(-1.6, 1.6), 1),
                 locked=False, modifiedAt=STAMP, z=len(cards) + 1)
        c[kind] = payload
        if tint:
            c["tint"] = tint
        cards.append(c)
        named[name] = c
        return name

    def note(name, x, y, content, tint=None, w=310, style="note", size=17):
        # Word wrapping, not a fixed row height: each slip is sized to its contents.
        columns = max(8, int((w - 40) / (size * 0.56)))
        lines = sum(max(1, len(textwrap.wrap(line.replace("**", ""), columns))) for line in content.split("\n"))
        h = math.ceil(64 + lines * size * 1.4)
        return put(name, x, y, w, h, "text", {
            "content": content, "style": style, "alignment": "leading", "autoHeight": True,
            "fontSize": size,
        }, tint, 0 if style == "headline" else None)

    def heading(name, x, y, content, w=650):
        note(name, x, y, content, w=w, style="headline", size=30)
        named[name]["locked"] = True

    def picture(name, x, y, w=270):
        payload = copy.deepcopy(previous[uid(name)]["image"])
        a = board["assets"][payload["asset"]]
        h = math.ceil((w - 24) * a["pixelHeight"] / a["pixelWidth"] + 70)
        return put(name, x, y, w, h, "image", payload)

    def source(ref, x, y, w=310):
        site, title, url, summary = SOURCES[ref]
        return put("source_" + ref, x, y, w, 225, "web", {"url": url, "snapshot": {
            "fetchedAt": STAMP, "variant": "compact", "siteName": site,
            "title": f"[{ref}] {title}", "description": summary,
        }})

    def existing_web(name, x, y):
        payload = copy.deepcopy(previous[uid(name)]["web"])
        put(name, x, y, 310, 290, "web", payload)

    def link(a, b, label=None, color="red", style="solid", weight=2.2, arrow="none", sag=0.35):
        edge = {"id": uid("thread:" + a + ":" + b), "from": uid(a), "to": uid(b),
                "color": color, "style": style, "arrow": arrow, "thickness": weight, "sag": sag}
        if label:
            edge["label"] = label
        strings.append(edge)

    def cites(name, ref):
        link(name, "source_" + ref, color="graphite", weight=1.2, sag=0.15)

    # Title and one compact key, as on The Albania Files. The canvas opens on the
    # people and their connections; the complete case is available with Zoom to Fit.
    heading("title", -560, -1810, "THE EPSTEIN FILES", 950)
    named["title"]["text"]["fontSize"] = 44
    named["title"]["frame"]["height"] = 120
    note("scope", -550, -1640,
         "**THE CASE · THE MONEY · THE RECORDS**\nJeffrey Epstein, Ghislaine Maxwell, Leslie Wexner, and the institutional leads. "
         "Schneerson / Chabad: a separate context cluster.\nSources reviewed 7 Nov 2026. A curated case overview, not a full review of the releases.", w=640, size=18)
    note("legend", 160, -1620,
         "THREAD KEY\nRed — financial relationships\nBlue — case / court history\nPurple — religious history\nThin gray — sources\nDashed — unresolved lead\n"
         "A listed contact is not proof of a crime.", w=300, style="typewriter", size=15)

    # The central hub uses the real subject cards; there is no duplicate map.
    picture("epstein", -390, -850, 330)
    note("case_overview", -450, -420,
         "**JEFFREY EPSTEIN**\n2008: Florida guilty plea.\n2019: federal trafficking charges; died before trial.\n"
         "Follow the blue threads to the court record and the red thread to his financial authority.\n[E01–E03, W01]", "red", w=340, size=18)
    note("maxwell", 230, -510,
         "**GHISLAINE MAXWELL**\nJury verdict: **29 Dec 2021**.\nSentence: **20 years**, 28 Jun 2022.\n"
         "Convicted for her role in recruiting, grooming and facilitating the abuse of minors with Epstein. [E05]", "azure", w=330, size=18)
    source("E05", 650, -210)
    link("maxwell", "epstein", "convicted scheme · E05", "azure", weight=3)
    link("epstein", "case_overview", color="azure", weight=1.5)
    cites("maxwell", "E05")

    # Upper left: an institutional lead, not a claimed criminal organization.
    heading("institutions_heading", -2300, -1770, "ACCESS & INSTITUTIONS", 870)
    picture("rockefeller", -1960, -1390, 250)
    picture("commission", -1250, -1500, 270)
    note("commission_summary", -1590, -1080,
         "**TRILATERAL COMMISSION**\nFounded by David Rockefeller in **1973**. A forum for policymakers, business, media and academics "
         "across North America, Europe and Asia, according to its own history. [T01]", w=310)
    source("T01", -2330, -920)
    existing_web("commission_wiki", -2380, -1530)
    note("invitation_lead", -1100, -980,
         "**WHO INVITED EPSTEIN?**\nThe original ‘Rockefeller invited him at 30’ claim remains unverified here. "
         "A dated invitation or reliable membership record is needed.\nKeep this as an open lead, not an established relationship.", "amber", w=300)
    link("rockefeller", "commission", "founded · 1973", "teal")
    link("commission", "commission_summary", color="teal")
    link("commission", "commission_wiki", color="graphite", weight=1.2)
    cites("commission_summary", "T01")
    link("invitation_lead", "commission", color="amber", style="dashed", weight=1.5)
    link("invitation_lead", "epstein", "invitation unverified", "amber", "dashed", 1.8)

    # Left flank: real financial authority, the response, and corporate history.
    heading("money_heading", -2330, -390, "THE MONEY & THE AUTHORITY", 960)
    picture("wexner", -1050, -100, 280)
    note("power_of_attorney", -1600, -50,
         "**POWER OF ATTORNEY**\nWexner acknowledged giving Epstein broad authority over his personal finances. "
         "He also described an early-1990s foundation trusteeship without executive responsibilities.\n"
         "His letter does not establish authority over ‘life and death.’ [W01]", "red", w=330)
    source("W01", -2170, 20)
    note("wexner_denial", -1750, 530,
         "**WEXNER’S ACCOUNT**\nHe says he was deceived, and denies knowing about or participating in the abuse. "
         "AP dates the financial power of attorney to **1991**.\nAn attributed response, not an independent finding. [W02]", "amber", w=320)
    source("W02", -2250, 610)
    picture("victorias_secret", -1030, 680, 220)
    note("retail_history", -1470, 1060,
         "**VICTORIA’S SECRET**\nThe ‘owns’ shorthand is outdated. The business separated from L Brands in **August 2021** "
         "as an independent public company. The former parent retained no ownership interest. [W03]", w=320)
    source("W03", -2070, 1110)
    link("wexner", "epstein", "financial authority · W01", "red", weight=3.2, arrow="forward", sag=0.6)
    link("wexner", "power_of_attorney", color="red")
    cites("power_of_attorney", "W01")
    link("wexner", "wexner_denial", "his response", "amber", weight=1.8)
    cites("wexner_denial", "W02")
    link("victorias_secret", "retail_history", "2021 separation", "teal")
    link("wexner", "retail_history", "retail context", "graphite", "dotted", 1.4)
    cites("retail_history", "W03")

    # Lower center: branching court history, with short notes and nearby exhibits.
    heading("case_heading", -10, 100, "THE CASE & ITS AFTERMATH", 1000)
    note("florida", -630, 600,
         "**2005 → 2008 / FLORIDA**\nPolice investigation began in 2005. A federal non-prosecution agreement followed on **24 Sep 2007**. "
         "On **30 Jun 2008**, Epstein pleaded guilty to felony solicitation of prostitution and procurement of minors to engage in prostitution; "
         "the court imposed **18 months**. [E01]", "azure", w=340)
    source("E01", -1020, 1510)
    note("charges", -80, 690,
         "**8 JUL 2019 / FEDERAL CHARGES**\nSDNY alleged sex trafficking of minors and conspiracy, involving paid recruitment "
         "and abuse in New York and Florida in 2002–2005.\n**Allegations; Epstein was not tried.** [E02]", "amber", w=310)
    source("E02", 330, 560)
    note("dismissal", 510, 1030,
         "**29 AUG 2019 / DISMISSAL**\nThe federal case was dismissed following Epstein’s death. Victims spoke at an August hearing.\n"
         "This was not an acquittal or a finding that the allegations were false. [E03]", "azure", w=310)
    source("E03", 870, 1420)
    note("opr", -620, 1600,
         "**2020 / THE DEAL REVIEWED**\nDOJ’s OPR found poor judgment by Alexander Acosta over the deal and victim notification, "
         "and criticized the treatment of victims. It did **not** find professional misconduct by DOJ attorneys. [E04]", "azure", w=330)
    source("E04", -110, 1770)
    note("death_review", 360, 1650,
         "**2023 / CUSTODY FAILURES**\nThe Inspector General documented serious supervision and prison failures. "
         "Its report records the medical examiner’s suicide finding for **10 Aug 2019**, and the FBI’s finding of no criminality in how Epstein died. [E06]", "azure", w=340)
    source("E06", 850, 1950)
    link("case_overview", "florida", "guilty plea", "azure", weight=2.6)
    link("case_overview", "charges", "federal charges", "azure", weight=2.6)
    link("florida", "charges", "later prosecution", "azure", weight=1.8)
    link("charges", "dismissal", "case closed after death", "azure", arrow="forward", weight=1.8)
    link("opr", "florida", "reviewed the deal", "azure", weight=1.8)
    link("dismissal", "death_review", "custody review", "azure", weight=1.8)
    for name, ref in [("florida", "E01"), ("charges", "E02"), ("dismissal", "E03"), ("opr", "E04"), ("death_review", "E06")]:
        cites(name, ref)

    # Upper right: the released records branch out from their official library.
    heading("files_heading", 780, -1810, "FOLLOW THE FILES", 750)
    note("library", 770, -1350,
         "**THE OFFICIAL LIBRARY**\nDOJ and House disclosures, with the portal showing an update of **11 Sep 2026**. "
         "Handwriting and other formats can defeat electronic search. A missing result is not proof of absence. [F01]", "teal", w=310)
    source("F01", 1240, -1120)
    note("first_release", 1790, -1570,
         "**27 FEB 2025 / FIRST PHASE**\nEvidence list, flight logs and redacted lists. DOJ said much had previously leaked.\n"
         "A contact entry or flight log alone does not establish participation in a crime. [F02]", w=310)
    source("F02", 2160, -1210)
    note("release_2026", 1700, -960,
         "**30 JAN 2026 / EXPANDED RELEASE**\nDOJ announced over 3 million additional pages: nearly **3.5 million** in total. "
         "Multiple cases and investigations contributed. DOJ cautions that public submissions can contain false material. [F03]", "teal", w=330)
    source("F03", 1210, -730)
    note("record_types", 2140, -680,
         "READ THE RECORD\nJudgment: court outcome.\nIndictment: allegation.\nTestimony: a witness’s account.\nTip: may be unverified.\n"
         "For a claim, keep the document ID, page and context.", w=285, style="typewriter", size=15)
    cites("library", "F01")
    cites("first_release", "F02")
    cites("release_2026", "F03")
    link("library", "first_release", "2025 release", "teal", weight=1.6)
    link("first_release", "release_2026", "2026 expansion", "teal", weight=1.8)
    link("release_2026", "record_types", color="graphite", style="dotted", weight=1.3)
    link("library", "epstein", "investigation records", "teal", weight=2)
    link("source_E05", "library", "Maxwell case records", "teal", weight=1.6)

    # Separate context island: connections describe the actual religious history.
    heading("terms_heading", 1450, -70, "SCHNEERSON & CHABAD", 920)
    note("religion_boundary", 1450, 80,
         "HISTORICAL CONTEXT\nThese sources do not establish involvement by Schneerson or Chabad in Epstein’s crimes.", w=860, style="typewriter", size=15)
    picture("schneerson", 1760, 390, 250)
    note("schneerson_bio", 1310, 390,
         "**MENACHEM M. SCHNEERSON**\n**1902–1994** · The Lubavitcher Rebbe.\nSeventh leader of Chabad-Lubavitch; led the movement "
         "from **1951 to 1994**. [R01, R04]", "violet", w=300, size=18)
    source("R01", 2190, 320)
    source("R04", 1230, 900)
    note("messiah", 2160, 800,
         "**THE MESSIAH BELIEF**\nSome followers identified Schneerson as the Messiah. Enzo Pace’s study says he did not "
         "proclaim himself the Messiah and examines the belief’s persistence after his death.\nFollowers’ belief ≠ a self-declaration. [R03]", "violet", w=330)
    source("R03", 2590, 1060)
    picture("chabad_photo", 1700, 1150, 360)
    note("chabad_history", 1320, 1430,
         "**CHABAD-LUBAVITCH**\nA Hasidic movement founded by Shneur Zalman of Liadi in the late 18th century. "
         "Its institutional account describes religious learning, education and social services. [R02]", "violet", w=310)
    source("R02", 1660, 1750)
    existing_web("chabad_wiki", 2200, 1380)
    note("occult", 2180, 1860,
         "**WHAT THE TEACHING SAYS**\nChabad describes ‘wisdom, understanding and knowledge’ as its intellectual framework and "
         "discusses Jewish mysticism. This supplies religious context, not evidence of criminal conduct. [R02]", "violet", w=320)
    note("terms", 2670, 1550,
         "**UNSOURCED KEYWORDS**\nAstrology, alchemy, sacred geometry, reincarnation and possession were on the initial board. "
         "The cited sources do not establish these as Epstein’s interests or Chabad practices. Each needs its own source.", "amber", w=300)
    link("schneerson", "schneerson_bio", color="violet", weight=1.6)
    cites("schneerson", "R01")
    cites("schneerson_bio", "R04")
    link("schneerson", "chabad_photo", "led the movement", "violet", weight=2.6)
    link("messiah", "schneerson", "some followers’ belief", "violet", weight=1.8)
    cites("messiah", "R03")
    link("chabad_photo", "chabad_history", color="violet", weight=1.8)
    link("chabad_photo", "chabad_wiki", color="graphite", weight=1.2)
    cites("chabad_history", "R02")
    cites("occult", "R02")
    link("terms", "occult", "unsourced", "amber", "dashed", 1.5)

    assert set(IDS.values()) <= {c["id"] for c in cards}, "An original card was lost"
    board.update(title="The Epstein Files", modifiedAt=STAMP, theme="cork",
                 viewport={"x": -340, "y": -720, "zoom": 0.36}, cards=cards, strings=strings)
    return board


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("board", nargs="?", type=Path, default=ROOT / "boards/Jeffrey Epstein.evboard")
    args = parser.parse_args()
    board = build(json.loads(args.board.read_text()))
    encoded = json.dumps(board, indent=2, ensure_ascii=False, sort_keys=True, separators=(",", " : ")) + "\n"
    temporary = args.board.with_suffix(".evboard.tmp")
    temporary.write_text(encoded)
    temporary.replace(args.board)
    print(f"Updated {args.board}: {len(board['cards'])} cards, {len(board['strings'])} strings, {len(board['assets'])} assets")


if __name__ == "__main__":
    main()
