// SPDX-License-Identifier: MIT
// Smoke test only: exports exactly three original synthetic functions.
import ghidra.app.util.headless.HeadlessScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import java.nio.file.*;
import java.util.*;

public class SmokeDecompile extends HeadlessScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 1) throw new IllegalArgumentException("output directory required");
        Path out = Path.of(args[0]);
        Files.createDirectories(out);
        String lang = currentProgram.getLanguageID().toString();
        String format = currentProgram.getExecutableFormat();
        Files.writeString(out.resolve("program.txt"),
            "name=" + currentProgram.getName() + "\nlanguage=" + lang +
            "\ncompiler=" + currentProgram.getCompilerSpec().getCompilerSpecID() +
            "\nformat=" + format + "\nimageBase=" + currentProgram.getImageBase() + "\n");
        if (analysisTimeoutOccurred()) throw new IllegalStateException("automatic analysis timed out");
        if (!lang.startsWith("AARCH64:") || !format.toLowerCase(Locale.ROOT).contains("mach"))
            throw new IllegalStateException("not an AARCH64 Mach-O program");
        Set<String> expected = Set.of("wu_clamp_score", "wu_weighted_sum", "wu_choose_mode");
        Set<String> found = new HashSet<>();
        DecompInterface decompiler = new DecompInterface();
        try (var summary = Files.newBufferedWriter(out.resolve("functions.tsv"))) {
            decompiler.toggleCCode(true);
            decompiler.toggleSyntaxTree(true);
            if (!decompiler.openProgram(currentProgram)) throw new IllegalStateException("decompiler open failed");
            FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
            while (functions.hasNext()) {
                monitor.checkCancelled();
                Function f = functions.next();
                String name = f.getName().replaceFirst("^_+", "");
                if (!expected.contains(name)) continue;
                if (!found.add(name)) throw new IllegalStateException("duplicate target " + name);
                var result = decompiler.decompileFunction(f, 30, monitor);
                if (!result.decompileCompleted() || result.getDecompiledFunction() == null || result.getHighFunction() == null)
                    throw new IllegalStateException(name + ": " + result.getErrorMessage());
                String code = result.getDecompiledFunction().getC();
                if (code.length() < 80 || !code.contains("return"))
                    throw new IllegalStateException("empty or invalid decompiler output: " + name);
                Files.writeString(out.resolve(name + ".c.txt"),
                    "/* GHIDRA PSEUDOCODE: synthetic fixture, not recovered original source. */\n" + code);
                summary.write(name + "\t" + f.getEntryPoint() + "\tOK\t" + code.length() + "\n");
            }
        } finally { decompiler.dispose(); }
        if (!found.equals(expected)) throw new IllegalStateException("missing targets: " + found);
        Files.writeString(out.resolve("result.txt"), "PASS: 3/3 synthetic ARM64 Mach-O functions decompiled\n");
        println("Synthetic decompiler smoke: 3/3 functions exported");
    }
}
