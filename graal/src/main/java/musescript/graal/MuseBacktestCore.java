package musescript.graal;

import org.graalvm.polyglot.Value;
import org.graalvm.polyglot.proxy.ProxyExecutable;
import org.graalvm.polyglot.proxy.ProxyObject;

import java.io.IOException;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Shared MuseScript on_bar WASM backtest harness — the dual memory ABI (streaming/preloaded),
 * OrderSim, CSV/strings loading, extracted out of MuseGraalStress.java so both the one-shot
 * stress test and KestrGraalServer's persistent-process RPC handler run the exact same,
 * already-proven-delta-0 logic. No behavior change from the pre-extraction version.
 */
public final class MuseBacktestCore {
    private MuseBacktestCore() {}

    public static final int STATE_BYTES = 8192;

    public static final class OrderSim {
        double position = 0, cash = 100000, entryPrice = 0;
        int trades = 0, wins = 0;
        final List<Double> equity = new ArrayList<>();

        void longOrder(double price, Double qty) {
            double q = qty != null ? qty : (position == 0 ? Math.floor(cash / price) : 0);
            if (q <= 0) return;
            if (position < 0) flat(price);
            cash -= q * price;
            position += q;
            entryPrice = price;
            trades++;
        }

        // Line-for-line port of musescript/harness/OrderSim.hx's short() -- this was a documented
        // no-op stub in the "env" import ("short not used by the MA-cross reference strategy")
        // that quietly did nothing on every short() call. Found via a real correctness sweep: 21
        // of 29 randomly-generated genomes scored via KestrGraal diverged from the trusted
        // JS-interp path, and every mismatching genome called short() somewhere in its tree.
        void shortOrder(double price, Double qty) {
            double q = qty != null ? qty : (position == 0 ? Math.floor(cash / price) : 0);
            if (q <= 0) return;
            if (position > 0) flat(price);
            cash += q * price;
            position -= q;
            entryPrice = price;
            trades++;
        }

        void flat(double price) {
            if (position == 0) return;
            double pnl = position * (price - entryPrice);
            if (pnl > 0) wins++;
            cash += position * price;
            position = 0;
            trades++;
        }

        void mark(double price) {
            equity.add(cash + position * price);
        }
    }

    public static double sharpe(double[] returns) {
        if (returns.length < 2) return 0;
        double mean = 0;
        for (double r : returns) mean += r;
        mean /= returns.length;
        double var = 0;
        for (double r : returns) {
            double d = r - mean;
            var += d * d;
        }
        var /= returns.length - 1;
        double std = Math.sqrt(var);
        return std == 0 ? 0 : mean / std * Math.sqrt(252);
    }

    public static double[] returnsFromEquity(List<Double> equity) {
        int n = Math.max(0, equity.size() - 1);
        double[] out = new double[n];
        for (int i = 1; i < equity.size(); i++) {
            double prev = equity.get(i - 1);
            out[i - 1] = prev != 0 ? (equity.get(i) - prev) / prev : 0;
        }
        return out;
    }

    public record Bar(double open, double high, double low, double close, double volume, double time, double index) {}
    public record BacktestResult(int trades, double finalEquity, double sharpe, double maxDrawdown, double winRate) {}

    /** Line-for-line port of musescript/harness/Metrics.hx's maxDrawdown -- same running-peak
     *  drawdown, kept a direct port (not reimplemented independently) so this stays provably
     *  identical to the reference JS/interp backends, the same discipline used for sharpe() above. */
    public static double maxDrawdown(List<Double> equity) {
        double peak = Double.NEGATIVE_INFINITY;
        double maxDd = 0;
        for (double e : equity) {
            if (e > peak) peak = e;
            double dd = peak > 0 ? (peak - e) / peak : 0;
            if (dd > maxDd) maxDd = dd;
        }
        return maxDd;
    }

    public static double winRate(int wins, int trades) {
        return trades == 0 ? 0 : (double) wins / trades;
    }

    public static final class HostState {
        public final Map<String, Double> params = new HashMap<>();
        final OrderSim sim = new OrderSim();
        double currentClose = Double.NaN;
    }

    public static ProxyObject makeEnv(HostState st, List<String> strings) {
        Map<String, Object> env = new HashMap<>();
        env.put("get_param", (ProxyExecutable) args -> {
            String name = strings.get(args[0].asInt());
            return st.params.getOrDefault(name, 0.0);
        });
        env.put("long", (ProxyExecutable) args -> {
            double qty = args[0].asDouble();
            st.sim.longOrder(st.currentClose, Double.isNaN(qty) ? null : qty);
            return null;
        });
        env.put("short", (ProxyExecutable) args -> {
            double qty = args[0].asDouble();
            st.sim.shortOrder(st.currentClose, Double.isNaN(qty) ? null : qty);
            return null;
        });
        env.put("flat", (ProxyExecutable) args -> {
            st.sim.flat(st.currentClose);
            return null;
        });
        // StrategyWasmEmitter.hx unconditionally imports "exp" on EVERY emitted module (its
        // softmax/sigmoid helper functions call host exp, "always provide the import" per its own
        // comment) -- without this, WASM instantiation itself fails for every artifact, not just
        // ones that actually use softmax/sigmoid at runtime. Found via a real batch run: every
        // genome's Backtest RPC failed with "Import module object env does not contain exp" until
        // this was added. get_position/get_entry_price/get_bars_in_trade/get_cash/get_equity/
        // get_unrealized_pnl (StrategyWasmEmitter.needPositionImports) are a separate, newer
        // OnPosition-hook feature not yet wired here -- a genome using an OnPosition hook will
        // still fail to instantiate against KestrGraal until those are added too.
        env.put("exp", (ProxyExecutable) args -> Math.exp(args[0].asDouble()));
        return ProxyObject.fromMap(Map.of("env", ProxyObject.fromMap(env)));
    }

