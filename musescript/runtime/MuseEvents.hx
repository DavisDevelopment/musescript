package musescript.runtime;

/**
 * Global MuseScript event bus — host + script ecosystem nerve.
 *
 * Distinct from strategy-language `@on(bar)` / `@on(tick)` / `@on(stream)` hooks
 * (those live on MuseInterp / emitters and drive bar-synced strategy bodies).
 * This bus is the **out-of-band** surface for Lab / UI / broker / watchlist /
 * meta / world / lifecycle so brains can react without polling.
 *
 * Determinism quarantine:
 *   - `det` events may fire on truth / evolve / replay paths.
 *   - `host` / `ui` events are non-deterministic — blocked when mode is
 *     `"truth"` (listeners must not break DetRng / bit-identical equity).
 *   - `world` is thin-channel optional; treat as host unless a recorded
 *     WorldContext tape supplies a deterministic event log.
 *
 * JS (after `haxe build-runtime.hxml`):
 *   MuseEvents.on(type, handler) / off / once / emit / pumpHostEvent
 *   MuseRuntime.on(...)       // thin facade
 *   MuseRuntime.pumpHostEvent({ type, ... })
 *
 * Constitution: listening for P&L / bragging never becomes a ranking channel —
 * no event type carries leaderboard weight; Truth / Honest Ledger stay separate.
 *
 * See docs/MUSE_EVENTS.md.
 */
@:expose("MuseEvents")
class MuseEvents {

	/** Schema stamp for hosts / tests. */
	public static inline var SCHEMA = "musescript.events/1";

	/** Drop-oldest ring when a type's pending queue exceeds this (emit storm). */
	public static inline var DEFAULT_MAX_DEPTH = 256;

	/** `live` (default) allows all classes; `truth` rejects non-det emits. */
	static var mode:String = "live";

	static var maxDepth:Int = DEFAULT_MAX_DEPTH;

	/** type → [{ fn, once }] — Dynamic keeps JS function identity for off(). */
	static var listeners:Map<String, Array<ListenerEntry>> = new Map();

	/** Wildcard listeners (`*` / `family.*`). */
	static var wildcards:Array<ListenerEntry> = [];

	/** Recent emits for Lab inspectors (ring, not a source of truth). */
	static var history:Array<Dynamic> = [];
	static inline var HISTORY_CAP = 64;

	/** Dropped count under backpressure (observability). */
	static var dropped:Int = 0;

	/** Nested emit guard — re-entrant emit is allowed but counted. */
	static var emitDepth:Int = 0;

	static function main() {}

	// --- mode / policy --------------------------------------------------------

	/** `"live"` | `"truth"`. Truth mode refuses host/ui/world* non-det emits. */
	public static function setMode(m:String):String {
		mode = (m == "truth") ? "truth" : "live";
		return mode;
	}

	public static function getMode():String return mode;

	/** Cap per-listener backlog semantics via history ring; clamp ≥ 8. */
	public static function setMaxDepth(n:Int):Int {
		maxDepth = n < 8 ? 8 : n;
		return maxDepth;
	}

	public static function getMaxDepth():Int return maxDepth;

	/** Reset listeners + history + counters. Safe between Lab sessions. */
	public static function clear():Void {
		listeners = new Map();
		wildcards = [];
		history = [];
		dropped = 0;
		emitDepth = 0;
		mode = "live";
		maxDepth = DEFAULT_MAX_DEPTH;
	}

	public static function droppedCount():Int return dropped;

	// --- catalog --------------------------------------------------------------

	/**
	 * Full event catalog as plain JSON for hosts / Studio inspectors.
	 * Each entry: { type, family, class, deterministic, payload, notes }.
	 */
	public static function catalog():Dynamic {
		return {
			schemaVersion: SCHEMA,
			mode: mode,
			maxDepth: maxDepth,
			events: catalogEntries()
		};
	}

	/** Lookup one type; null if unknown (hosts may still pump unknown as `host`). */
	public static function describe(type:String):Null<Dynamic> {
		if (type == null || type.length == 0) return null;
		for (e in catalogEntries()) {
			if (Reflect.field(e, "type") == type) return e;
		}
		return null;
	}

	/** True when this type is allowed under current mode. */
	public static function isAllowed(type:String):Bool {
		if (mode != "truth") return true;
		return isDeterministic(type);
	}

	/** Catalog-backed: det family/events only. Unknown types → non-det. */
	public static function isDeterministic(type:String):Bool {
		var d = describe(type);
		if (d == null) return false;
		return Reflect.field(d, "deterministic") == true;
	}

