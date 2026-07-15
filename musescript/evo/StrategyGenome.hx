package musescript.evo;

typedef StrategyGenome = {
	var entryLong:BoolNode;
	var entryShort:BoolNode;
	var exitLong:BoolNode;
	var exitShort:BoolNode;
	var size:ScalarNode;
	var params:Array<EvoParam>;
	var name:String;
	var ?lineage:Array<String>;
	var ?seedOrigin:Null<Int>;
}
