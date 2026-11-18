// What dcopidl2cpp generates for a class whose k_dcop section is empty.
#include "displayconfig.h"
bool KDisplayConfig::process(const TQCString &fun, const TQByteArray &data, TQCString &replyType, TQByteArray &replyData)
{
	return DCOPObject::process(fun, data, replyType, replyData);
}
QCStringList KDisplayConfig::interfaces()
{
	QCStringList ifaces = DCOPObject::interfaces();
	ifaces += "KDisplayConfig";
	return ifaces;
}
QCStringList KDisplayConfig::functions()
{
	return DCOPObject::functions();
}
