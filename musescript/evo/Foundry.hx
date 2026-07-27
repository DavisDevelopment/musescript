package musescript.evo;

/**
 * Fork / Consensus Foundry — rare generalization layer for Rivalry co-evo.
 *
 * Bags: both auto (`SymbolSelector` / POET-style proposal) AND explicit (`--tapes` / path).
 * Tick path: short fork-evo on champion material (variation under `perms` budget) → consensus
 * beam gated by real OOS / multi-bag tape improvement vs parent → optional inject.
 * Does not touch the NMA hot path — CorpusEvoRun calls `maybeTick` only every `--foundry-every` gens.
 *
 * OOS gate: callers pass `oosScore` (typically Fitness + BasketFitness over the held-out
 * `oosBasket`). Without a scorer, Foundry refuses inject — no blind structural-only inserts.
 */
class Foundry {
	public var every:Int;
	public var perms:Int;
	public var bagsMode:Null<String>;
	public var events:Array<FoundryEvent> = [];
	/** Minimum OOS delta (hybrid - parent) required to keep. Default 0 = any strict improvement. */
	public var oosEpsilon:Float;

	public function new(?every:Int = 0, ?perms:Int = 8, ?bagsMode:Null<String> = null, ?oosEpsilon:Float = 0.0) {
		this.every = every < 0 ? 0 : every;
		this.perms = perms < 1 ? 1 : perms;
		this.bagsMode = bagsMode;
		this.oosEpsilon = oosEpsilon;
	}

	public function enabled():Bool return every > 0;

	public function due(gen:Int):Bool return enabled() && (gen + 1) % every == 0;

	/**
	 * Resolve bag sources for a fork. `explicitTapes` = `--tapes` list; `autoPropose` builds a
	 * stub ranking over those plus any path listed in `bagsMode` when it is not `"auto"`.
	 */
	public function resolveBags(explicitTapes:Array<String>, autoPropose:Bool):Array<String> {
		var bags:Array<String> = [];
		if (bagsMode != null && bagsMode != "" && bagsMode != "auto")
			bags.push(bagsMode);
		if (explicitTapes != null)
			for (t in explicitTapes) if (t != null && t != "" && bags.indexOf(t) < 0) bags.push(t);
		if (autoPropose || bagsMode == "auto") {
			// Auto proposal: prefer a second symbol when a basket exists; else mark "auto".
			if (explicitTapes != null && explicitTapes.length > 1)
				bags.push("auto:" + explicitTapes[Std.int(Math.min(1, explicitTapes.length - 1))]);
			else if (bags.length == 0)
				bags.push("auto:propose");
		}
		return bags;
	}

