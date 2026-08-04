package musescript.io;

/**
 * Host-supplied network / HTTP capability (M2).
 *
 * Without a net grant → {@link IoDenied}. Plugins never receive NetGrant
 * (`PluginCapabilities` denies `io_net` at audit).
 *
 * `fixture_mode`:
 *   - `replay` (default for backtest) — fixture hit or hard error; never live
 *   - `record` — live fetch + write fixture (CLI / ingest flag only)
 *   - `strict` — live only; refused when harness `isBacktest` / `isFitness`
 */
typedef NetGrant = {
	var allow_hosts:Array<String>;
	@:optional var allow_schemes:Array<String>;
	@:optional var timeout_ms:Int;
	@:optional var max_bytes:Int;
	@:optional var max_requests_per_run:Int;
	/** `replay` | `record` | `strict` — default `replay`. */
	@:optional var fixture_mode:String;
	/** Absolute native directory for HTTP fixtures. */
	@:optional var fixture_dir:String;
};