	// --- subscribe ------------------------------------------------------------

	/**
	 * Subscribe. `type` may be exact (`order.fill`), family wildcard
	 * (`order.*`), or `*`. Returns an unsubscribe handle (also workable via off).
	 */
	public static function on(type:String, handler:Dynamic):Dynamic {
		return addListener(type, handler, false);
	}

	/** Subscribe for a single delivery then auto-off. */
	public static function once(type:String, handler:Dynamic):Dynamic {
		return addListener(type, handler, true);
	}

	/** Remove a previously registered handler (exact function identity). */
	public static function off(type:String, handler:Dynamic):Bool {
		if (handler == null) return false;
		if (isWildcard(type)) {
			var before = wildcards.length;
			wildcards = [for (e in wildcards) if (!(e.type == type && e.fn == handler)) e];
			return wildcards.length < before;
		}
		var list = listeners.get(type);
		if (list == null) return false;
		var next = [for (e in list) if (e.fn != handler) e];
		if (next.length == list.length) return false;
		if (next.length == 0) listeners.remove(type);
		else listeners.set(type, next);
		return true;
	}

	/** Count listeners for `type` (exact only; wildcards counted separately if type null). */
	public static function listenerCount(?type:String):Int {
		if (type == null) {
			var n = wildcards.length;
			for (k in listeners.keys()) n += listeners.get(k).length;
			return n;
		}
		var list = listeners.get(type);
		var n = list != null ? list.length : 0;
		for (w in wildcards) if (matches(w.type, type)) n++;
		return n;
	}

	// --- emit / pump ----------------------------------------------------------

	/**
	 * Emit a fully formed envelope `{ type, ... }`. Returns
	 * `{ ok, delivered, dropped?, reason? }`. Never throws across JS boundary.
	 */
	public static function emit(event:Dynamic):Dynamic {
		try {
			if (event == null) return fail("null event");
			var type:String = Reflect.field(event, "type");
			if (type == null || type.length == 0) return fail("missing type");
			if (!isAllowed(type))
				return fail('event "$type" blocked in truth mode (non-deterministic class)');

			var envelope = normalize(event, type);
			pushHistory(envelope);

			emitDepth++;
			var delivered = 0;
			try {
				delivered += dispatchExact(type, envelope);
				delivered += dispatchWildcards(type, envelope);
			} catch (ex:Dynamic) {
				emitDepth--;
				return {
					ok: false,
					delivered: delivered,
					error: Std.string(ex),
					type: type
				};
			}
			emitDepth--;
			return { ok: true, delivered: delivered, type: type, event: envelope };
		} catch (e:Dynamic) {
			return fail(Std.string(e));
		}
	}

	/**
	 * Host pump — preferred entry for Lab / broker / UI / world bridges.
	 * Accepts either `{ type, ...payload }` or `(type, payloadObj)`.
	 * Stamps `source:"host"`, `ts`, `class`, `deterministic`.
	 */
	public static function pumpHostEvent(a:Dynamic, ?b:Dynamic):Dynamic {
		try {
			var event:Dynamic;
			if (Std.isOfType(a, String)) {
				event = b != null ? shallowCopy(b) : {};
				Reflect.setField(event, "type", a);
			} else {
				event = a != null ? shallowCopy(a) : {};
			}
			if (!Reflect.hasField(event, "source"))
				Reflect.setField(event, "source", "host");
			return emit(event);
		} catch (e:Dynamic) {
			return fail(Std.string(e));
		}
	}

	/** Snapshot of recent envelopes (newest last). */
	public static function recent(?n:Int):Array<Dynamic> {
		var take = n != null && n > 0 ? n : history.length;
		if (take >= history.length) return history.copy();
		return history.slice(history.length - take);
	}

	// --- internals ------------------------------------------------------------

	static function addListener(type:String, handler:Dynamic, once:Bool):Dynamic {
		if (type == null || type.length == 0) return null;
		if (handler == null || !Reflect.isFunction(handler)) return null;
		var entry:ListenerEntry = { type: type, fn: handler, once: once };
		if (isWildcard(type)) {
			wildcards.push(entry);
		} else {
			var list = listeners.get(type);
			if (list == null) {
				list = [];
				listeners.set(type, list);
			}
			list.push(entry);
		}
		return function() return off(type, handler);
	}

