package musescript.ast;

enum Const {
	CInt(v:Int);
	CFloat(v:Float);
	CString(v:String);
	CBool(v:Bool);
	CNull;
}
