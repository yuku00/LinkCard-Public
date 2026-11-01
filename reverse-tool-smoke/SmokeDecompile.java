// SPDX-License-Identifier: MIT
// Smoke test only: exports exactly three original synthetic functions.
import ghidra.app.util.headless.HeadlessScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.model.address.Address;
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
            Map<String, Address> targets = new TreeMap<>();
            SymbolIterator symbols = currentProgram.getSymbolTable().getAllSymbols(true);
            try (var inventory = Files.newBufferedWriter(out.resolve("synthetic-symbols.tsv"))) {
                while (symbols.hasNext()) {
                    Symbol symbol = symbols.next();
                    inventory.write(symbol.getName() + "\t" + symbol.getAddress() + "\n");
                    String name = symbol.getName().replaceFirst("^_+", "");
                    if (expected.contains(name) && symbol.getAddress().isMemoryAddress()) {
                        Address old = targets.putIfAbsent(name, symbol.getAddress());
                        if (old != null && !old.equals(symbol.getAddress()))
                            throw new IllegalStateException("ambiguous symbol " + name);
                    }
                }
            }
            for (var target : targets.entrySet()) {
                monitor.checkCancelled();
                String name = target.getKey();
                Function f = getFunctionAt(target.getValue());
                if (f == null) {
                    disassemble(target.getValue());
                    f = createFunction(target.getValue(), name);
                }
                if (f == null) throw new IllegalStateException("no function at symbol " + name);
                // Entry functions can have an analyzer-selected primary name.
                // The synthetic Mach-O symbol, not that primary name, identifies the target.
                f.setName(name, SourceType.USER_DEFINED);
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
