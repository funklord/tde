#include "probe.h"
#include <tqtimer.h>
#include <tqdbusconnection.h>
#include <tqdbusproxy.h>

int main(int argc, char **argv) {
	TQApplication app(argc, argv, false);          // no GUI, no X needed
	TQT_DBusConnection c = TQT_DBusConnection::sessionBus();
	if (!c.isConnected()) { printf("no session bus\n"); return 2; }

	// Exactly the construction ScreenSaverDBusWatcher uses in PR 779.
	TQT_DBusProxy *proxy = new TQT_DBusProxy(
	    "org.freedesktop.DBus", "/org/freedesktop/DBus",
	    "org.freedesktop.DBus", c);

	Probe p;
	TQObject::connect(proxy, TQ_SIGNAL(dbusSignal(const TQT_DBusMessage&)),
	                  &p,    TQ_SLOT(onSignal(const TQT_DBusMessage&)));

	TQTimer::singleShot(6000, &p, TQ_SLOT(done()));   // hard stop, always exits
	printf("probe: listening 6s via TQT_DBusProxy\n"); fflush(stdout);
	return app.exec();
}
