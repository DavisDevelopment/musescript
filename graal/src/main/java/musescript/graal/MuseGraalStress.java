package musescript.graal;

import org.graalvm.polyglot.Context;
import org.graalvm.polyglot.Engine;
import org.graalvm.polyglot.Source;
import org.graalvm.polyglot.Value;
import org.graalvm.polyglot.io.ByteSequence;
import org.graalvm.polyglot.proxy.ProxyObject;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import musescript.graal.MuseBacktestCore.Bar;
import musescript.graal.MuseBacktestCore.BacktestResult;
import musescript.graal.MuseBacktestCore.HostState;

/**
 * MuseScript stress test on GraalVM's WebAssembly runtime (GraalWasm).
 *
 * Exercises the dual memory ABI:
 *   streaming  — reset(capacity) + push_bar(...)
 *   preloaded  — pack OHLCV into exported memory + configure_tape + on_bar(index)
 *
 * Host ABI is side-effects only (get_param / long / short / flat).
 *
 * The actual backtest harness (OrderSim, streaming/preloaded runners, CSV/strings loading) lives
 * in MuseBacktestCore.java, shared with KestrGraalServer.java's persistent-process RPC handler —
 * this file is now just the one-shot stress-test driver + the polySum math-kernel legs.
 */
public final class MuseGraalStress {

    static final Map<String, Double> DEFAULT_PARAMS = Map.of("fast", 10.0, "slow", 30.0);

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

    public static void main(String[] argv) throws Exception {
        Path root = Path.of(argv.length > 0 ? argv[0] : "..").toAbsolutePath().normalize();
        Path graalDir = root.resolve("build/graal");
        System.out.println("=== MuseScript GraalWasm stress (memory ABI) ===");
        System.out.println("root: " + root);
        System.out.println("jvm:  " + System.getProperty("java.vm.name") + " " + System.getProperty("java.vm.version"));

        List<Bar> bars = MuseBacktestCore.loadCsv(root.resolve("data/real/spy.csv"));
        List<String> strings = MuseBacktestCore.loadStrings(graalDir.resolve("on_bar.strings.json"));
        String expectedJson = Files.readString(graalDir.resolve("expected.json"));
        int expTrades = (int) MuseBacktestCore.jsonNumber(expectedJson, "trades");
        double expEquity = MuseBacktestCore.jsonNumber(expectedJson, "finalEquity");
        double expSharpe = MuseBacktestCore.jsonNumber(expectedJson, "sharpe");
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
            BacktestResult rs = MuseBacktestCore.runStreaming(stratModule, strings, bars, DEFAULT_PARAMS);
            System.out.printf("streaming trades=%d equity=%s sharpe=%s%n", rs.trades(), rs.finalEquity(), rs.sharpe());
            boolean streamOk = MuseBacktestCore.parity(rs, expTrades, expEquity, expSharpe);
            System.out.println("leg 2a: " + (streamOk ? "PASS" : "FAIL"));
            allOk &= streamOk;

            System.out.println("\n--- leg 2b: preloaded configure_tape/on_bar parity ---");
            BacktestResult rp = MuseBacktestCore.runPreloaded(stratModule, strings, bars, DEFAULT_PARAMS);
            System.out.printf("preloaded trades=%d equity=%s sharpe=%s%n", rp.trades(), rp.finalEquity(), rp.sharpe());
            boolean preloadOk = MuseBacktestCore.parity(rp, expTrades, expEquity, expSharpe)
                && rs.trades() == rp.trades()
                && Math.abs(rs.finalEquity() - rp.finalEquity()) <= 1e-6;
            System.out.println("leg 2b: " + (preloadOk ? "PASS (matches streaming + interp)" : "FAIL"));
            allOk &= preloadOk;

            System.out.println("\n--- leg 3: sequential throughput (streaming) ---");
            int warm = 3, timedRuns = 20;
            for (int i = 0; i < warm; i++) MuseBacktestCore.runStreaming(stratModule, strings, bars, DEFAULT_PARAMS);
            t0 = System.nanoTime();
            for (int i = 0; i < timedRuns; i++) {
                BacktestResult rr = MuseBacktestCore.runStreaming(stratModule, strings, bars, DEFAULT_PARAMS);
                if (rr.trades() != expTrades) throw new IllegalStateException("nondeterministic!");
            }
            double perRun = (System.nanoTime() - t0) / 1e6 / timedRuns;
            System.out.printf("%d backtests x %d bars: %.2f ms/backtest (%.0f bars/sec)%n",
                timedRuns, bars.size(), perRun, bars.size() / (perRun / 1000.0));
            System.out.println("leg 3: PASS");

            System.out.println("\n--- leg 4: sequential throughput (preloaded) ---");
            for (int i = 0; i < warm; i++) MuseBacktestCore.runPreloaded(stratModule, strings, bars, DEFAULT_PARAMS);
            t0 = System.nanoTime();
            for (int i = 0; i < timedRuns; i++) MuseBacktestCore.runPreloaded(stratModule, strings, bars, DEFAULT_PARAMS);
            double perRunP = (System.nanoTime() - t0) / 1e6 / timedRuns;
            System.out.printf("%d backtests x %d bars: %.2f ms/backtest (%.0f bars/sec)%n",
                timedRuns, bars.size(), perRunP, bars.size() / (perRunP / 1000.0));
            System.out.println("leg 4: PASS");

            System.out.println("\n--- leg 5: module instantiation cost ---");
            int instRuns = 500;
            ProxyObject dummyEnv = MuseBacktestCore.makeEnv(new HostState(), strings);
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
                        for (int i = 0; i < perThread; i++) last = MuseBacktestCore.runStreaming(module, strings, bars, DEFAULT_PARAMS);
                        return last;
                    }
                }));
            }
            boolean parallelOk = true;
            for (Future<BacktestResult> f : futures) {
                BacktestResult r = f.get();
                if (!MuseBacktestCore.parity(r, expTrades, expEquity, expSharpe)) parallelOk = false;
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
