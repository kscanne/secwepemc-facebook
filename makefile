# Makefile for secwepemc-facebook
# Copyright 2012 Kevin Scannell
# License: GPLv3+

all: updategms INSTALL.textile

updatepos: strings.txt header.pot buildpot.sh
	ls po | sed 's/\.po//' | while read x; do echo "Updating $$x..."; bash buildpot.sh $$x; msgmerge -q --backup=off -U po/$$x.po facebook.pot > /dev/null 2>&1; done
	sed -i '/^#~/,$$d' po/*.po
	sed -i '$${/^#, fuzzy$$/d}' po/*.po
	sed -i '$${/^$$/d}' po/*.po

updategms: facebook-ga.user.js

# builds all languages
facebook-ga.user.js: po/*.po template.user.js po2gm.pl generate-gm.sh LINGUAS template.json
	bash generate-gm.sh

INSTALL.textile: LINGUAS INSTALL-template
	cat LINGUAS | egrep -v 'Alternate source' | sed 's/\t/ | /g' | sed 's/^/| /; s/$$/ |/' | sed 's/\(https\?:\/\/\(userscripts.org\|www.sorbzilla\)[^ ,]*\)/"Firefox":&/g; s/\(https\?:\/\/chrome.google.com[^ ,]*\)/"Chrome":&/g' > table.txt
	sed '/^|_\./r table.txt' INSTALL-template > $@
	rm -f table.txt

clean:
	rm -f facebook.pot facebook-*.user.js INSTALL.textile

FORCE:
