package musescript.graal;

import org.graalvm.polyglot.Context;
import org.graalvm.polyglot.Engine;
import org.graalvm.polyglot.Source;
import org.graalvm.polyglot.Value;
import org.graalvm.polyglot.io.ByteSequence;
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
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * MuseScript stress test on GraalVM's WebAssembly runtime (GraalWasm).
 *
 * Exercises the dual memory ABI:
 *   streaming  — reset(capacity) + push_bar(...)
 *   preloaded  — pack OHLCV into exported memory + configure_tape + on_bar(index)
 *
 * Host ABI is side-effects only (get_param / long / short / flat).
 */
public final class MuseGraalStress {

    static final int STATE_BYTES = 8192;

    static final class OrderSim {
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

    static double sharpe(double[] returns) {
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

    static double[] returnsFromEquity(List<Double> equity) {
        int n = Math.max(0, equity.size() - 1);
        double[] out = new double[n];
        for (int i = 1; i < equity.size(); i++) {
            double prev = equity.get(i - 1);
            out[i - 1] = prev != 0 ? (equity.get(i) - prev) / prev : 0;
        }
        return out;
    }

    record Bar(double open, double high, double low, double close, double volume, double time, double index) {}
    record BacktestResult(int trades, double finalEquity, double sharpe) {}

    static final class HostState {
        final Map<String, Double> params = new HashMap<>();
        final OrderSim sim = new OrderSim();
        double currentClose = Double.NaN;
    }

    static ProxyObject makeEnv(HostState st, List<String> strings) {
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
            // short not used by M0, but keep ABI parity if emitter imports it
            return null;
        });
        env.put("flat", (ProxyExecutable) args -> {
            st.sim.flat(st.currentClose);
            return null;
        });
        return ProxyObject.fromMap(Map.of("env", ProxyObject.fromMap(env)));
    }

    /** Streaming mode: reset + push_bar per bar. */
    static BacktestResult runStreaming(Value module, List<String> strings, List<Bar> bars) {
        HostState st = new HostState();
        st.params.put("fast", 10.0);
        st.params.put("slow", 30.0);
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
    static BacktestResult runPreloaded(Value module, List<String> strings, List<Bar> bars) {
        HostState st = new HostState();
        st.params.put("fast", 10.0);
        st.params.put("slow", 30.0);
        Value instance = module.newInstance(makeEnv(st, strings));
        Value exports = instance.getMember("exports");
        Value memory = exports.getMember("memory");
        int n = Math.max(1, bars.size());
        int bytesNeeded = STATE_BYTES + n * 7 * 8;
        exports.getMember("ensure_capacity").execute(bytesNeeded);

        // Re-acquire memory after possible growth.
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
        return new BacktestResult(st.sim.trades, fin, sharpe(returnsFromEquity(eq)));
    }

    static List<Bar> loadCsv(Path path) throws IOException {
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
            double time = t >= 0 && t < p.length ? idx : idx;
            if (!Double.isFinite(open) || !Double.isFinite(high)
                || !Double.isFinite(low) || !Double.isFinite(close)) continue;
            bars.add(new Bar(open, high, low, close, vol, time, idx));
            idx++;
        }
        return bars;
    }

    static List<String> loadStrings(Path path) throws IOException {
        String json = Files.readString(path).trim();
        List<String> out = new ArrayList<>();
        Matcher m = Pattern.compile("\"([^\"]*)\"").matcher(json);
        while (m.find()) out.add(m.group(1));
        return out;
    }

    static double jsonNumber(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*(-?[0-9.eE+]+)").matcher(json);
        if (!m.find()) throw new IllegalStateException("missing key " + key);
        return Double.parseDouble(m.group(1));
    }

    static double polySumJava(int n) {
        double acc = 0.0;
        int i = 0;
        while (i < n) {
            double x = i * 0.0000001;
            acc = acc + (((x * x) * x) - ((2.0 * x) * x) + x);
            i = i + 1;
        }
        return acc;
    }

