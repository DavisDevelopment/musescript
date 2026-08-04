package musescript.io;

/**
 * Resolve / validate {@link NetGrant} for `muse.http` / `http_*`.
 */
class NetGrants {
	public static inline var DEFAULT_TIMEOUT_MS = 10000;
	public static inline var DEFAULT_MAX_BYTES = 8 * 1024 * 1024;
	public static inline var MODE_REPLAY = "replay";
	public static inline var MODE_RECORD = "record";
	public static inline var MODE_STRICT = "strict";

	public static function require(op:String, ?grants:Null<IoGrant>):NetGrant {
		return IoDenied.requireNet(op, grants);
	}

	public static function modeOf(net:NetGrant):String {
		var m = net.fixture_mode;
		if (m == null || m.length == 0) return MODE_REPLAY;
		var s = StringTools.trim(m).toLowerCase();
		if (s == MODE_REPLAY || s == MODE_RECORD || s == MODE_STRICT) return s;
		throw new IoDenied("http_request", 'unknown fixture_mode "$m" (use replay|record|strict)');
	}

	public static function timeoutMs(net:NetGrant, ?reqOverride:Null<Int>):Int {
		if (reqOverride != null && reqOverride > 0) return reqOverride;
		if (net.timeout_ms != null && net.timeout_ms > 0) return net.timeout_ms;
		return DEFAULT_TIMEOUT_MS;
	}

	public static function maxBytes(net:NetGrant):Int {
		if (net.max_bytes != null && net.max_bytes > 0) return net.max_bytes;
		return DEFAULT_MAX_BYTES;
	}

	/** Host allowlist: exact match or `*.example.com` suffix. */
	public static function assertHostAllowed(op:String, net:NetGrant, host:String):Void {
		var hosts = net.allow_hosts;
		if (hosts == null || hosts.length == 0)
			throw new IoDenied(op, "net grant missing allow_hosts");
		var h = host == null ? "" : host.toLowerCase();
		for (pat in hosts) {
			if (pat == null) continue;
			var p = StringTools.trim(pat).toLowerCase();
			if (p.length == 0) continue;
			if (p == h) return;
			if (StringTools.startsWith(p, "*.") && p.length > 2) {
				var suffix = p.substr(1); // `.example.com`
				if (StringTools.endsWith(h, suffix) || h == p.substr(2)) return;
			}
		}
		throw new IoDenied(op, 'host "$host" not in allow_hosts');
	}

	public static function assertSchemeAllowed(op:String, net:NetGrant, scheme:String):Void {
		var schemes = net.allow_schemes;
		if (schemes == null || schemes.length == 0) schemes = ["https"];
		var s = scheme == null ? "" : scheme.toLowerCase();
		for (ok in schemes) {
			if (ok != null && StringTools.trim(ok).toLowerCase() == s) return;
		}
		throw new IoDenied(op, 'scheme "$scheme" not in allow_schemes');
	}
}
