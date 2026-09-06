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
	return docked ? 0 : 1;
}
