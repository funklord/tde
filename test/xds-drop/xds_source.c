/*
 * xds_source X Y NAME -- act as an XDND drag source offering only
 * XdndDirectSave0 (XDS protocol version 0), drop at root position X,Y, and
 * write the file wherever the target asks. Prints each protocol step.
 *
 * Bounded: alarm(20) ends it whatever the target does. One window, no
 * children, no files other than the one the target names.
 */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static Display *dpy;
static Atom a_aware, a_enter, a_position, a_status, a_drop, a_finished;
static Atom a_selection, a_xds, a_text, a_copy, a_targets;

static Atom atom(const char *name) { return XInternAtom(dpy, name, False); }

static void send_client(Window to, Atom type, long l0, long l1, long l2, long l3, long l4)
{
	XEvent e;
	memset(&e, 0, sizeof(e));
	e.xclient.type = ClientMessage;
	e.xclient.window = to;
	e.xclient.message_type = type;
	e.xclient.format = 32;
	e.xclient.data.l[0] = l0;
	e.xclient.data.l[1] = l1;
	e.xclient.data.l[2] = l2;
	e.xclient.data.l[3] = l3;
	e.xclient.data.l[4] = l4;
	XSendEvent(dpy, to, False, NoEventMask, &e);
	XFlush(dpy);
}

/* The XdndAware window under X,Y, searching from the top-level down. */
static Window find_target(int x, int y, long *version)
{
	Window w = DefaultRootWindow(dpy), child;
	int cx, cy;
	while (XTranslateCoordinates(dpy, DefaultRootWindow(dpy), w, x, y, &cx, &cy, &child) && child != None) {
		Atom type; int format; unsigned long n, rest; unsigned char *data = NULL;
		if (XGetWindowProperty(dpy, child, a_aware, 0, 1, False, AnyPropertyType,
		                       &type, &format, &n, &rest, &data) == Success && data && n > 0) {
			*version = *(long *) data;
			XFree(data);
			return child;
		}
		if (data) XFree(data);
		w = child;
	}
	return None;
}

/* "file://host/path" with %XX escapes -> "/path". */
static void url_to_path(const char *url, char *out, size_t cap)
{
	const char *p = url;
	size_t o = 0;
	if (strncmp(p, "file://", 7) == 0) {
		p += 7;
		p = strchr(p, '/');
		if (!p) { out[0] = 0; return; }
	}
	while (*p && o + 1 < cap) {
		if (p[0] == '%' && p[1] && p[2]) {
			char hex[3] = { p[1], p[2], 0 };
			out[o++] = (char) strtol(hex, NULL, 16);
			p += 3;
		} else {
			out[o++] = *p++;
		}
	}
	out[o] = 0;
}

