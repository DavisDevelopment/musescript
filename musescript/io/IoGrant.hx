package musescript.io;

/**
 * Host-supplied capability tokens for gated I/O (M1+).
 *
 * Default for strategies / fitness / widgets: **null** — any `fs_*` / `http_*` /
 * `db_*` call must throw {@link IoDenied}. Studio / CLI ingest passes a grant
 * with sandboxed roots; WASM fitness hosts leave grants null.
 */
typedef IoGrant = {
	@:optional var fs:{
		var roots:Array<{
			var name:String;
			var abs:String;
			var read:Bool;
			@:optional var write:Bool;
		}>;
		@:optional var mode:String;
	};
	/** Net / HTTP grant — see {@link NetGrant}. */
	@:optional var net:NetGrant;
	/** DB grant stub (shape locked in M3). */
	@:optional var db:Dynamic;
};
