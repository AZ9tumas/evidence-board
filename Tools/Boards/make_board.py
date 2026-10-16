"""Builds "The Albania Files" evidence board from sourced facts. Usage: make_board.py map.jpg out.evboard [iterations] [seed]"""
import base64
import hashlib
import json
import math
import random
import sys
import uuid

MAP, OUT = sys.argv[1], sys.argv[2]
NOW = "2026-10-15T15:00:00Z"
NS = uuid.UUID("6f1d2c3b-7a8e-4d5f-9a0b-1c2d3e4f5a6b")
random.seed(42)

cards, strings, assets = [], [], {}
boxes = {}


def uid(name):
    return str(uuid.uuid5(NS, name)).upper()


def note_height(text, width, style):
    char, line, top = {"note": (7.7, 19.5, 48), "typewriter": (8.5, 17.5, 48), "headline": (17.5, 30, 48)}[style]
    per_line = max(1, int((width - 36) / char))
    lines = 0
    for paragraph in text.replace("**", "").replace("*", "").split("\n"):
        lines += max(1, math.ceil(len(paragraph) * 1.06 / per_line))
    return math.ceil(top + lines * line)


CLUSTER = ["fixed"]


def add(card, name, x, y, w, h):
    card.update({
        "id": uid(name), "createdAt": NOW, "modifiedAt": NOW, "locked": card.get("locked", False),
        "frame": {"x": x, "y": y, "width": w, "height": h}, "z": len(cards) + 1,
    })
    card.setdefault("rotation", round(random.uniform(-1.4, 1.4), 1))
    card["_name"], card["_cluster"] = name, CLUSTER[0]
    cards.append(card)
    boxes[name] = (x, y, w, h)
    return y + h


def text(name, x, y, w, content, style="note", tint=None, locked=False, rotation=None):
    card = {"type": "text", "text": {"content": content, "style": style, "alignment": "leading", "autoHeight": True}}
    if tint:
        card["tint"] = tint
    if locked:
        card["locked"] = True
    if rotation is not None:
        card["rotation"] = rotation
    return add(card, name, x, y, w, note_height(content, w, style))


PALETTES = {
    "Al Jazeera": ("#F2A900", "#8C7B5E", "#7A4A00", "#2E2A24", "#FFF4DD"),
    "Mother Jones": ("#E2262C", "#9A6A6A", "#5C0D10", "#2B1A1A", "#FFE9E9"),
    "NBC News": ("#6E5FD8", "#7E7AA8", "#2A1F7A", "#1E1C2E", "#EEEBFF"),
    "The Times of Israel": ("#2F7FD0", "#6A86A6", "#0E2A4D", "#17202B", "#E6F1FF"),
    "OCCRP": ("#1FA3A3", "#5E8F8F", "#0B4545", "#142424", "#E2FAFA"),
    "Exit News": ("#F0522E", "#A07060", "#55160B", "#2A1A15", "#FFEDE6"),
    "Balkan Insight": ("#D4213D", "#8F6670", "#4A0A16", "#251719", "#FFE8EC"),
    "Haaretz": ("#2D6FB0", "#62809E", "#0C2846", "#141E29", "#E5F0FB"),
    "CNN": ("#E01E1E", "#996666", "#4D0000", "#241414", "#FFE6E6"),
    "Electronic Arts": ("#FF5A5A", "#7D6E8A", "#231A3D", "#18151F", "#F2EEFF"),
    "Storyboard18": ("#8E3FC8", "#7E6A8F", "#2E0B47", "#1D1524", "#F4EAFF"),
    "N1": ("#1C79D8", "#5F7FA0", "#062A50", "#121C27", "#E6F2FF"),
    "House Judiciary Democrats": ("#3C6AB8", "#6C7F9E", "#0F2350", "#141A27", "#E8EEFA"),
    "Political Wire": ("#4A6FC7", "#6E7DA0", "#15265A", "#151A27", "#E9EEFF"),
    "Koha": ("#E8202C", "#9A6A6E", "#4A0408", "#241516", "#FFE7E8"),
    "Citizens.al": ("#14B3C2", "#5F9599", "#04424A", "#122224", "#E2FBFD"),
    "Wikipedia": ("#9AA0A8", "#7A7F87", "#2E3238", "#1C1E22", "#F4F5F7"),
    "Euronews": ("#2C6FE0", "#64809F", "#0A2655", "#131B26", "#E6EFFF"),
    "Axios": ("#2F6BFF", "#6A7FA8", "#0B2260", "#141A28", "#E7EEFF"),
    "Kitco": ("#E5A823", "#8F7F5C", "#5A3E00", "#26211A", "#FFF5DC"),
    "Sen. Jeff Merkley": ("#3F67B5", "#6D7F9F", "#11275A", "#151B28", "#E8EEFB"),
    "Commercial Observer": ("#D9363E", "#9A6E70", "#4C0B0F", "#251718", "#FFE8E9"),
    "Yahoo News": ("#7B3FE4", "#7F70A0", "#2A0E5C", "#1C1628", "#F1EAFF"),
    "NPR": ("#D62021", "#946A6A", "#470909", "#241515", "#FFE7E7"),
}