	/**
	 * Short fork-evo: expand champions via crossover/mutate up to `perms` trials, then consensus
	 * pick gated by OOS improvement vs parent (and structural novelty vs pop / parent).
	 *
	 * `oosScore` — required for inject; CorpusEvoRun wires held-out / multi-bag tape eval.
	 * `onProgress` — optional heartbeat (GUI / console) so long Foundry work doesn't look frozen.
	 * Emits a timeline of events: fork → trials → consensus|reject (with reason).
	 */
	public function maybeTick(
		gen:Int,
		champions:Array<StrategyGenome>,
		variation:Variation,
		bags:Array<String>,
		?popKeys:Null<Map<String, Bool>>,
		?oosScore:Null<(StrategyGenome) -> Float>,
		?onProgress:Null<(phase:String, note:String) -> Void>
	):Null<FoundryEvent> {
		if (!due(gen)) return null;

		function emit(phase:String, note:String, ?hybrid:Null<StrategyGenome>, ?injected:Bool = false,
				?oosParent:Null<Float>, ?oosHybrid:Null<Float>, ?trial:Int = 0):FoundryEvent {
			var ev:FoundryEvent = {
				gen: gen,
				phase: phase,
				bags: bags != null ? bags.copy() : [],
				injected: injected,
				note: note,
				hybrid: hybrid,
				oosParent: oosParent,
				oosHybrid: oosHybrid,
				trial: trial
			};
			events.push(ev);
			if (onProgress != null) onProgress(phase, note);
			return ev;
		}

		if (champions == null || champions.length == 0 || variation == null) {
			return emit("fork", "fork recorded; no champions");
		}

		emit("fork", 'fork champions=${champions.length} bags=${bags != null ? bags.length : 0}');

		// --- fork-evo: beam of mutants/crossovers capped by perms ---
		var beam:Array<StrategyGenome> = [];
		beam.push(champions[0]);
		if (champions.length >= 2) beam.push(champions[1]);
		var trials = 0;
		while (trials < perms && beam.length < perms + 2) {
			trials++;
			var child:StrategyGenome;
			if (champions.length >= 2 && trials % 2 == 0)
				child = variation.crossover(champions[0], champions[1]);
			else
				child = variation.mutate(champions[trials % champions.length]);
			beam.push(child);
		}
		emit("trials", 'fork-evo beam=${beam.length} trials=$trials bags=${bags != null ? bags.length : 0}', null, false, null, null, trials);

		if (bags == null || bags.length == 0) {
			return emit("reject", "rejected: empty bag list (need auto or --tapes)");
		}
		if (oosScore == null) {
			return emit("reject", "rejected: no OOS scorer (Foundry requires held-out / multi-bag eval)");
		}

		// Multi-bag coverage: require auto bag OR ≥2 explicit bags OR a real OOS scorer with
		// at least one bag — scorer presence already proves a tape path; still insist on bags.
		var autoN = 0;
		for (b in bags) if (StringTools.startsWith(b, "auto:")) autoN++;
		// With a live OOS scorer, a single held-out tape is enough (IS/OOS split); multi-bag
		// preference remains for auto/explicit baskets without scorer (already rejected above).

		var parent = champions[0];
		var parentKey = Canonical.structuralKey(parent);
		var parentOos = oosScore(parent);
		emit("trials", 'OOS parent=${fmtScore(parentOos)} key=${shortKey(parentKey)}', null, false, parentOos, null, 0);

		var hybrid:Null<StrategyGenome> = null;
		var bestHybridOos = Fitness.NEG_INF;
		var bestNote = "rejected: no novel hybrid beating parent OOS";
		var scored = 0;

		for (i in 1...beam.length) {
			var cand = beam[i];
			var key = Canonical.structuralKey(cand);
			if (key == parentKey) continue;
			if (popKeys != null && popKeys.exists(key)) continue;

			scored++;
			if (onProgress != null)
				onProgress("trials", 'OOS trial $scored/$perms key=${shortKey(key)}');

			var candOos = oosScore(cand);
			if (candOos == Fitness.NEG_INF || Math.isNaN(candOos)) {
				if (hybrid == null) bestNote = 'rejected: OOS invalid key=${shortKey(key)}';
				continue;
			}
			// Keep if strictly improves parent by oosEpsilon (default 0 = any improvement).
			var improved = candOos > parentOos + oosEpsilon;
			// Also accept when parent is NEG_INF / invalid and candidate is finite.
			if (!improved && (parentOos == Fitness.NEG_INF || Math.isNaN(parentOos)) && candOos != Fitness.NEG_INF)
				improved = true;
			if (!improved) {
				if (hybrid == null)
					bestNote = 'rejected: OOS ${fmtScore(candOos)} <= parent ${fmtScore(parentOos)}+eps key=${shortKey(key)}';
				continue;
			}
			if (candOos > bestHybridOos) {
				bestHybridOos = candOos;
				hybrid = cand;
				bestNote = 'consensus keep OOS ${fmtScore(candOos)} > parent ${fmtScore(parentOos)}'
					+ ' key=${shortKey(key)} bags=${bags.join(",")}';
			}
		}

		if (hybrid != null) {
			return emit("consensus", bestNote, hybrid, true, parentOos, bestHybridOos, scored);
		}
		return emit("reject", bestNote + ' (scored=$scored)', null, false, parentOos, null, scored);
	}

	static function shortKey(key:String):String {
		var n = Std.int(Math.min(12, key.length));
		return key.substr(0, n) + (key.length > n ? "..." : "");
	}

	static function fmtScore(s:Float):String {
		if (s == Fitness.NEG_INF || Math.isNaN(s)) return "n/a";
		var r = Math.round(s * 10000) / 10000;
		return Std.string(r);
	}
}

@:structInit
class FoundryEvent {
	public var gen:Int;
	public var phase:String;
	public var bags:Array<String>;
	public var injected:Bool;
	public var note:String;
	public var hybrid:Null<StrategyGenome>;
	public var oosParent:Null<Float> = null;
	public var oosHybrid:Null<Float> = null;
	public var trial:Int = 0;
}
