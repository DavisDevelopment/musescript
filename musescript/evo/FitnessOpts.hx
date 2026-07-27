package musescript.evo;

/** Plain Fitness knobs shipped to NmaNodeEvalPool workers at spawn (JSON-safe). */
typedef FitnessOpts = {
	var popMemo:Bool;
	var costBps:Float;
	var initialCash:Float;
	var equityFloor:Float;
	var attrBandit:Bool;
	var creditCuts:Bool;
}
