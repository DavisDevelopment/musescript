package musescript.evo.graal;

/**
 * POD snapshot of Rivalry / Foundry / deme state for Swing paint.
 * Event-streamed at generation boundaries only — never per Murmuration tick.
 * Keeps murmuration types out of the paint path; fields are plain data (no secondary-module imports).
 */
@:structInit
class CompeteVizState {
	public var mode:String = "REAL"; // REAL | ARENA | FOUNDRY
	public var gen:Int = 0;
	public var demes:Array<{id:Int, n:Int, best:Float, mean:Float}> = [];
	public var wealthZ:Array<Float> = [];
	public var wealthRaw:Array<Float> = [];
	public var faults:Int = 0;
	public var cohort:Int = 0;
	public var responseEvents:Array<{kind:String, loserPop:Int, winnerPop:Int, round:Int}> = [];
	public var responseNudge:Int = 0;
	public var responseMate:Int = 0;
	public var foundryEvents:Array<{gen:Int, phase:String, bags:Array<String>, injected:Bool, note:String}> = [];
	public var arenaGen:Int = -1;
	public var rivalryWeight:Float = 0;
	public var migratePulse:Bool = false;
	/** Arena / Foundry heartbeat text (e.g. "round 0 200/400", "foundry trial 3/8") — cleared when idle. */
	public var arenaPulse:String = "";
	/** Per-market pick counts when `--compete-symbols` / SymbolSelector is active. */
	public var marketChoices:Array<Int> = [];
	/** Sequential-tape veteran pool size / cap / net inventory (gen-boundary snapshot). */
	public var veteranN:Int = 0;
	public var veteranCap:Int = 0;
	public var veteranNetInv:Float = 0;
	/** Cumulative POET env keep / reject counts (when `--poet` active). */
	public var poetKept:Int = 0;
	public var poetRejected:Int = 0;
	/** Immigrants swapped this gen after deme ring-migrate (0 when no migrate). */
	public var immigrantMarkers:Int = 0;

	public static function empty():CompeteVizState {
		return {
			mode: "REAL",
			gen: 0,
			demes: [],
			wealthZ: [],
			wealthRaw: [],
			faults: 0,
			cohort: 0,
			responseEvents: [],
			responseNudge: 0,
			responseMate: 0,
			foundryEvents: [],
			arenaGen: -1,
			rivalryWeight: 0,
			migratePulse: false,
			arenaPulse: "",
			marketChoices: [],
			veteranN: 0,
			veteranCap: 0,
			veteranNetInv: 0,
			poetKept: 0,
			poetRejected: 0,
			immigrantMarkers: 0
		};
	}

	public function summarizeResponses():Void {
		responseNudge = 0;
		responseMate = 0;
		for (e in responseEvents) {
			if (e.kind == "es-nudge") responseNudge++;
			else responseMate++;
		}
	}
}
