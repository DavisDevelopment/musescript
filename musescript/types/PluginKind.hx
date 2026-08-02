package musescript.types;

/**
 * Declared kind for widget / plugin / extension programs.
 *
 * Full strategies (Studio backtests, evo) do not use a plugin kind — they keep
 * the unrestricted order + portfolio surface. Plugin kinds start denied and
 * only opt into chart / panel / (later) scanner capabilities. Order verbs,
 * portfolio mutation, filesystem/network, and raw Reflect stay out of every
 * plugin kind.
 *
 * See `PluginCapabilities` for the capability table and docs/PLUGIN_KINDS.md.
 */
enum abstract PluginKind(String) from String to String {
	/** Default: read-only bars / series / params / stats / ML / graph query. */
	var Compute = "compute";
	/** Compute + plot/chart drawing commands. */
	var Chart = "chart";
	/** Compute + chart plots + panel display helpers (`log`). */
	var Panel = "panel";
	/**
	 * Reserved: universe / scan helpers (`scan_top` / `scan_bottom`). Not
	 * granted yet — callers get an honest deny until a real scanner consumer
	 * lands (ROADMAP plugin section).
	 */
	var Scanner = "scanner";

	public static function parse(raw:Null<String>):PluginKind {
		if (raw == null || StringTools.trim(raw) == "") return Compute;
		return switch (StringTools.trim(raw).toLowerCase()) {
			case "compute" | "default" | "widget-compute": Compute;
			case "chart" | "overlay" | "on-chart": Chart;
			case "panel" | "flex" | "display": Panel;
			case "scanner" | "scan": Scanner;
			default: throw 'unknown plugin kind: $raw (expected compute|chart|panel|scanner)';
		};
	}

	public static function all():Array<PluginKind> {
		return [Compute, Chart, Panel, Scanner];
	}

	public function label():String {
		return this;
	}
}