def web(name, x, y, url, site, title, description, published, w=340):
    v, m, dv, dm, light = PALETTES[site]
    snapshot = {
        "fetchedAt": NOW, "variant": "compact", "title": title, "description": description, "siteName": site,
        "publishedAt": published, "palette": {"vibrant": v, "muted": m, "darkVibrant": dv, "darkMuted": dm, "light": light},
    }
    title_lines = min(3, math.ceil(len(title) / 29))
    desc_lines = min(2, math.ceil(len(description) / 44))
    h = 150 + title_lines * 25 + desc_lines * 18
    return add({"type": "web", "web": {"url": url, "snapshot": snapshot}}, name, x, y, w, h)


def image(name, x, y, w, path, caption):
    data = open(path, "rb").read()
    key = "sha256-" + hashlib.sha256(data).hexdigest()
    from PIL import Image
    width, height = Image.open(path).size
    assets[key] = {"mime": "image/jpeg", "pixelWidth": width, "pixelHeight": height, "byteCount": len(data),
                   "data": base64.b64encode(data).decode()}
    photo_h = (w - 24) * height / width
    return add({"type": "image", "image": {"asset": key, "caption": caption, "frameStyle": "polaroid"}, "rotation": -1.0},
               name, x, y, w, math.ceil(photo_h + 12 + 52))


def string(a, b, color="red", label=None, style="solid", arrow="none", thickness=2.0, sag=0.45):
    s = {"id": uid(f"string {a} {b}"), "from": uid(a), "to": uid(b), "color": color, "style": style,
         "arrow": arrow, "thickness": thickness, "sag": sag}
    if label:
        s["label"] = label
    strings.append(s)


GAP = 46

# ---------------------------------------------------------------- Title
text("title", -460, -2330, 720, "THE ALBANIA FILES", "headline", locked=True, rotation=0)
text("subtitle", -460, -2240, 720,
     "**Jared Kushner · Ivanka Trump · Donald Trump · Steve Witkoff**: Sazan Island and Zvërnec, the Flamingo "
     "Revolution, the question of Israel's role, the billions behind Affinity Partners, and the envoy beside Kushner.\n"
     "Compiled 16 Oct 2026 from public reporting. Each card names its source.", rotation=0, locked=True)
text("legend", 330, -2340, 360,
     "HOW TO READ THIS BOARD\n"
     "✅ reported by named outlets/records\n"
     "⚠️ disputed, denied or conflicting\n"
     "❌ traced: no evidence found\n"
     "red string ....... money, ownership\n"
     "azure ............ family, politics\n"
     "rose ............. the protests\n"
     "dashed ........... alleged / withdrawn\n"
     "dotted ........... debunked", "typewriter", rotation=0.8)

# ---------------------------------------------------------------- People
CLUSTER[0] = "people"
text("trump", -330, -1960, 300,
     "**DONALD TRUMP**\n47th U.S. President (since 20 Jan 2025). Father-in-law of Jared Kushner. "
     "Created the Gaza **Board of Peace** in Jan 2026.", tint="amber")
text("kushner", -330, -1640, 300,
     "**JARED KUSHNER**\nFounder and CEO of **Affinity Partners** (2021). Former senior White House adviser. "
     "2026: U.S. *Special Envoy for Peace* and founding member of the Board of Peace's executive board.", tint="red")
text("ivanka", -760, -1800, 300,
     "**IVANKA TRUMP**\nTrump's daughter, Kushner's wife. In Vlorë with Kushner on **21 Jan 2026**; dined with PM Rama "
     "(Greek press). Has toured the area with architects and investors (Al Jazeera). No formal role in the companies found.",
     tint="rose")
text("rama", -1190, -1960, 300,
     "**EDI RAMA**\nPrime Minister of Albania. Chairs the Strategic Investment Committee that approved Sazan. "
     "Defends the project; protesters want him out.", tint="azure")
text("abehsera", -1190, -1610, 300,
     "**ASHER ABEHSERA**\nKushner's business partner; they worked on New York real estate together (AFP). Chairman "
     "and CEO of **Sazan Real Estate Development (SRED)**, which leads the project (Reuters, Exit News).", tint="violet")
text("khayyat", -1190, -1290, 300,
     "**MOUTAZ & RAMEZ AL-KHAYYAT**\nQatar-based brothers of Syrian origin, co-founders of UCC Holding. Filings show them "
     "holding most of SRED (Exit News). Their **Albania Land Development** bought Zvërnec beachfront plots (OCCRP).",
     tint="lime")
text("mbs", 560, -1960, 300,
     "**MOHAMMED BIN SALMAN**\nSaudi Crown Prince. Chairs the **Public Investment Fund (PIF)**, Affinity's anchor investor.",
     tint="teal")
text("affinity", 120, -1640, 320,
     "**AFFINITY PARTNERS**\nKushner's Miami private-equity firm, funded mostly from the Gulf. "
     "Assets passed **$6 billion** in 2025 (Dealroom). Had returned no profit to investors by 2024.", tint="graphite")

# ---------------------------------------------------------------- Albania
CLUSTER[0] = "albania"
text("h_albania", -3250, -2000, 620, "THE ISLAND AND THE LAGOON", "headline", locked=True, rotation=0)
image("map", -3250, -1880, 460, MAP, "Vlora Bay: Sazan, Zvërnec, Narta Lagoon (schematic)")

