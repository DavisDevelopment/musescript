package musescript.checker;

import musescript.types.SourcePos;

enum abstract Severity(String) to String {
	var Error = "error";
	var Warning = "warning";
	var Info = "info";
}

typedef Diagnostic = {
	var severity:Severity;
	var msg:String;
	var ?pos:SourcePos;
	var ?code:String;
}
