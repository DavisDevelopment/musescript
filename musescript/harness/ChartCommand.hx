package musescript.harness;

typedef ChartCommand = {
	var kind:String;
	var ?series:Float;
	var ?label:String;
	var ?color:String;
	var ?barIndex:Int;
}