y = -1880
y = text("law", -2730, y, 310,
         "✅ **22 Feb 2024: Law 21/2024**\nParliament rewrites the Protected Areas law so **five-star resorts** can be built "
         "inside protected areas. Conservation groups say it gutted Vjosa–Narta's safeguards.") + GAP
y = text("sazan", -2730, y, 310,
         "✅ **30 Dec 2024: Sazan approved**\nRama's Strategic Investment Committee gives *strategic investor* status to "
         "**Atlantic Incubation Partners**, linked to Affinity: 45 ha, **€1.4 billion**, about 1,000 jobs. "
         "About three weeks before Trump's inauguration (Reuters).") + GAP
y = text("zvernec", -2730, y, 310,
         "✅ **Zvërnec: €230 million**\nKushner says his partnership bought the land from a private party for €230M "
         "and that the whole project could reach **about €4 billion**. Calls himself a minority partner, with Abehsera "
         "running it (Citizens.al, 9 Oct 2026).") + GAP
text("kushner_account", -2730, y, 310,
     "KUSHNER'S ACCOUNT\n(Oct 2026, paraphrased)\n- land bought privately, €230M\n- titles checked by lawyers\n"
     "- nothing given by the state\n- up to ~€4B, jobs, growth", "typewriter")

y = -1880
y = text("developer", -2370, y, 320,
         "⚠️ **Who is the developer?**\nAffinity says it is *not* the developer: investors joined \"in their personal "
         "capacity\". Lead company **SRED** was registered in Qatar in Oct 2025 (AFP). Most of it is held by the "
         "Al-Khayyat brothers; co-owners in Luxembourg and Delaware have undisclosed owners (Exit News).") + GAP
y = text("spak", -2370, y, 320,
         "⚠️ **SPAK investigation**\nAlbania's anti-corruption prosecutor is probing the 2024 protected-status changes, "
         "the land titles and the money used to buy them. Reuters saw files suspecting a **Miami-based Albanian "
         "businessman**, wanted for laundering drug money, of forging ownership papers. The files allege **no "
         "wrongdoing** by Kushner, SRED or other investors.") + GAP
text("freeze", -2370, y, 320,
     "⚠️ **Frozen, then unfrozen?**\nReported: SPAK froze about **$195M** in Albania Land Development accounts, then "
     "lifted it within days. SPAK has confirmed neither. In July it told U.S. media it had *no open investigation*, "
     "which conflicts with the land-title probe.")

y = -1880
y = web("w_aljazeera", -2010, y, "https://www.aljazeera.com/news/2026/6/5/why-the-kushners-plan-to-build-an-albanian-resort-has-sparked-protests",
        "Al Jazeera", "Kushner Island? Why a planned resort has provoked protests in Albania",
        "Explainer: Sazan, Zvërnec, strategic-investor status and the protests.", "2026-06-05T00:00:00Z") + GAP
y = web("w_exit", -2010, y, "https://exit.al/en/exit-explains/jared-kushners-fund-officially-distances-from-zvernec-development--i48037",
        "Exit News", "Jared Kushner's Fund Officially Distances from Zvernec Development in Albania",
        "SRED leads; ownership traced to the Al-Khayyat brothers.", None) + GAP
y = web("w_occrp", -2010, y, "https://www.occrp.org/en/news/albania-freezes-assets-in-kushner-resort-probe",
        "OCCRP", "Albania Freezes Assets in Kushner Resort Probe",
        "Albania Land Development accounts frozen in the land probe.", None) + GAP
web("w_koha", -2010, y, "https://www.koha.net/en/arberi/reuters-zbulon-dosjen-e-spak-ut-dyshime-per-falsifikim-te-dokumenteve-te-pronesise-ne-zvernec",
    "Koha", "Reuters reveals SPAK file: Suspicions of falsification of property documents in Zvërnec",
    "No wrongdoing alleged against Kushner or the investors.", None)

web("w_citizens", -2730, -560, "https://citizens.al/en/2026/10/09/jared-kushner-flet-per-projektin-e-zvernecit/",
    "Citizens.al", "Jared Kushner talks about the Zvërnec project",
    "€230M purchase, minority partner, Abehsera runs it.", "2026-10-09T00:00:00Z")

# ---------------------------------------------------------------- Flamingo Revolution
CLUSTER[0] = "flamingo"
text("h_flamingo", -3250, -120, 700, "THE FLAMINGO REVOLUTION", "headline", locked=True, rotation=0)
y = 0
y = text("f_may23", -3250, y, 300,
         "✅ **23 May 2026**\nResidents find barbed wire fencing off Pishë Poro beach in the Vjosa–Narta protected "
         "landscape, and tear it down.", tint="rose") + GAP
y = text("f_may30", -3250, y, 300,
         "✅ **30 May 2026: Zvërnec**\nPrivate guards drag away a man protesting the fence at the site. A **Major "
         "Security** guard is arrested and charged with unlawful deprivation of liberty and minor injury.", tint="rose") + GAP