	static function dispatchExact(type:String, envelope:Dynamic):Int {
		var list = listeners.get(type);
		if (list == null || list.length == 0) return 0;
		// Snapshot so once/off during emit is safe; drop fired `once` entries.
		var snap = list.copy();
		var delivered = 0;
		var removeOnce:Array<ListenerEntry> = [];
		for (e in snap) {
			try {
				Reflect.callMethod(null, e.fn, [envelope]);
			} catch (_:Dynamic) {
				// Listener errors are isolated — bus stays up.
			}
			delivered++;
			if (e.once) removeOnce.push(e);
		}
		if (removeOnce.length > 0) {
			var cur = listeners.get(type);
			if (cur != null) {
				var next = [for (e in cur) if (removeOnce.indexOf(e) < 0) e];
				if (next.length == 0) listeners.remove(type);
				else listeners.set(type, next);
			}
		}
		return delivered;
	}

	static function dispatchWildcards(type:String, envelope:Dynamic):Int {
		if (wildcards.length == 0) return 0;
		var snap = wildcards.copy();
		var delivered = 0;
		var removeOnce:Array<ListenerEntry> = [];
		for (e in snap) {
			if (!matches(e.type, type)) continue;
			try {
				Reflect.callMethod(null, e.fn, [envelope]);
			} catch (_:Dynamic) {}
			delivered++;
			if (e.once) removeOnce.push(e);
		}
		if (removeOnce.length > 0)
			wildcards = [for (e in wildcards) if (removeOnce.indexOf(e) < 0) e];
		return delivered;
	}

	static function pushHistory(envelope:Dynamic):Void {
		history.push(envelope);
		while (history.length > HISTORY_CAP) {
			history.shift();
			dropped++;
		}
		// Soft backpressure signal when storms exceed maxDepth in a short window:
		// if history itself is full and we're nested deep, bump dropped.
		if (emitDepth > 8 && history.length >= HISTORY_CAP) dropped++;
		if (history.length > maxDepth) {
			while (history.length > maxDepth) {
				history.shift();
				dropped++;
			}
		}
	}

	static function normalize(event:Dynamic, type:String):Dynamic {
		var out = shallowCopy(event);
		Reflect.setField(out, "type", type);
		var meta = describe(type);
		var cls:String = meta != null ? Reflect.field(meta, "class") : "host";
		var det:Bool = meta != null && Reflect.field(meta, "deterministic") == true;
		if (!Reflect.hasField(out, "class")) Reflect.setField(out, "class", cls);
		if (!Reflect.hasField(out, "deterministic")) Reflect.setField(out, "deterministic", det);
		if (!Reflect.hasField(out, "family")) {
			var fam:String = meta != null ? Reflect.field(meta, "family") : familyOf(type);
			Reflect.setField(out, "family", fam);
		}
		if (!Reflect.hasField(out, "ts"))
			Reflect.setField(out, "ts", nowMs());
		if (!Reflect.hasField(out, "schemaVersion"))
			Reflect.setField(out, "schemaVersion", SCHEMA);
		return out;
	}

	static function familyOf(type:String):String {
		var i = type.indexOf(".");
		if (i <= 0) return "unknown";
		return type.substr(0, i);
	}

	static function isWildcard(type:String):Bool {
		return type == "*" || StringTools.endsWith(type, ".*");
	}

	static function matches(pattern:String, type:String):Bool {
		if (pattern == "*") return true;
		if (pattern == type) return true;
		if (StringTools.endsWith(pattern, ".*")) {
			var prefix = pattern.substr(0, pattern.length - 1); // keep trailing '.'
			return StringTools.startsWith(type, prefix);
		}
		return false;
	}

	static function shallowCopy(o:Dynamic):Dynamic {
		var out:Dynamic = {};
		if (o == null) return out;
		for (k in Reflect.fields(o))
			Reflect.setField(out, k, Reflect.field(o, k));
		return out;
	}

	static function nowMs():Float {
		#if js
		return js.Syntax.code("Date.now()");
		#else
		return Date.now().getTime();
		#end
	}

	static function fail(reason:String):Dynamic {
		return { ok: false, delivered: 0, reason: reason, error: reason };
	}

