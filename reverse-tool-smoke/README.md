# Ghidra synthetic ARM64 smoke

This isolated, **manual-only** workflow validates Ghidra 12.2's native decompiler with three original, non-sensitive C functions compiled to an ARM64 Mach-O object. It does not accept an uploaded file, URL, plugin, or arbitrary path.

## What runs
- Ubuntu 24.04 x64 standard GitHub-hosted runner, 20-minute cap.
- Preinstalled JDK 25 required; no fallback JDK download.
- Official Ghidra 12.2 ZIP (569,712,708 bytes) checked against SHA-256 `2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67`.
- Native source tests, ARM64 Mach-O header validation, Ghidra headless import and actual `DecompInterface.decompileFunction` on all three named functions.
- Success requires explicit per-function results and nonempty C-like output, not just an import or zero exit status.

The output is pseudocode, not recovered original source. This smoke does not verify Objective-C/Swift handling, private host interfaces, functional parity, or mobile runtime behavior.

## Privacy and lifetime
Only synthetic source, generated object, pseudocode and logs are published. No original plugin, proprietary sample, account data, credentials, or private decompilation output is used. The workflow has read-only content permissions, no credentials persisted by checkout, no schedule or push trigger, no Actions cache, and one-day artifact retention. Temporary Ghidra/project files are removed on normal completion; GitHub controls runner teardown. Platform retention is not a guarantee of physical erasure.

After evidence is saved locally, a user can delete the workflow run and its artifact through Actions; removing the workflow file disables further manual runs. Nothing is added to the plugin build or runtime.

## Local desktop use
`run.sh` is tailored to the preinstalled GitHub runner environment. Do not change the input to private samples and run on a public repository without a separate authorized private-transfer and result-return design.

The synthetic fixture, Java exporter and shell script are original MIT-licensed material. Ghidra retains its own Apache-2.0/third-party licensing and is downloaded from the official project, not redistributed in this repository.