text("f_minister", -3250, y, 300,
     "\"Private property security guards have no right whatsoever to use force against anyone.\"\n"
     "— Albania's Interior Minister, demanding punishment and a review of the firm's licence", "typewriter")
y = 0
y = text("f_may31", -2900, y, 300,
         "✅ **31 May 2026: Tirana**\nThousands march; clashes with police. A pink flamingo becomes the symbol. "
         "Protests spread to other cities, Kosovo and the diaspora.", tint="rose") + GAP
y = text("f_demands", -2900, y, 300,
         "THE DEMANDS\n1. Cancel the resort concession\n2. Independent SPAK probe of the contract\n"
         "3. Permanent protection for the wetlands\n4. Resignations, up to Rama's government", "typewriter") + GAP
text("f_brussels", -2900, y, 300,
     "✅ **June 2026: Brussels**\nThe European Parliament urges Albania to repeal the 2024 amendments and stop "
     "construction in protected areas (Citizens.al).", tint="rose")
y = 0
y = text("f_100days", -2550, y, 300,
         "✅ **100+ days on**\nStill going. 15 protesters face criminal proceedings; 2 security employees are under "
         "investigation. **13 Oct 2026**: students clash with police outside the Education Ministry.", tint="rose") + GAP
y = web("w_balkan", -2550, y, "https://balkaninsight.com/2026/10/13/albanian-student-protesters-clash-with-police-outside-ministry-of-education/bi/",
        "Balkan Insight", "Albanian Student Protesters Clash with Police Outside Ministry of Education",
        "The movement in its fifth month.", "2026-10-13T00:00:00Z", w=320) + GAP
y = web("w_nbc", -2550, y, "https://www.nbcnews.com/world/europe/kushner-luxury-resort-plan-protests-albania-rcna348612",
        "NBC News", "Kushner luxury resort plan sparks mass protests in Albania",
        "Thousands in Tirana; Rama defends the project.", None, w=320) + GAP
web("w_wiki", -2550, y, "https://en.wikipedia.org/wiki/Flamingo_Revolution", "Wikipedia", "Flamingo Revolution",
    "Timeline, demands and arrests.", None, w=320)

# ---------------------------------------------------------------- Israel
CLUSTER[0] = "israel"
text("h_israel", -1600, -560, 760, "ISRAEL'S ROLE? TRACED", "headline", locked=True, rotation=0)
text("i_question", -1600, -460, 340,
     "THE QUESTION\nDid Israel play a role in the Flamingo protests or the resort?\nMethod: follow each claim back "
     "to its source.", "typewriter", rotation=-0.6)
y = -200
y = text("i_c1", -1600, y, 330,
         "❌ **\"Selling the coast to Jewish billionaires and the Israeli military\"**\nAI-generated posts and fake "
         "headlines on Facebook, TikTok, Instagram and YouTube (Times of Israel). Nothing behind them.", tint="graphite") + GAP
y = text("i_c2", -1600, y, 330,
         "❌ **Video of \"Israeli soldiers beating locals\"**\nWent viral in June 2026, part of the wave of fakes the "
         "Times of Israel describes. No evidence the men are Israeli soldiers.", tint="graphite") + GAP
y = text("i_c3", -1600, y, 330,
         "❌ **Photo: a fence with Israeli and Albanian flags as a \"new border\"**\nDigitally manipulated (fact-check, "
         "June 2026).", tint="graphite") + GAP
y = -200
y = text("i_c4", -1230, y, 330,
         "❌ **\"Israel or Israeli investors are behind the project\"**\nNo reporting supports it. Filings point to the "
         "Qatar-based Al-Khayyat brothers, Kushner and Abehsera. A leader of Albania's Jewish community: *\"This has "
         "nothing to do with the Albanian Jewish community or with Israeli investors.\"*", tint="graphite") + GAP
y = text("i_c5", -1230, y, 330,
         "❌ **Were the guards Israeli?**\nThe firm at Zvërnec was **Major Security**, a private security company "
         "whose licence Albania's Interior Minister wants reviewed. No reporting on foreign ownership.", tint="graphite") + GAP
text("i_c6", -1230, y, 330,
     "⚠️ **Who spreads it?**\nLocal observers blame Russia, Iran and Turkey for stirring unrest; others call the "
     "antisemitism a false flag to discredit the protests. Neither is proven.", tint="graphite")
y = -200
y = text("i_d1", -860, y, 340,
         "✅ **Documented: Albania and Israel**\nJune 2025 defence cooperation agreement. Nov 2025: **Elbit Systems** "
         "to supply howitzers, mortars and drones, then build drones in Albania with state firm KAYO. Oct 2026: energy "
         "and cyber pact. Reporting doesn't tie any of it to the resort.", tint="teal") + GAP
y = text("i_d2", -860, y, 340,
         "✅ **Documented: Kushner and Israeli money**\nAffinity is the largest shareholder of **Phoenix Financial**. "
         "Phoenix holds about $456–465M in nine defence-linked firms, Elbit the largest (CNN, 1 Oct 2026). Kushner: "
         "\"deeply misleading\"; Affinity doesn't own those firms.", tint="teal") + GAP
text("i_d3", -860, y, 340,
     "⚠️ **Jan 2025 rumour: Albania to take 100,000 Gazans**\nFrom an Israeli journalist's post. Rama: *\"I haven't heard "
     "something so false in a long time.\"*", tint="teal")
