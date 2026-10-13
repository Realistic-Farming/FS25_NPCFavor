#!/usr/bin/env python3
"""BUILD 15:39 / PB-14 - add the player-facing startup notice string.

The old startup line was a red blinking warning telling the player to type
`npcHelp` in the console. It is replaced by a player-language notice on the
shared MasterHUD notice queue, which needs one new l10n key: npc_notice_loaded.

Translations here are the plain "mod is ready" sentence, carrying the version
via %s. Languages without a hand-written translation fall back to English
rather than shipping a machine-mangled sentence; the Lua guards with hasText so
a missing key can never render as a raw id.

Files are decoded utf-8-sig and written back as plain UTF-8 with no BOM.
"""

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEY = "npc_notice_loaded"

EN = "NPC Favor v%s ready. Your neighbours are settling in."

TEXTS = {
    "en": EN,
    "de": "NPC Favor v%s bereit. Deine Nachbarn richten sich ein.",
    "fr": "NPC Favor v%s est prêt. Vos voisins s'installent.",
    "es": "NPC Favor v%s listo. Tus vecinos se están instalando.",
    "ea": "NPC Favor v%s listo. Tus vecinos se están instalando.",
    "it": "NPC Favor v%s pronto. I tuoi vicini si stanno sistemando.",
    "nl": "NPC Favor v%s is klaar. Je buren richten zich in.",
    "pl": "NPC Favor v%s gotowy. Twoi sąsiedzi się zadomawiają.",
    "pt": "NPC Favor v%s pronto. Os seus vizinhos estão a instalar-se.",
    "br": "NPC Favor v%s pronto. Seus vizinhos estão se instalando.",
    "ru": "NPC Favor v%s готов. Ваши соседи обживаются.",
    "uk": "NPC Favor v%s готовий. Ваші сусіди облаштовуються.",
    "cz": "NPC Favor v%s připraven. Vaši sousedé se zabydlují.",
    "da": "NPC Favor v%s er klar. Dine naboer falder til.",
    "no": "NPC Favor v%s er klar. Naboene dine faller til ro.",
    "sv": "NPC Favor v%s är klart. Dina grannar installerar sig.",
    "fi": "NPC Favor v%s valmis. Naapurisi asettuvat taloksi.",
    "hu": "NPC Favor v%s kész. A szomszédaid berendezkednek.",
    "ro": "NPC Favor v%s gata. Vecinii tăi se instalează.",
    "tr": "NPC Favor v%s hazır. Komşularınız yerleşiyor.",
}


def read(path):
    return path.read_bytes().decode("utf-8-sig")


def write(path, text):
    path.write_bytes(text.encode("utf-8"))


def main():
    changed, skipped = [], []
    files = sorted(HERE.glob("lang_*.xml"))
    if not files:
        print("no lang_*.xml found")
        return 1

    for path in files:
        lang = path.stem.split("_", 1)[1]
        body = read(path)

        if 'name="%s"' % KEY in body:
            skipped.append(path.name)
            continue

        value = TEXTS.get(lang, EN)
        # XML-escape the value; the sentences carry no markup but this keeps the
        # writer honest if one ever gains an ampersand.
        value = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        entry = '\t\t<text name="%s" text="%s" />\n' % (KEY, value)

        new = re.sub(r"([ \t]*)</texts>", entry + r"\1</texts>", body, count=1)
        if new == body:
            print("could not find </texts> in %s" % path.name)
            return 1
        write(path, new)
        changed.append(path.name)

    print("added %s to %d file(s), %d already had it" % (KEY, len(changed), len(skipped)))

    # Verify: every shipped language file must now carry the key exactly once.
    bad = []
    for path in files:
        n = read(path).count('name="%s"' % KEY)
        if n != 1:
            bad.append("%s: %d occurrences" % (path.name, n))
    if bad:
        print("VERIFY FAILED:")
        for b in bad:
            print("  " + b)
        return 1
    print("verified: %s present exactly once in all %d language files" % (KEY, len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