int main(int argc, char **argv)
{
	if (argc != 4) { fprintf(stderr, "usage: xds_source X Y NAME\n"); return 2; }
	alarm(20);
	setvbuf(stdout, NULL, _IOLBF, 0);
	int x = atoi(argv[1]), y = atoi(argv[2]);
	dpy = XOpenDisplay(NULL);
	if (!dpy) { fprintf(stderr, "no display\n"); return 1; }
	a_aware = atom("XdndAware"); a_enter = atom("XdndEnter");
	a_position = atom("XdndPosition"); a_status = atom("XdndStatus");
	a_drop = atom("XdndDrop"); a_finished = atom("XdndFinished");
	a_selection = atom("XdndSelection"); a_xds = atom("XdndDirectSave0");
	a_text = atom("text/plain"); a_copy = atom("XdndActionCopy");
	a_targets = atom("TARGETS");

	Window src = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 0, 0, 1, 1, 0, 0, 0);
	XSelectInput(dpy, src, PropertyChangeMask);
	if (getenv("XDS_FORMAT32")) {
		/* A malformed offer: the name as 32-bit items. */
		long packed[64] = { 0 };
		size_t len = strlen(argv[3]);
		if (len > sizeof(packed) - 1)
			len = sizeof(packed) - 1;
		memcpy(packed, argv[3], len);
		XChangeProperty(dpy, src, a_xds, a_text, 32, PropModeReplace,
		                (unsigned char *) packed, (len + 3) / 4);
	} else {
		XChangeProperty(dpy, src, a_xds, a_text, 8, PropModeReplace,
		                (unsigned char *) argv[3], strlen(argv[3]));
	}
	XSetSelectionOwner(dpy, a_selection, src, CurrentTime);

	long version = 0;
	Window target = find_target(x, y, &version);
	if (target == None) { printf("no XdndAware window at %d,%d\n", x, y); return 1; }
	if (version > 5) version = 5;
	printf("target 0x%lx, XDND version %ld\n", target, version);

	send_client(target, a_enter, src, version << 24, a_xds, None, None);
	/* Two positions, as a moving pointer sends: Qt3's views ignore a move
	 * that reports the same point as the enter. */
	send_client(target, a_position, src, 0, ((x - 8) << 16) | (y - 8), CurrentTime, a_copy);

	int dropped = 0, statuses = 0;
	for (;;) {
		XEvent e;
		XNextEvent(dpy, &e);
		if (e.type == ClientMessage && e.xclient.message_type == a_status) {
			printf("status: %s\n", (e.xclient.data.l[1] & 1) ? "accepts" : "refuses");
			if (++statuses == 1) {
				send_client(target, a_position, src, 0, (x << 16) | y, CurrentTime, a_copy);
			} else if (!dropped) {
				dropped = 1;
				send_client(target, a_drop, src, 0, CurrentTime, 0, 0);
				printf("dropped\n");
			}
		} else if (e.type == ClientMessage && e.xclient.message_type == a_finished) {
			printf("finished\n");
			break;
		} else if (e.type == SelectionRequest) {
			XSelectionRequestEvent *r = &e.xselectionrequest;
			XSelectionEvent n;
			memset(&n, 0, sizeof(n));
			n.type = SelectionNotify;
			n.requestor = r->requestor;
			n.selection = r->selection;
			n.target = r->target;
			n.time = r->time;
			n.property = r->property != None ? r->property : r->target;
			char *tname = XGetAtomName(dpy, r->target);
			printf("request for %s\n", tname);
			if (r->target == a_xds) {
				Atom type; int format; unsigned long cnt, rest; unsigned char *data = NULL;
				char path[4096] = "";
				if (XGetWindowProperty(dpy, src, a_xds, 0, 4096, False, AnyPropertyType,
				                       &type, &format, &cnt, &rest, &data) == Success && data) {
					printf("target asked to save to %.*s\n", (int) cnt, data);
					char url[4096];
					snprintf(url, sizeof(url), "%.*s", (int) cnt, data);
					url_to_path(url, path, sizeof(path));
					XFree(data);
				}
				char result = 'E';
				const char *forced = getenv("XDS_ANSWER");
				FILE *f = (path[0] && !forced) ? fopen(path, "w") : NULL;
				if (forced)
					result = forced[0];
				if (f) {
					fputs("written by xds_source\n", f);
					fclose(f);
					result = 'S';
				}
				printf("answering %c\n", result);
				XChangeProperty(dpy, r->requestor, n.property, XA_STRING, 8,
				                PropModeReplace, (unsigned char *) &result, 1);
			} else if (r->target == a_targets) {
				Atom list[2] = { a_targets, a_xds };
				XChangeProperty(dpy, r->requestor, n.property, XA_ATOM, 32,
				                PropModeReplace, (unsigned char *) list, 2);
			} else {
				n.property = None;
			}
			if (tname) XFree(tname);
			XSendEvent(dpy, r->requestor, False, NoEventMask, (XEvent *) &n);
			XFlush(dpy);
		}
	}
	XCloseDisplay(dpy);
	return 0;
}
