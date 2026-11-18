// Print what libtderandr reports for each output: is it primary, active.
#include <stdio.h>
#include <tdeapplication.h>
#include <tdecmdlineargs.h>
#include <tdeaboutdata.h>
#include "libtderandr.h"
int main(int argc, char **argv)
{
	TDEAboutData about("primary_probe", "primary_probe", "1");
	TDECmdLineArgs::init(argc, argv, &about);
	TDEApplication::disableAutoDcopRegistration();
	TDEApplication app;
	KRandrSimpleAPI api;
	TQPtrList<SingleScreenData> list = api.readCurrentDisplayConfiguration();
	for (SingleScreenData *s = list.first(); s; s = list.next()) {
		if (s->is_extended)
			printf("%s primary=%d\n", s->screenUniqueName.local8Bit().data(), s->is_primary);
	}
	return 0;
}
