/*
 * Exercises screen::externalDisplayConnected() from tdepowersave itself.
 * It links the object the real build produced rather than reimplementing
 * the query, so a second copy of the logic cannot drift from the first.
 *
 * Expected: false on a laptop panel alone, true where the only output is
 * not named like a built-in panel -- which is what Xvfb provides.
 */
#include <tqapplication.h>
#include "screen.h"
#include <cstdio>

// Defined in tdepowersave's main.cpp, which this probe does not link.
bool trace = false;

int main(int argc, char **argv)
{
	TQApplication app(argc, argv);
	screen s;
	bool docked = s.externalDisplayConnected();
	printf("externalDisplayConnected() = %s\n", docked ? "true" : "false");

	TQString panel;
	bool found = s.internalPanelOutput(panel);
	printf("internalPanelOutput()      = %s%s%s\n",
	       found ? "true (" : "false",
	       found ? panel.latin1() : "",
	       found ? ")" : "");
	printf("enabledOutputCount()       = %d\n", s.enabledOutputCount());
	printf("internalPanelIsOff()       = %s\n",
	       s.internalPanelIsOff() ? "true" : "false");

	/*
	 * Exercise the refusal path of the state-changing code for real. On a
	 * server with no output that looks like a panel, or with only one output
	 * being driven, disableInternalPanel() must decline and change nothing.
	 * Only run where it is guaranteed to refuse -- pass --try-disable to say
	 * so explicitly, so this cannot go off by accident on a real desktop.
	 */
	if (argc > 1 && TQString(argv[1]) == "--try-disable") {
		int before = s.enabledOutputCount();
		bool acted = s.disableInternalPanel();
		int after = s.enabledOutputCount();
		printf("disableInternalPanel()     = %s\n", acted ? "true" : "false");
		printf("  enabled outputs %d -> %d%s\n", before, after,
		       (before == after) ? "  (unchanged, as required)" : "  CHANGED");
		if (acted || before != after) {
			printf("FAIL: it acted where it should have refused\n");
			return 2;
		}
		printf("PASS: refused and changed nothing\n");

		/* restore with nothing recorded, and heal with no panel present */
		bool restored = s.restoreInternalPanel();
		bool healed = s.healInternalPanel();
		printf("restoreInternalPanel()     = %s\n", restored ? "true" : "false");
		printf("healInternalPanel()        = %s\n", healed ? "true" : "false");
		int end = s.enabledOutputCount();
		printf("  enabled outputs now %d%s\n", end,
		       (end == before) ? "  (still unchanged)" : "  CHANGED");
		if (restored || healed || end != before) {
			printf("FAIL: one of them acted where it should have refused\n");
			return 2;
		}
		printf("PASS: all three refused and the display is untouched\n");
	}

	return docked ? 0 : 1;
}