text("i_verdict", -1600, 780, 420,
     "VERDICT, 15 OCT 2026\nNo credible reporting shows Israel (its government, military or Israeli investors) "
     "organising, funding or policing the protests, or owning the resort. Inside the protests, the 'Israeli role' "
     "lives in fakes.\nThe real threads run elsewhere: Elbit arms for Albania, and Kushner's Phoenix stake. They meet "
     "at Elbit, not at Zvërnec.", "typewriter", rotation=0.4)
y = 700
y = web("w_toi", -1130, y, "https://www.timesofisrael.com/albanian-protests-against-jared-kushner-resort-development-see-emerging-antisemitism/",
        "The Times of Israel", "'They're selling the coast to Jewish billionaires and IDF'",
        "Antisemitic fakes on the fringes of the Albanian protests.", None) + GAP
y = -200 + 4 * 220
web("w_haaretz", -760, 820, "https://www.haaretz.com/israel-news/security-aviation/2025-11-12/ty-article/.premium/israel-albania-strengthen-ties-as-elbit-to-provide-it-with-artillery-mortars-and-drones/0000019a-78d7-d326-a3ff-fcdf3d180000",
    "Haaretz", "Israel and Albania Strengthen Ties as Elbit to Provide It With Artillery, Mortars and Drones",
    "ATMOS howitzers, SPEAR mortars, drones; production in Albania.", "2025-11-12T00:00:00Z")

# ---------------------------------------------------------------- Billions
CLUSTER[0] = "billions"
text("h_billions", 520, -1500, 600, "THE BILLIONS", "headline", locked=True, rotation=0)
y = -1390
y = text("b_pif", 520, y, 320,
         "✅ **$2 billion: Saudi PIF (2021)**\nPIF's own advisory panel objected: inexperienced team, \"excessive\" "
         "fees, PR risk (minutes, 30 Jun 2021). The board, chaired by MBS, overruled it days later (NYT, Apr 2022).",
         tint="teal") + GAP
y = text("b_gulf", 520, y, 320,
         "✅ **Qatar and Abu Dhabi**\nQatar's QIA and Abu Dhabi's Lunate: **$539M** combined by March 2022. Later "
         "reporting: UAE- and Qatar-linked firms, at least **$1.5B**.", tint="teal") + GAP
text("b_fees", 520, y, 320,
     "⚠️ **Fees and fresh money**\nReported: about **$157M** in fees from foreign investors (about $87M Saudi), and "
     "about $5B more sought or raised in the Gulf while he serves as envoy. Accounts and figures differ.", tint="teal")
y = -1390
y = text("b_ea", 880, y, 320,
         "✅ **$55 billion: Electronic Arts**\nTaken private by **PIF, Silver Lake and Affinity**. Announced 29 Sep "
         "2025, closed **4 Aug 2026**: $210 a share, $20B of JPMorgan debt. Called the largest all-cash sponsor "
         "take-private ever.", tint="red") + GAP
y = text("b_phoenix", 880, y, 320,
         "✅ **About $1.06 billion: Phoenix Financial (Israel)**\nBought 4.95% for $128.5M (Jul 2024); nearly 10% "
         "approved Jan 2025, just before the inauguration; sold about 2.5% for about $343M (Jul 2026). Keeps **7.4%**.",
         tint="red") + GAP
text("b_wbd", 880, y, 320,
     "⚠️ **$108.4B: Paramount's bid for Warner Bros. Discovery**\nAffinity joined in Oct 2025 with about $200M of "
     "equity, then **withdrew on 16 Dec 2025**. Trump had said he would personally review the deal.", tint="red")
y = -1390
y = text("b_belgrade", 1240, y, 320,
         "⚠️ **About $500M: Belgrade, Serbia**\nA Trump-branded hotel on the bombed Army headquarters. Affinity "
         "**withdrew on 15 Dec 2025**, hours after Culture Minister Nikola Selaković was indicted over lifting the "
         "site's heritage protection.", tint="red") + GAP
y = text("b_gaza", 1240, y, 320,
         "⚠️ **Gaza: the Board of Peace**\nKushner sits on its founding executive board (Jan 2026). Rep. Raskin's "
         "letter (16 Apr 2026): envoy role plus Gulf investors means conflicts of interest. Senators question a Gaza "
         "stablecoin plan (17 Apr 2026).", tint="amber") + GAP
text("b_quote", 1240, y, 320,
     "\"What people call conflicts of interest, Steve and I call experience.\"\n— Jared Kushner, 2025, on himself "
     "and envoy Steve Witkoff", "typewriter")
y = -1390
y = web("w_pif", 1600, y, "https://politicalwire.com/2022/04/10/saudi-investment-fund-had-big-doubts-about-kushner/",
        "Political Wire", "Saudi Investment Fund Had Big Doubts About Kushner",
        "On the NYT report: advisers objected, MBS's board overruled.", "2022-04-10T00:00:00Z") + GAP
