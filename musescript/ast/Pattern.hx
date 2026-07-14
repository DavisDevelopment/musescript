package musescript.ast;

enum Pattern {
	PatWild;
	PatLit(c:Const);
	PatBind(name:String);
	PatTyped(name:String, typeName:String);
	PatObj(fields:Array<{name:String, pat:Pattern}>);
	PatArr(items:Array<Pattern>, ?rest:Null<String>);
	PatOr(a:Pattern, b:Pattern);
	PatGuard(pat:Pattern, guard:Dynamic);
	PatAs(pat:Pattern, name:String);
	PatTag(tag:String, args:Array<Pattern>);
}
