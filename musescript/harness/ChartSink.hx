package musescript.harness;

class ChartSink {
	public var commands:Array<ChartCommand>;
	public function new() commands = [];
	public function plot(series:Float, label:String, ?color:String, ?barIndex:Int):Void {
		commands.push({ kind: "plot", series: series, label: label, color: color, barIndex: barIndex });
	}
	public function plotshape(label:String, ?barIndex:Int):Void {
		commands.push({ kind: "plotshape", label: label, barIndex: barIndex });
	}
	public function hline(v:Float, label:String):Void {
		commands.push({ kind: "hline", series: v, label: label });
	}
	public function bgcolor(color:String, ?barIndex:Int):Void {
		commands.push({ kind: "bgcolor", color: color, barIndex: barIndex });
	}
}