y = web("w_ea", 1600, y, "https://www.ea.com/news/ea-announces-completion-of-acquisition", "Electronic Arts",
        "EA Announces Completion of Acquisition by PIF, Silver Lake, and Affinity Partners",
        "$210 per share; EA leaves Nasdaq.", "2026-08-04T00:00:00Z") + GAP
y = web("w_cnn", 1600, y, "https://www.cnn.com/2026/10/01/us/jared-kushner-israel-gaza-investments-invs-vis", "CNN",
        "Jared Kushner's company has large stake in firm with Israeli military links",
        "Phoenix's holdings in nine defence-linked companies.", "2026-10-01T00:00:00Z") + GAP
y = web("w_wbd", 1600, y, "https://storyboard18.com/ott-news/kushner-linked-firm-exits-paramounts-hostile-bid-for-warner-bros-discovery-86046.htm",
        "Storyboard18", "Kushner-linked firm exits Paramount's hostile bid for Warner Bros. Discovery",
        "Affinity's roughly $200M stake pulled.", "2025-12-16T00:00:00Z") + GAP
y = web("w_n1", 1600, y, "https://n1info.rs/english/news/affinity-partners-tells-n1-it-is-pulling-out-of-project/", "N1",
        "Affinity Partners tells N1 it is pulling out of project", "Belgrade General Staff plan dropped.",
        "2025-12-15T00:00:00Z") + GAP
web("w_raskin", 1600, y, "https://democrats-judiciary.house.gov/sites/evo-subsites/democrats-judiciary.house.gov/files/evo-media-document/2026-04-16-raskin-to-kushner-affinity-re-conflict-of-interest.pdf",
    "House Judiciary Democrats", "Raskin to Kushner and Affinity re: conflict of interest",
    "Letter to the \"Special Envoy for Peace\", 16 Apr 2026.", "2026-04-16T00:00:00Z")

# ---------------------------------------------------------------- The envoy
CLUSTER[0] = "envoy"
text("h_envoy", 650, -880, 620, "THE ENVOY: STEVE WITKOFF", "headline", locked=True, rotation=0)
text("witkoff", 650, -760, 300,
     "**STEVE WITKOFF**\nNew York real-estate developer (Witkoff Group) and longtime friend of Trump. U.S. Special "
     "Envoy to the Middle East since Jan 2025, and Trump's go-between with Putin. Works side by side with Kushner "
     "(NPR).", tint="azure")
text("e_duo", 650, -500, 320,
     "✅ **The duo: Gaza and Moscow**\nWith Kushner on the Gaza ceasefire and the Board of Peace (both named by the "
     "White House, Jan 2026; signed at Davos, 22 Jan). Five hours with Putin in the Kremlin on 2 Dec 2025 over the "
     "Ukraine plan (Axios); more Moscow trips in 2026.", tint="azure")
text("e_wlf", 650, -200, 320,
     "✅ **World Liberty Financial**\nCrypto venture founded by Trump and his sons with Witkoff and his sons. May 2025: "
     "Zach Witkoff announces its **USD1** stablecoin will carry Abu Dhabi fund MGX's **$2 billion** investment in "
     "Binance. The reserves can earn the issuer tens of millions in interest.", tint="red")
text("e_ethics", 650, 100, 320,
     "⚠️ **Conflict-of-interest questions**\nSenators Warren and Merkley asked the ethics office to investigate "
     "(2025). Democrats note Witkoff worked on a U.S.–UAE AI deal while World Liberty dealt with the Emirati fund. "
     "Fortune (Oct 2025): he still held World Liberty crypto and shares in WC Digital Fi LLC. No official finding "
     "found.", tint="red")
text("e_qatar", 650, 400, 320,
     "✅ **Qatar bought his hotel**\nAug 2023: Qatar's sovereign fund (QIA) paid about **$623M** for Manhattan's Park "
     "Lane Hotel, owned by the Witkoff Group with Abu Dhabi's Mubadala (Commercial Observer). The same Qatari fund "
     "invested in Kushner's Affinity.", tint="teal")
text("e_telegraph", 1050, -760, 320,
     "⚠️ **The Telegraph, Oct 2026**\nReports overlapping business interests between Kushner, Witkoff and Apollo's "
     "Marc Rowan, who all help steer Gaza's rebuilding through the Board of Peace. The Board calls it baseless; no "
     "deal through the Board has been shown.", tint="amber")
text("e_albania", 1050, -460, 320,
     "❌ **Witkoff and Albania?**\nTraced: no reporting ties him to Sazan, Zvërnec or the companies behind them. He "
     "turns up only in commentary that pairs him with Kushner. Not on the project's ownership chain.", tint="graphite")
web("w_npr", 1050, -200, "https://www.npr.org/2025/04/25/nx-s1-5364884/trump-witkoff-russia-iran-middle-east", "NPR",
    "Meet Steve Witkoff, Trump's negotiator with Iran, Russia and the Middle East",
    "From real estate to envoy.", "2025-04-25T00:00:00Z")
web("w_axios", 1050, 100, "https://www.axios.com/2025/12/02/putin-witkoff-kushner-meeting-ukraine-plan", "Axios",
    "Witkoff and Kushner met Putin for five hours on Ukraine plan", "Kremlin talks on the U.S. peace plan.",
    "2025-12-02T00:00:00Z")
