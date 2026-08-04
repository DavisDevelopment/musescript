package musescript.io;

/**
 * Build {@link IoGrant} from CLI / host dyn opts for the ingest tier.
 *
 * GeneRunner / PanelRunner `--ingest` use this so fitness paths stay grant-free
 * while Studio/CLI can pass `--fs-root`, `--fixture-dir`, `--allow-hosts`,
 * `--grants` JSON, and `--http` mode.
 */
class CliIoGrants {
	/**
	 * Merge sources into one grant (or null if nothing enabling).
	 *
	 * `opts` may carry:
	 *   - grants: IoGrant object (or already-parsed dyn)
	 *   - fsRoot / fs_root: absolute sandbox root (read+write `workspace`)
	 *   - fixtureDir / fixture_dir: NetGrant fixture directory
	 *   - allowHosts / allow_hosts: comma-separated or Array\<String\>
	 *   - http: replay|record|strict|off → fixture_mode (`off` clears net)
	 */
	public static function fromOpts(?opts:Dynamic):Null<IoGrant> {
		if (opts == null) return null;
		var g:Dynamic = {};
		if (Reflect.hasField(opts, "grants") && Reflect.field(opts, "grants") != null) {
			var src:Dynamic = Reflect.field(opts, "grants");
			for (k in Reflect.fields(src))
				Reflect.setField(g, k, Reflect.field(src, k));
		}

		var fsRoot = firstStr(opts, ["fsRoot", "fs_root", "fs-root"]);
		if (fsRoot != null && fsRoot.length > 0) {
			var abs = StringTools.replace(fsRoot, "\\", "/");
			Reflect.setField(g, "fs", {
				roots: [{ name: "workspace", abs: abs, read: true, write: true }],
				mode: "sync"
			});
		}

		var fixtureDir = firstStr(opts, ["fixtureDir", "fixture_dir", "fixture-dir"]);
		var hosts = hostsOf(opts);
		var httpMode = firstStr(opts, ["http"]);
		if (httpMode != null) httpMode = StringTools.trim(httpMode).toLowerCase();

		var existingNet:Dynamic = Reflect.field(g, "net");
		if (httpMode == "off") {
			Reflect.setField(g, "net", null);
		} else if ((fixtureDir != null && fixtureDir.length > 0)
			|| (hosts != null && hosts.length > 0)
			|| (httpMode != null && httpMode.length > 0)) {
			var dir = fixtureDir != null && fixtureDir.length > 0
				? StringTools.replace(fixtureDir, "\\", "/")
				: (existingNet != null && Reflect.field(existingNet, "fixture_dir") != null
					? Std.string(Reflect.field(existingNet, "fixture_dir")) : "");
			var allow:Array<String> = hosts != null && hosts.length > 0
				? hosts
				: (existingNet != null && Reflect.field(existingNet, "allow_hosts") != null
					? cast Reflect.field(existingNet, "allow_hosts") : ["api.example.com"]);
			var mode = httpMode != null && httpMode.length > 0 ? httpMode : "replay";
			if (mode != "replay" && mode != "record" && mode != "strict") mode = "replay";
			Reflect.setField(g, "net", {
				allow_hosts: allow,
				allow_schemes: ["https", "http"],
				timeout_ms: 10000,
				max_bytes: 8 * 1024 * 1024,
				max_requests_per_run: 32,
				fixture_mode: mode,
				fixture_dir: dir
			});
		}

		var hasFs = Reflect.field(g, "fs") != null;
		var hasNet = Reflect.field(g, "net") != null;
		var hasDb = Reflect.field(g, "db") != null;
		if (!hasFs && !hasNet && !hasDb) return null;
		return cast g;
	}

	/** Load grants JSON text into an IoGrant-shaped dyn. */
	public static function parseJson(text:String):IoGrant {
		var root:Dynamic = haxe.Json.parse(text);
		if (root == null || !Reflect.isObject(root))
			throw "CliIoGrants: grants JSON must be an object";
		return cast root;
	}

	static function firstStr(opts:Dynamic, keys:Array<String>):Null<String> {
		for (k in keys) {
			if (opts == null || !Reflect.hasField(opts, k)) continue;
			var v:Dynamic = Reflect.field(opts, k);
			if (v == null) continue;
			var s = StringTools.trim(Std.string(v));
			if (s.length > 0) return s;
		}
		return null;
	}

	static function hostsOf(opts:Dynamic):Null<Array<String>> {
		var raw:Dynamic = null;
		if (Reflect.hasField(opts, "allowHosts")) raw = Reflect.field(opts, "allowHosts");
		else if (Reflect.hasField(opts, "allow_hosts")) raw = Reflect.field(opts, "allow_hosts");
		else if (Reflect.hasField(opts, "allow-hosts")) raw = Reflect.field(opts, "allow-hosts");
		if (raw == null) return null;
		if (Std.isOfType(raw, Array)) {
			var out:Array<String> = [];
			for (h in (raw : Array<Dynamic>)) {
				if (h == null) continue;
				var s = StringTools.trim(Std.string(h));
				if (s.length > 0) out.push(s);
			}
			return out.length > 0 ? out : null;
		}
		var s = StringTools.trim(Std.string(raw));
		if (s.length == 0) return null;
		var parts = s.split(",");
		var hosts:Array<String> = [];
		for (p in parts) {
			var t = StringTools.trim(p);
			if (t.length > 0) hosts.push(t);
		}
		return hosts.length > 0 ? hosts : null;
	}
}
