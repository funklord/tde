# Standalone: needs no X server and no TDE session, only a session bus.
CXXFLAGS = -I/usr/include/tqt $(shell pkg-config --cflags dbus-1-tqt tqt-mt)
LDLIBS   = $(shell pkg-config --libs dbus-1-tqt tqt-mt)

.PHONY: test clean

probe: probe.cpp moc_probe.cpp probe.h
		$(CXX) -o $@ probe.cpp moc_probe.cpp $(CXXFLAGS) $(LDLIBS)

moc_probe.cpp: probe.h
		tmoc $< -o $@

# The control matters: "received 0" and "nothing was emitted" look identical.
test: probe
		@timeout 8 dbus-monitor --session \
			"type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged'" \
			> control.log 2>&1 & \
		 ./probe & p=$$!; sleep 2; \
		 for i in 1 2 3 4; do \
			dbus-send --session --dest=org.freedesktop.DBus --print-reply \
				/org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1; \
		 done; \
		 wait $$p; \
		 echo "control saw: $$(grep -c NameOwnerChanged control.log)"

clean:
		rm -f probe moc_probe.cpp control.log