web("w_kitco", 1450, -760, "https://www.kitco.com/news/off-the-wire/2025-05-01/trumps-stablecoin-chosen-2-billion-abu-dhabi-investment-binance-co",
    "Kitco", "Trump's stablecoin chosen for $2 billion Abu Dhabi investment in Binance, co-founder says",
    "Zach Witkoff announces USD1 for MGX's deal.", "2025-05-01T00:00:00Z")
web("w_merkley", 1450, -460, "https://www.merkley.senate.gov/?p=22101", "Sen. Jeff Merkley",
    "Merkley, Warren: Trump-Linked Crypto Deal is a 'Staggering' Conflict of Interest",
    "Request for an ethics investigation.", "2025-05-01T00:00:00Z")
web("w_qia", 1450, -160, "https://commercialobserver.com/2023/08/qatar-sovereign-fund-acquires-park-lane-hotel-for-623m/",
    "Commercial Observer", "Qatar Sovereign Fund Acquires Park Lane Hotel for $623M",
    "Bought from the Witkoff Group and Mubadala.", "2023-08-28T00:00:00Z")
web("w_telegraph", 1450, 140, "https://www.yahoo.com/news/politics/articles/billion-dollar-conflicts-threatening-tear-050000648.html",
    "Yahoo News", "The billion-dollar conflicts threatening to tear apart Trump's board of peace",
    "The Telegraph's investigation.", "2026-10-13T00:00:00Z")

# ---------------------------------------------------------------- Strings
# Family and politics
string("trump", "kushner", "azure", "son-in-law, envoy", arrow="forward")
string("trump", "ivanka", "azure", "daughter", arrow="forward")
string("ivanka", "kushner", "rose", "married", thickness=2.5)
string("ivanka", "rama", "azure", "dinner, Vlorë, 21 Jan 2026")
string("rama", "sazan", "azure", "chaired approval", arrow="forward")
string("rama", "law", "azure", "passed under Rama", style="dashed")
string("trump", "sazan", "amber", "3 weeks before inauguration", style="dashed", thickness=1.5)
string("trump", "b_gaza", "azure", "created it", arrow="forward")
string("trump", "b_wbd", "azure", "\"I'll review it\"", style="dashed", thickness=1.5)
string("rama", "i_d3", "azure", "denied", style="dashed", thickness=1.5)
string("f_demands", "rama", "rose", "resign", arrow="forward", style="dashed")
# Money and ownership
string("kushner", "affinity", "red", "founder & CEO", thickness=3)
string("mbs", "b_pif", "teal", "board overruled advisers", arrow="forward")
string("b_pif", "affinity", "red", "$2B", arrow="forward", thickness=3)
string("b_gulf", "affinity", "red", "$539M+", arrow="forward")
string("affinity", "b_ea", "red", "co-owner", arrow="forward")
string("b_pif", "b_ea", "red", "co-owner", arrow="forward")
string("affinity", "b_phoenix", "red", "7.4% · ~$1.06B", arrow="forward", thickness=2.5)
string("b_phoenix", "i_d2", "red", "holds Elbit shares")
string("affinity", "b_wbd", "red", "withdrew", style="dashed")
string("affinity", "b_belgrade", "red", "withdrew", style="dashed")
string("kushner", "b_gaza", "amber", "executive board")
string("kushner", "abehsera", "violet", "business partner", thickness=2.5)
string("abehsera", "developer", "violet", "chairs SRED", arrow="forward")
string("khayyat", "developer", "lime", "majority owners", arrow="forward", thickness=2.5)
string("khayyat", "freeze", "lime", "Albania Land Development")
string("developer", "zvernec", "red", "develops", arrow="forward")
string("affinity", "sazan", "red", "Atlantic Incubation Partners", style="dashed")
string("affinity", "developer", "red", "\"not the developer\"", style="dashed", thickness=1.5)
string("kushner", "zvernec", "red", "his partnership's €230M buy", arrow="forward")
string("zvernec", "kushner_account", "graphite", thickness=1.2)
string("spak", "zvernec", "amber", "probing land titles", arrow="forward")
string("spak", "freeze", "amber", thickness=1.5)
string("law", "zvernec", "amber", "opened protected areas", style="dashed")
string("map", "sazan", "graphite", thickness=1.2)
string("map", "zvernec", "graphite", thickness=1.2)
# The protests
string("zvernec", "f_may30", "rose", "fence → assault", arrow="forward", thickness=2.5)
string("f_may23", "f_may30", "rose", arrow="forward")
string("f_may30", "f_may31", "rose", "next day", arrow="forward")
string("f_may31", "f_100days", "rose", arrow="forward")
string("f_may31", "f_demands", "rose")
string("f_may30", "f_minister", "graphite", thickness=1.2)
string("f_brussels", "law", "rose", "repeal it", arrow="forward", style="dashed")
# Israel, traced
string("f_may31", "i_question", "rose", "claims spread online", style="dotted")
string("i_question", "i_c1", "graphite", style="dotted", thickness=1.5)
string("i_question", "i_c4", "graphite", style="dotted", thickness=1.5)
string("i_c1", "i_verdict", "graphite", style="dotted", thickness=1.5)
string("i_c3", "i_verdict", "graphite", style="dotted", thickness=1.5)
string("i_c4", "khayyat", "lime", "actual owners", style="dashed")
string("i_c5", "f_may30", "graphite", "Major Security", style="dotted", thickness=1.5)
string("i_d1", "i_d2", "teal", "meet at Elbit, not Zvërnec", style="dashed", thickness=2.5)
string("i_d1", "i_verdict", "teal", style="dotted", thickness=1.5)
string("i_d2", "i_verdict", "teal", style="dotted", thickness=1.5)
# The envoy
string("trump", "witkoff", "azure", "friend, envoy", arrow="forward")
string("witkoff", "kushner", "azure", "the duo", thickness=2.5)
string("witkoff", "e_duo", "azure")
string("witkoff", "b_quote", "graphite", "\"Steve and I\"", style="dashed", thickness=1.5)
string("witkoff", "e_wlf", "red", "co-founder, with sons", arrow="forward", thickness=2.5)
string("trump", "e_wlf", "red", "co-founder, with sons", arrow="forward")
string("e_wlf", "e_ethics", "red")
string("e_wlf", "b_gaza", "red", "USD1 for Gaza? (senators)", style="dashed")
string("witkoff", "e_qatar", "teal", "sold to QIA", arrow="forward")
string("b_gulf", "e_qatar", "teal", "same Qatari fund", style="dashed")
string("witkoff", "e_telegraph", "amber")
string("e_telegraph", "b_gaza", "amber", style="dashed", thickness=1.5)
string("witkoff", "e_albania", "graphite", "traced", style="dotted", thickness=1.5)
string("e_albania", "developer", "graphite", "not in the ownership chain", style="dotted", thickness=1.5)
# Sources
for card, source in [
    ("sazan", "w_aljazeera"), ("developer", "w_exit"), ("freeze", "w_occrp"), ("spak", "w_koha"),
    ("kushner_account", "w_citizens"), ("f_100days", "w_balkan"), ("f_may31", "w_nbc"), ("f_may23", "w_wiki"),
    ("i_c1", "w_toi"), ("i_d1", "w_haaretz"), ("b_pif", "w_pif"), ("b_ea", "w_ea"), ("b_phoenix", "w_cnn"),
    ("b_wbd", "w_wbd"), ("b_belgrade", "w_n1"), ("b_gaza", "w_raskin"),
    ("witkoff", "w_npr"), ("e_duo", "w_axios"), ("e_wlf", "w_kitco"), ("e_ethics", "w_merkley"), ("e_qatar", "w_qia"),
    ("e_telegraph", "w_telegraph"),
]:
    string(card, source, "graphite", thickness=1.2, sag=0.3)

