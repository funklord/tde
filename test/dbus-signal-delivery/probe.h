#ifndef SIGPROBE_H
#define SIGPROBE_H
#include <tqobject.h>
#include <tqapplication.h>
#include <tqdbusmessage.h>
#include <cstdio>

class Probe : public TQObject {
	TQ_OBJECT
public:
	int seen;
	Probe() : seen(0) {}
public slots:
	void onSignal(const TQT_DBusMessage &m) {
		if (m.member() == "NameOwnerChanged" && m.count() >= 3) {
			++seen;
			printf("  RECEIVED NameOwnerChanged for %s\n", m[0].toString().ascii());
			fflush(stdout);
		}
	}
	void done() {
		printf("RESULT: NameOwnerChanged received = %d\n", seen);
		fflush(stdout);
		tqApp->quit();
	}
};
#endif