	static function catalogEntries():Array<Dynamic> {
		return [
			// Market / bar
			entry("market.bar", "market", "det", true,
				"{ barIndex, open, high, low, close, volume?, time?, symbol? }",
				"Bar close (or aligned panel bar). Prefer strategy @on(bar) for trading logic; bus mirror for Lab overlays."),
			entry("market.tf_roll", "market", "det", true,
				"{ symbol?, fromTf, toTf, barIndex }",
				"Timeframe roll / session boundary when the host or tape marks one."),

			// Order / broker
			entry("order.submit", "order", "det", true,
				"{ orderId?, symbol?, side, qty?, price?, kind? }",
				"Sim or broker accepted a new order intent. Det when emitted from OrderSim/EventLog replay."),
			entry("order.fill", "order", "det", true,
				"{ orderId?, symbol?, side, qty, price, barIndex?, pnl? }",
				"Full fill. Harness fills[] are the authoritative sim log; this is the reactive twin."),
			entry("order.partial", "order", "det", true,
				"{ orderId?, symbol?, side, qty, filledQty, price }",
				"Partial fill (book / live broker)."),
			entry("order.reject", "order", "host", false,
				"{ orderId?, symbol?, reason }",
				"Broker/host reject — host-class (live). Recorded rejects in EventLog replay may be pumped as det under truth only if present on the tape."),
			entry("order.cancel", "order", "det", true,
				"{ orderId?, symbol?, reason? }",
				"Cancel acknowledged."),
			entry("order.status", "order", "host", false,
				"{ orderId?, symbol?, status, prevStatus?, raw? }",
				"Generic status tick (submitted/working/filled/...). Host default; quarantine in truth."),
			entry("order.suggested", "order", "host", false,
				"{ summary, runId?, n?, headline? }",
				"Swarm / Lab suggested orders for human approval — never auto-ranks by P&L."),

			// Watchlist / pings
			entry("watchlist.add", "watchlist", "host", false,
				"{ symbol, listId? }",
				"Symbol added to a watchlist."),
			entry("watchlist.remove", "watchlist", "host", false,
				"{ symbol, listId? }",
				"Symbol removed."),
			entry("watchlist.ping", "watchlist", "host", false,
				"{ symbol, kind?, message?, severity? }",
				"Alert / global ping fired for a symbol."),

			// UI / user
			entry("ui.click", "ui", "host", false,
				"{ target?, id?, x?, y?, meta? }",
				"Pointer click — non-det; Lab only."),
			entry("ui.selection", "ui", "host", false,
				"{ kind, id?, symbol?, range? }",
				"Chart / table / tree selection changed."),
			entry("ui.focus", "ui", "host", false,
				"{ panel?, id? }",
				"Panel / surface focus."),
			entry("ui.command", "ui", "host", false,
				"{ command, args? }",
				"Command-palette-ish host command."),

			// Metaprogramming
			entry("meta.reload", "meta", "host", false,
				"{ sourceId?, reason? }",
				"Script / widget reload."),
			entry("meta.macro_expand", "meta", "det", true,
				"{ macro, resultDigest? }",
				"Deterministic macro expand (same source → same expand)."),
			entry("meta.diagnostics", "meta", "det", true,
				"{ diagnostics:[{severity,msg,code?}…] }",
				"Compile / typecheck diagnostics from MuseRuntime.check."),
			entry("meta.strategy_swap", "meta", "host", false,
				"{ from?, to?, reason? }",
				"Active strategy / construct swapped in Lab."),

			// World / Jormungandr (optional thin channel — no strategy upload)
			entry("world.shock", "world", "host", false,
				"{ scenarioKey?, eventIds?, mag?, dir?, region? }",
				"Shock applied on the body. Brain listens; source never uploads."),
			entry("world.scrub", "world", "host", false,
				"{ t, runId?, scenarioKey? }",
				"Sim scrubber moved to time T."),
			entry("world.muse_light", "world", "host", false,
				"{ scenarioKey?, verdict?, reason? }",
				"Light Muse finished against a WorldContext."),
			entry("world.muse_evolve", "world", "host", false,
				"{ scenarioKey?, found?, reason? }",
				"Evolve-under-world finished (champion never ranked by P&L vanity)."),

			// Lifecycle
			entry("lifecycle.start", "lifecycle", "det", true,
				"{ runId?, backend?, bars? }",
				"MuseRuntime.run / runPanel / widget session start."),
			entry("lifecycle.stop", "lifecycle", "det", true,
				"{ runId?, ok?, backend? }",
				"Run completed successfully envelope attached."),
			entry("lifecycle.error", "lifecycle", "det", true,
				"{ runId?, error }",
				"Run failed — still det if the failure is a pure function of source+tape+seed."),
			entry("lifecycle.dispose", "lifecycle", "det", true,
				"{ runId?, reason? }",
				"Session / debug session disposed."),
		];
	}

	static function entry(
		type:String, family:String, cls:String, det:Bool,
		payload:String, notes:String
	):Dynamic {
		return {
			type: type,
			family: family,
			"class": cls,
			deterministic: det,
			payload: payload,
			notes: notes
		};
	}
}

private typedef ListenerEntry = {
	var type:String;
	var fn:Dynamic;
	var once:Bool;
};