# ---------------------------------------------------------------- Layout and output
from layout import optimize

for card in cards:
    if card["_name"] in ("abehsera", "khayyat"):
        card["_cluster"] = "albania"
    if card["_name"].startswith("h_") or card["_name"] in ("title", "subtitle", "legend"):
        card["_cluster"] = "fixed"
REGIONS = {  # cluster: (x0, y0, x1, y1), below each heading
    "albania": (-4600, -2620, -2300, -1180),
    "people": (-1950, -2620, 300, -1930),
    "billions": (650, -2620, 2950, -1080),
    "flamingo": (-4600, -760, -2350, 600),
    "israel": (-1950, -1560, 300, 240),
    "envoy": (650, -760, 2950, 600),
}
FIXED = {
    "title": (-1700, -3120), "subtitle": (-1700, -3030), "legend": (-880, -3130),
    "h_albania": (-4600, -2740), "h_flamingo": (-4600, -880), "h_israel": (-1950, -1690), "h_billions": (650, -2740),
    "h_envoy": (650, -880),
}
for card in cards:
    spot = FIXED.get(card["_name"])
    if spot:
        card["frame"]["x"], card["frame"]["y"] = spot
optimize(cards, strings, REGIONS, iterations=int(sys.argv[3]) if len(sys.argv) > 3 else 90000, seed=int(sys.argv[4]) if len(sys.argv) > 4 else 2)

ids = {c["id"] for c in cards}
for s in strings:
    assert s["from"] in ids and s["to"] in ids, s
xs = [c["frame"]["x"] for c in cards] + [c["frame"]["x"] + c["frame"]["width"] for c in cards]
ys = [c["frame"]["y"] for c in cards] + [c["frame"]["y"] + c["frame"]["height"] for c in cards]
print("bounds", min(xs), min(ys), max(xs), max(ys))
for card in cards:
    card["frame"] = {k: int(round(v)) for k, v in card["frame"].items()}
    del card["_name"], card["_cluster"]

board = {
    "format": "evidenceboard", "formatVersion": 1, "id": uid("board"), "title": "The Albania Files",
    "createdAt": NOW, "modifiedAt": NOW, "theme": "cork",
    "viewport": {"x": (min(xs) + max(xs)) / 2, "y": (min(ys) + max(ys)) / 2 + 60, "zoom": 0.13},
    "cards": cards, "strings": strings, "assets": assets,
}
with open(OUT, "w") as f:
    json.dump(board, f, ensure_ascii=False, indent=1, sort_keys=True)
print(len(cards), "cards,", len(strings), "strings ->", OUT)