    /** Streaming mode: reset + push_bar per bar. */
    public static BacktestResult runStreaming(Value module, List<String> strings, List<Bar> bars, Map<String, Double> params) {
        HostState st = new HostState();
        st.params.putAll(params);
        Value instance = module.newInstance(makeEnv(st, strings));
        Value exports = instance.getMember("exports");
        exports.getMember("reset").execute(Math.max(1, bars.size()));
        Value pushBar = exports.getMember("push_bar");
        for (Bar bar : bars) {
            st.currentClose = bar.close();
            pushBar.execute(
                bar.open(), bar.high(), bar.low(), bar.close(),
                bar.volume(), bar.time(), bar.index()
            );
            st.sim.mark(bar.close());
        }
        return finish(st);
    }

    /** Preloaded mode: pack contiguous OHLCV into exported memory, then on_bar(index). */
    public static BacktestResult runPreloaded(Value module, List<String> strings, List<Bar> bars, Map<String, Double> params) {
        HostState st = new HostState();
        st.params.putAll(params);
        Value instance = module.newInstance(makeEnv(st, strings));
        Value exports = instance.getMember("exports");
        Value memory = exports.getMember("memory");
        int n = Math.max(1, bars.size());
        int bytesNeeded = STATE_BYTES + n * 7 * 8;
        exports.getMember("ensure_capacity").execute(bytesNeeded);

        memory = exports.getMember("memory");
        int baseOpen = STATE_BYTES;
        int baseHigh = baseOpen + n * 8;
        int baseLow = baseHigh + n * 8;
        int baseClose = baseLow + n * 8;
        int baseVol = baseClose + n * 8;
        int baseTime = baseVol + n * 8;
        int baseIdx = baseTime + n * 8;

        for (int i = 0; i < bars.size(); i++) {
            Bar b = bars.get(i);
            memory.writeBufferDouble(ByteOrder.LITTLE_ENDIAN, baseOpen + i * 8L, b.open());
            memory.writeBufferDouble(ByteOrder.LITTLE_ENDIAN, baseHigh + i * 8L, b.high());
            memory.writeBufferDouble(ByteOrder.LITTLE_ENDIAN, baseLow + i * 8L, b.low());
            memory.writeBufferDouble(ByteOrder.LITTLE_ENDIAN, baseClose + i * 8L, b.close());
            memory.writeBufferDouble(ByteOrder.LITTLE_ENDIAN, baseVol + i * 8L, b.volume());
            memory.writeBufferDouble(ByteOrder.LITTLE_ENDIAN, baseTime + i * 8L, b.time());
            memory.writeBufferDouble(ByteOrder.LITTLE_ENDIAN, baseIdx + i * 8L, b.index());
        }
        exports.getMember("configure_tape").execute(
            baseOpen, baseHigh, baseLow, baseClose, baseVol, baseTime, baseIdx, n
        );
        Value onBar = exports.getMember("on_bar");
        for (int i = 0; i < bars.size(); i++) {
            st.currentClose = bars.get(i).close();
            onBar.execute(i);
            st.sim.mark(bars.get(i).close());
        }
        return finish(st);
    }

    static BacktestResult finish(HostState st) {
        List<Double> eq = st.sim.equity;
        double fin = eq.isEmpty() ? st.sim.cash : eq.get(eq.size() - 1);
        return new BacktestResult(
            st.sim.trades, fin, sharpe(returnsFromEquity(eq)),
            maxDrawdown(eq), winRate(st.sim.wins, st.sim.trades)
        );
    }

    public static List<Bar> loadCsv(Path path) throws IOException {
        List<String> lines = Files.readAllLines(path);
        String[] header = lines.get(0).toLowerCase().split(",");
        int o = -1, h = -1, l = -1, c = -1, v = -1, t = -1;
        for (int i = 0; i < header.length; i++) {
            switch (header[i].trim()) {
                case "open" -> o = i;
                case "high" -> h = i;
                case "low" -> l = i;
                case "close" -> c = i;
                case "volume" -> v = i;
                case "date", "time", "timestamp" -> t = i;
            }
        }
        List<Bar> bars = new ArrayList<>();
        int idx = 0;
        for (int i = 1; i < lines.size(); i++) {
            String line = lines.get(i).trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            String[] p = line.split(",");
            if (p.length < 5) continue;
            double open = Double.parseDouble(p[o]), high = Double.parseDouble(p[h]);
            double low = Double.parseDouble(p[l]), close = Double.parseDouble(p[c]);
            double vol = v >= 0 && v < p.length ? Double.parseDouble(p[v]) : 0;
            double time = idx;
            if (!Double.isFinite(open) || !Double.isFinite(high)
                || !Double.isFinite(low) || !Double.isFinite(close)) continue;
            bars.add(new Bar(open, high, low, close, vol, time, idx));
            idx++;
        }
        return bars;
    }

    public static List<String> loadStrings(Path path) throws IOException {
        String json = Files.readString(path).trim();
        List<String> out = new ArrayList<>();
        Matcher m = Pattern.compile("\"([^\"]*)\"").matcher(json);
        while (m.find()) out.add(m.group(1));
        return out;
    }

    public static double jsonNumber(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*(-?[0-9.eE+]+)").matcher(json);
        if (!m.find()) throw new IllegalStateException("missing key " + key);
        return Double.parseDouble(m.group(1));
    }

    public static boolean parity(BacktestResult r, int trades, double equity, double sharpe) {
        return r.trades() == trades
            && Math.abs(r.finalEquity() - equity) <= 1e-6
            && Math.abs(r.sharpe() - sharpe) <= 1e-6;
    }
}