    static boolean parity(BacktestResult r, int trades, double equity, double sharpe) {
        return r.trades() == trades
            && Math.abs(r.finalEquity() - equity) <= 1e-6
            && Math.abs(r.sharpe() - sharpe) <= 1e-6;
    }

    public static void main(String[] argv) throws Exception {
        Path root = Path.of(argv.length > 0 ? argv[0] : "..").toAbsolutePath().normalize();
        Path graalDir = root.resolve("build/graal");
        System.out.println("=== MuseScript GraalWasm stress (memory ABI) ===");
        System.out.println("root: " + root);
        System.out.println("jvm:  " + System.getProperty("java.vm.name") + " " + System.getProperty("java.vm.version"));

        List<Bar> bars = loadCsv(root.resolve("data/real/spy.csv"));
        List<String> strings = loadStrings(graalDir.resolve("on_bar.strings.json"));
        String expectedJson = Files.readString(graalDir.resolve("expected.json"));
        int expTrades = (int) jsonNumber(expectedJson, "trades");
        double expEquity = jsonNumber(expectedJson, "finalEquity");
        double expSharpe = jsonNumber(expectedJson, "sharpe");
        System.out.println("tape: data/real/spy.csv bars=" + bars.size() + "  strings=" + strings);

        boolean allOk = true;
        byte[] stratBytes = Files.readAllBytes(graalDir.resolve("on_bar.wasm"));

        try (Engine engine = Engine.newBuilder("wasm").build();
             Context ctx = Context.newBuilder("wasm").engine(engine).build()) {

            System.out.println("\n--- leg 1: polySum math kernel ---");
            Value mathModule = ctx.eval(Source.newBuilder("wasm",
                ByteSequence.create(Files.readAllBytes(graalDir.resolve("polySum.wasm"))),
                "polySum").build());
            Value polySum = mathModule.newInstance().getMember("exports").getMember("polySum");
            int n = 2_000_000, rounds = 5;
            for (int i = 0; i < 30; i++) polySum.execute(50_000);
            double wasmVal = polySum.execute(n).asDouble();
            double javaVal = polySumJava(n);
            double mathDelta = Math.abs(wasmVal - javaVal);
            System.out.printf("value wasm=%.9f java=%.9f delta=%.3e%n", wasmVal, javaVal, mathDelta);
            long t0 = System.nanoTime();
            for (int i = 0; i < rounds; i++) polySum.execute(n);
            double wasmMs = (System.nanoTime() - t0) / 1e6 / rounds;
            t0 = System.nanoTime();
            for (int i = 0; i < rounds; i++) polySumJava(n);
            double javaMs = (System.nanoTime() - t0) / 1e6 / rounds;
            System.out.printf("graal-wasm  %8.2f ms @ n=%d%n", wasmMs, n);
            System.out.printf("pure-java   %8.2f ms @ n=%d%n", javaMs, n);
            boolean mathOk = mathDelta <= 1e-6;
            System.out.println("leg 1: " + (mathOk ? "PASS" : "FAIL"));
            allOk &= mathOk;

            Value stratModule = ctx.eval(Source.newBuilder("wasm",
                ByteSequence.create(stratBytes), "on_bar").build());

            System.out.println("\n--- leg 2a: streaming push_bar parity ---");
            BacktestResult rs = runStreaming(stratModule, strings, bars);
            System.out.printf("streaming trades=%d equity=%s sharpe=%s%n", rs.trades(), rs.finalEquity(), rs.sharpe());
            boolean streamOk = parity(rs, expTrades, expEquity, expSharpe);
            System.out.println("leg 2a: " + (streamOk ? "PASS" : "FAIL"));
            allOk &= streamOk;

            System.out.println("\n--- leg 2b: preloaded configure_tape/on_bar parity ---");
            BacktestResult rp = runPreloaded(stratModule, strings, bars);
            System.out.printf("preloaded trades=%d equity=%s sharpe=%s%n", rp.trades(), rp.finalEquity(), rp.sharpe());
            boolean preloadOk = parity(rp, expTrades, expEquity, expSharpe)
                && rs.trades() == rp.trades()
                && Math.abs(rs.finalEquity() - rp.finalEquity()) <= 1e-6;
            System.out.println("leg 2b: " + (preloadOk ? "PASS (matches streaming + interp)" : "FAIL"));
            allOk &= preloadOk;

            System.out.println("\n--- leg 3: sequential throughput (streaming) ---");
            int warm = 3, timedRuns = 20;
            for (int i = 0; i < warm; i++) runStreaming(stratModule, strings, bars);
            t0 = System.nanoTime();
            for (int i = 0; i < timedRuns; i++) {
                BacktestResult rr = runStreaming(stratModule, strings, bars);
                if (rr.trades() != expTrades) throw new IllegalStateException("nondeterministic!");
            }
            double perRun = (System.nanoTime() - t0) / 1e6 / timedRuns;
            System.out.printf("%d backtests x %d bars: %.2f ms/backtest (%.0f bars/sec)%n",
                timedRuns, bars.size(), perRun, bars.size() / (perRun / 1000.0));
            System.out.println("leg 3: PASS");

            System.out.println("\n--- leg 4: sequential throughput (preloaded) ---");
            for (int i = 0; i < warm; i++) runPreloaded(stratModule, strings, bars);
            t0 = System.nanoTime();
            for (int i = 0; i < timedRuns; i++) runPreloaded(stratModule, strings, bars);
            double perRunP = (System.nanoTime() - t0) / 1e6 / timedRuns;
            System.out.printf("%d backtests x %d bars: %.2f ms/backtest (%.0f bars/sec)%n",
                timedRuns, bars.size(), perRunP, bars.size() / (perRunP / 1000.0));
            System.out.println("leg 4: PASS");

            System.out.println("\n--- leg 5: module instantiation cost ---");
            int instRuns = 500;
            ProxyObject dummyEnv = makeEnv(new HostState(), strings);
            t0 = System.nanoTime();
            for (int i = 0; i < instRuns; i++) stratModule.newInstance(dummyEnv);
            double perInst = (System.nanoTime() - t0) / 1e3 / instRuns;
            System.out.printf("%d instantiations: %.1f us each%n", instRuns, perInst);
            System.out.println("leg 5: PASS");
        }

        System.out.println("\n--- leg 6: parallel backtests (4 threads, shared Engine) ---");
        int threads = 4, perThread = 5;
        try (Engine shared = Engine.newBuilder("wasm").build()) {
            ExecutorService pool = Executors.newFixedThreadPool(threads);
            List<Future<BacktestResult>> futures = new ArrayList<>();
            long t0 = System.nanoTime();
            for (int t = 0; t < threads; t++) {
                futures.add(pool.submit((Callable<BacktestResult>) () -> {
                    try (Context tctx = Context.newBuilder("wasm").engine(shared).build()) {
                        Value module = tctx.eval(Source.newBuilder("wasm",
                            ByteSequence.create(stratBytes), "on_bar").build());
                        BacktestResult last = null;
                        for (int i = 0; i < perThread; i++) last = runStreaming(module, strings, bars);
                        return last;
                    }
                }));
            }
            boolean parallelOk = true;
            for (Future<BacktestResult> f : futures) {
                BacktestResult r = f.get();
                if (!parity(r, expTrades, expEquity, expSharpe)) parallelOk = false;
            }
            pool.shutdown();
            double totalMs = (System.nanoTime() - t0) / 1e6;
            System.out.printf("%d threads x %d backtests in %.0f ms total%n", threads, perThread, totalMs);
            System.out.println("leg 6: " + (parallelOk ? "PASS" : "FAIL"));
            allOk &= parallelOk;
        }

        System.out.println("\n=== GRAAL STRESS: " + (allOk ? "PASS" : "FAIL") + " ===");
        System.exit(allOk ? 0 : 1);
    }
}
