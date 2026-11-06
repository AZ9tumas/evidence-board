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
STAMP = "2026-11-06T18:49:38Z"
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
    original_ids = {c["id"] for c in board["cards"]}
    cards = {c["id"]: c for c in board["cards"]}
    strings = []

    def put(name, x, y, w, h, kind, payload, tint="graphite", locked=False):
        cid = uid(name)
        c = cards.get(cid, {"id": cid, "createdAt": STAMP})
        for key in ("text", "image", "web"):
            c.pop(key, None)
        c.update(type=kind, frame={"x": x, "y": y, "width": w, "height": h},
                 rotation=0, locked=locked, tint=tint, modifiedAt=STAMP)
        c[kind] = payload
        cards[cid] = c
        return name

    def note(name, x, y, content, tint="graphite", w=400, style="note"):
        # Leave room for platform font differences and wrapped bold headings.
        char_width, line_height = (18, 34) if style == "headline" else (8.8, 22)
        per_line = max(1, int((w - 40) / char_width))
        lines = sum(max(1, math.ceil(len(p.replace("**", "")) * 1.08 / per_line))
                    for p in content.split("\n"))
        height = 64 + lines * line_height
        return put(name, x, y, w, height, "text",
                   {"content": content, "style": style, "alignment": "leading", "autoHeight": True},
                   tint, style == "headline")

    def picture(name, x, y, w=350):
        c = cards[uid(name)]
        payload = c["image"].copy()
        asset = board["assets"][payload["asset"]]
        h = math.ceil((w - 24) * asset["pixelHeight"] / asset["pixelWidth"] + 76)
        return put(name, x, y, w, h, "image", payload)

    def source(name, x, y, ref, tint="azure"):
        site, title, url, summary = SOURCES[ref]
        return put(name, x, y, 400, 290, "web", {"url": url, "snapshot": {
            "fetchedAt": STAMP, "variant": "compact", "siteName": site,
            "title": f"[{ref}] {title}", "description": summary,
        }}, tint)

    def existing_web(name, x, y):
        c = cards[uid(name)]
        c.update(frame={"x": x, "y": y, "width": 400, "height": 390}, rotation=0, modifiedAt=STAMP)

    def connect(a, b, label="source", color="azure", style="solid", legacy_id=None):
        strings.append({"id": legacy_id or uid("string:" + a + ":" + b),
                        "from": uid(a), "to": uid(b), "color": color,
                        "style": style, "arrow": "forward", "label": label,
                        "thickness": 2, "sag": 0})

    def pair(name, x, y, content, ref, tint="teal"):
        note(name, x, y, content + f"\nSource: [{ref}] →", tint)
        source(name + "_source", x + 650, y, ref)
        connect(name, name + "_source")

    # A four-column reading order keeps each claim beside the record supporting it.
    note("title", 0, -650, "THE EPSTEIN FILES", "red", 1300, "headline")
    note("scope", 0, -490,
         "**A sourced case board**\nCourt milestones · released records · financial relationships · Schneerson and Chabad context.\n"
         "Reviewed 7 Nov 2026 (Asia/Kolkata). A curated overview; the full release has not been reviewed. Existing photos retained.", w=1050)
    note("legend", 1400, -650,
         "**READ THE STATUS FIRST**\nTEAL — documented outcome / official finding\nAMBER — allegation or attributed account\n"
         "VIOLET — religious / historical context\nGRAPHITE — open question / reading guide\n"
         "Blue arrows lead to sources. Dashed arrows mark unverified claims. A name in a file does not by itself establish wrongdoing.", w=1050)
    note("provenance", 2800, -650,
         "**FOLLOW THE SOURCE**\nSource IDs match the linked web cards. Card descriptions are curated summaries. "
         "Court allegations, findings, institutional histories and first-person statements are labeled separately.\n"
         "The religious-history section supplies context; the cited material does not establish participation by Schneerson or Chabad in Epstein’s crimes.", w=1050)
    note("navigation", 4200, -650,
         "**EXPLORE THE BOARD**\n1. Case timeline\n2. The released files\n3. Money and institutions\n4. The rabbi and Chabad\n"
         "Open a web card for its source. Select connected cards and use Trace (⌘T). Refresh All Previews (⇧⌘R) can fetch page imagery.", w=1050)

    # 1. Criminal case, with charges distinguished from adjudicated outcomes.
    note("case_heading", 0, -160, "01 / THE CASE", "red", 1050, "headline")
    picture("epstein", 0, 0)
    note("case_overview", 650, 0,
         "**JEFFREY EPSTEIN**\n2008: pleaded guilty to Florida state offenses.\n2019: federally charged; died before trial.\n"
         "The 2019 prosecution ended without a trial verdict. Maxwell’s later conviction is a separate adjudication.\n"
         "Sources: [E01], [E02], [E03], [E05] below.", "teal")
    connect("epstein", "case_overview", "case summary")
    pair("florida", 0, 580,
         "**2005–2008 / FLORIDA**\nPalm Beach police began investigating in 2005. A federal non-prosecution agreement was signed on "
         "24 Sep 2007. On 30 Jun 2008, Epstein pleaded guilty to felony solicitation of prostitution and procurement of minors "
         "to engage in prostitution, the offenses’ statutory labels. He received an 18-month jail sentence.", "E01")
    pair("charges", 0, 1120,
         "**8 JUL 2019 / FEDERAL CHARGES**\nSDNY unsealed charges of sex trafficking of minors and conspiracy. "
         "Prosecutors alleged abuse and paid recruitment of girls in New York and Florida during 2002–2005.\n"
         "Status: indictment allegations, never tried against Epstein.", "E02", "amber")
    pair("dismissal", 0, 1640,
         "**29 AUG 2019 / CASE DISMISSED**\nThe court formally dismissed United States v. Epstein following his death. "
         "The dismissal followed an August hearing at which victims could speak. It was not an acquittal or a determination that the allegations were false.", "E03")
    pair("opr", 0, 2140,
         "**12 NOV 2020 / PROSECUTOR REVIEW**\nOPR found that Alexander Acosta exercised poor judgment in the non-prosecution deal "
         "and handling victim notification. It did not find professional misconduct by DOJ attorneys. "
         "The review criticized how victims were treated.", "E04")
    pair("maxwell", 0, 2640,
         "**2021–2022 / MAXWELL CONVICTED**\nA jury found Ghislaine Maxwell guilty on 29 Dec 2021. "
         "On 28 Jun 2022 she was sentenced to 20 years for her role in recruiting, grooming and facilitating abuse of minors with Epstein.\n"
         "Status: jury verdict and sentence; not merely a contact or association.", "E05")
    pair("death_review", 0, 3160,
         "**JUN 2023 / CUSTODY REVIEW**\nThe Inspector General documented serious prison staffing, supervision and other failures. "
         "Its report records the medical examiner’s suicide finding for Epstein’s 10 Aug 2019 death and the FBI’s finding of no criminality in how he died.\n"
         "Institutional failures and the cause-of-death findings are distinct issues.", "E06")

    # 2. What was released and how to evaluate it.
    note("files_heading", 1400, -160, "02 / THE FILES", "azure", 1050, "headline")
    pair("library", 1400, 0,
         "**START WITH THE OFFICIAL LIBRARY**\nThe DOJ portal links to DOJ and House disclosures. Its displayed update is 11 Sep 2026. "
         "It cautions that handwriting and other formats can make search unreliable.\n"
         "A missing search result is not proof that a document or name is absent.", "F01")
    pair("first_release", 1400, 580,
         "**27 FEB 2025 / FIRST PHASE**\nDOJ released an evidence list, flight logs and redacted contact-related lists. "
         "DOJ said much of this material had previously leaked.\n"
         "Reading rule: a contact entry records a listed contact; a flight entry records reported travel. Neither alone proves participation in a crime.", "F02")
    pair("release_2026", 1400, 1120,
         "**30 JAN 2026 / EXPANDED RELEASE**\nDOJ announced more than 3 million additional pages, bringing its stated total to nearly "
         "3.5 million. The release draws on several investigations and cases.\n"
         "DOJ cautions that responsive public submissions may contain false material. Publication is not verification of every assertion.", "F03")
    note("record_types", 1400, 1640,
         "**WHAT KIND OF RECORD IS IT?**\nJudgment → adjudicated outcome.\nIndictment or complaint → allegations.\n"
         "Deposition → a witness’s testimony.\nEmail → a communication requiring context.\nTip → information submitted, possibly unverified.\n"
         "Contact or flight log → a limited record of contact or travel.\nBoard method: establish provenance before drawing a conclusion.")
    note("record_check", 2050, 1640,
         "**FOR EACH CLAIM, CAPTURE**\nDocument ID and URL\nPage number and relevant passage\nAuthor, date and recipient\n"
         "Firsthand knowledge or hearsay?\nCorroboration and any denial\nLater court outcome or correction\n"
         "Avoid copying private victim identifiers into research notes.")
    connect("record_types", "record_check", "evaluate")
    note("open_files", 1400, 2240,
         "**NEXT DOCUMENT WORK**\n1. Trace a specific assertion to its original page.\n2. Compare the release copy with the court exhibit.\n"
         "3. Read the surrounding exchange.\n4. Record contradictions and gaps.\n5. Update the status only when the evidence warrants it.\n"
         "This board does not claim a full review of millions of pages.")
    note("reading_findings", 2050, 2240,
         "**CURRENT BOUNDARY**\nThe case timeline rests on the linked official records. The Wexner section includes his own account and reporting. "
         "The Rockefeller invitation detail remains an open lead. Schneerson and Chabad have a separate historical context section.\n"
         "No connection is evidence of criminal conduct without a source supporting that particular claim.")
    connect("open_files", "reading_findings", "scope")

    # 3. Financial relationships and the original institutional leads.
    note("money_heading", 2800, -160, "03 / MONEY & INSTITUTIONS", "amber", 1050, "headline")
    picture("wexner", 2800, 0)
    note("wexner_summary", 3450, 0,
         "**LESLIE WEXNER**\nEpstein managed Wexner’s personal finances and held power of attorney, according to Wexner’s 2019 letter. "
         "Wexner says he was deceived.\nThe authority and relationship are relevant financial history; assess specific conduct from the records.\nSource: [W01] below.", "amber")
    connect("wexner", "wexner_summary", "financial history")
    pair("power_of_attorney", 2800, 580,
         "**WHAT THE AUTHORITY COVERED**\nWexner said Epstein had broad authority over his personal finances. "
         "The letter does not support the original note’s claim of power over ‘life and death.’\n"
         "Wexner also described an early-1990s foundation trusteeship and said Epstein had no executive responsibilities there. "
         "These are Wexner’s statements.", "W01", "amber")
    pair("wexner_denial", 2800, 1120,
         "**WEXNER’S RESPONSE**\nAP reports that Wexner denied knowing about Epstein’s crimes or participating in abuse. "
         "It dates the power of attorney to 1991.\n"
         "Record the denial alongside the financial connection. A denial is an attributed statement, not an independent finding.", "W02", "amber")
    picture("victorias_secret", 2800, 1640, 260)
    note("retail_history", 3450, 1640,
         "**VICTORIA’S SECRET / CORPORATE HISTORY**\nThe original ‘owns’ link oversimplified the history. "
         "Victoria’s Secret separated from L Brands in August 2021 as an independent publicly traded company.\n"
         "The filing says the former parent retained no ownership interest.\nSource: [W03] below.", "teal")
    connect("victorias_secret", "retail_history", "2021 separation")
    source("retail_source", 2800, 2130, "W03")
    connect("retail_history", "retail_source", "filing")
    picture("rockefeller", 2800, 2570)
    picture("commission", 3450, 2570)
    connect("rockefeller", "commission", "founded in 1973", "teal",
            legacy_id="DDC158B1-5C49-4F7C-8E96-191F43EC9DD7")
    pair("commission_summary", 2800, 3110,
         "**THE TRILATERAL COMMISSION**\nFounded by David Rockefeller in 1973. The organization describes itself as a forum for "
         "policymakers, business leaders, media and academics across North America, Europe and Asia.\n"
         "Its institutional history supports the founding relationship above, not a criminal inference about members.", "T01")
    note("invitation_lead", 2800, 3650,
         "**OPEN LEAD / THE INVITATION**\nThe original board said Rockefeller invited Epstein at age 30. "
         "That age, invitation and inviter are not established by the sources cited here.\n"
         "Next: obtain a dated membership roster and the original invitation or a reliable account. Keep Epstein’s own recollections attributed.", "graphite")
    existing_web("commission_wiki", 3450, 3650)
    connect("invitation_lead", "commission_wiki", "background only", "graphite", "dashed")

    # 4. Resolve the user's rabbi reference from the board; avoid invented links.
    note("rabbi_heading", 4200, -160, "04 / THE RABBI & CHABAD", "violet", 1050, "headline")
    picture("schneerson", 4200, 0, 300)
    note("schneerson_bio", 4850, 0,
         "**MENACHEM MENDEL SCHNEERSON**\n1902–1994. Known as the Lubavitcher Rebbe; seventh leader of Chabad-Lubavitch. "
         "Led the movement from 1951 until his death in 1994.\n"
         "This identifies the rabbi already pictured on the board.\nSources: [R01], [R04] below.", "violet")
    connect("schneerson", "schneerson_bio", "biography", "violet",
            legacy_id="0F437CC9-AFBF-4AB0-9A8C-623C4FFEC2FE")
    source("rabbi_primary", 4200, 580, "R01", "violet")
    source("rabbi_independent", 4850, 580, "R04", "violet")
    connect("rabbi_primary", "rabbi_independent", "compare accounts", "violet")
    pair("chabad_history", 4200, 1120,
         "**CHABAD-LUBAVITCH**\nA Hasidic Jewish movement founded by Rabbi Shneur Zalman of Liadi in the late 18th century. "
         "Chabad’s institutional history emphasizes religious learning, education and social services.\n"
         "The name is an acronym for wisdom, understanding and knowledge. This is the organization’s account of its philosophy.", "R02", "violet")
    pair("messiah", 4200, 1640,
         "**THE MESSIAH CLAIM / CORRECTION**\nSome followers identified Schneerson as the Messiah. Enzo Pace’s academic study "
         "says Schneerson did not proclaim himself the Messiah and examines the persistence of this belief after his death.\n"
         "The original ‘claimed to be a Messiah’ note conflated a leader’s declaration with followers’ beliefs.", "R03", "violet")
    picture("chabad_photo", 4200, 2190, 400)
    existing_web("chabad_wiki", 4850, 2190)
    connect("chabad_photo", "chabad_wiki", "background", "violet",
            legacy_id="B76506CE-011F-4CFD-A6A2-EDAE99A90A10")
    note("terms_heading", 4200, 2700, "TERMS & OPEN QUESTIONS", "violet", 1050, "headline")
    note("occult", 4200, 2860,
         "**RELIGIOUS CONTEXT**\nChabad’s account discusses Jewish mysticism alongside study and religious practice. "
         "Its stated intellectual framework is described in [R02].\n"
         "The original occult heading was not a source establishing a criminal relationship. Keep descriptions of beliefs distinct from evidence about conduct.", "violet")
    note("terms", 4850, 2860,
         "**ORIGINAL RESEARCH KEYWORDS**\nAstrology · alchemy · sacred geometry · reincarnation · possession.\n"
         "Retained as questions from the initial board. No cited source here establishes these as Epstein’s interests or as a description of Chabad’s practices. "
         "Each would need its own specific source.")
    connect("occult", "terms", "unverified leads", "graphite", "dashed",
            legacy_id="2E1F3E74-FD15-47B3-917F-2C4114489997")
    note("religion_boundary", 4200, 3440,
         "**WHAT IS THE ACTUAL CONNECTION?**\nThe sources cited in this section establish religious history and debates about belief. "
         "They do not establish involvement by Schneerson or Chabad in Epstein’s crimes.\n"
         "A proposed link needs a named person, dated act and traceable document. This remains a research boundary, not a finding from an exhaustive search.", "graphite", 1050)

    # A compact relationship map provides actual person-to-person paths without
    # routing long strings through the source-reading columns above.
    note("relationships_heading", 0, 4300, "DOCUMENTED RELATIONSHIPS / SOURCE KEY ABOVE", "azure", 2450, "headline")
    note("map_maxwell", 0, 4480,
         "**GHISLAINE MAXWELL**\nConvicted for her role in the abuse scheme with Epstein.\nSource: [E05]", "teal")
    note("map_epstein", 650, 4480,
         "**JEFFREY EPSTEIN**\nThe criminal case and financial relationships have different evidentiary bases.\nSources: [E01–E05], [W01]", "red")
    note("map_wexner", 1300, 4480,
         "**LESLIE WEXNER**\nAcknowledged giving Epstein authority over personal finances. Denies knowledge of abuse.\nSources: [W01], [W02]", "amber")
    connect("map_maxwell", "map_epstein", "convicted role [E05]", "teal")
    connect("map_wexner", "map_epstein", "financial authority [W01]", "amber")
    note("map_rockefeller", 2800, 4480, "**DAVID ROCKEFELLER**\nFounder of the Trilateral Commission.\nSource: [T01]", "teal")
    note("map_commission", 3450, 4480, "**TRILATERAL COMMISSION**\nInstitutional history. The precise Epstein invitation remains unverified here.\nSource: [T01] / open lead above.")
    connect("map_rockefeller", "map_commission", "founded [T01]", "teal")
    note("map_schneerson", 4200, 4480, "**MENACHEM M. SCHNEERSON**\nSeventh rebbe of Chabad-Lubavitch.\nSources: [R01], [R04]", "violet")
    note("map_chabad", 4850, 4480, "**CHABAD-LUBAVITCH**\nReligious movement and institutions; historical context.\nSource: [R02]", "violet")
    connect("map_schneerson", "map_chabad", "led [R01, R04]", "violet")

    # The original assets and card identities survive, while unsupported edges are
    # replaced with explicit source relationships or labeled research questions.
    assert original_ids <= cards.keys(), "An existing card was lost"
    for z, card in enumerate(cards.values(), 1):
        card["z"] = z
    board.update(title="The Epstein Files — Case, Records & Chabad Context", modifiedAt=STAMP,
                 viewport={"x": 2625, "y": 2050, "zoom": 0.13},
                 cards=list(cards.values()), strings=strings)
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
