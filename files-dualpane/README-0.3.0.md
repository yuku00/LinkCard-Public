# Files Native Experiment 0.3.0

Target: Files (`com.apple.DocumentsApp`), iOS 16.6 build 20G75, RootHide arm64 + arm64e.

This is an implemented, restricted **new native Split instance** experiment, not a finished dual-pane file manager. The original root/tab/Full/Split controllers stay in place. A new native `DOCSplitBrowserViewController` is constructed on the main thread using a copied real configuration and the existing source observer, then displayed in an independent, dismissible UIKit container.

## Boundaries

- Validate runtime signatures before private construction. Copy the real config, assign an experiment state namespace, preserve the real scene and interaction mode. Disable the evidenced drag-and-drop option on the copy.
- Let the native Split factory create and connect its Full/sidebar/hierarchy/document manager/navigation datasource/action manager. Do not guess enums, create a second observer, or transplant original controllers.
- Check new Full/hierarchy/document manager/datasource/action manager/navigation identities against the original Split. This does not prove independent provider state or navigation history.
- Bind only the NEW Full's public browser delegate to the experiment container. Verify its document manager's `uiBrowserDelegate` points to the adapter. Internal native delegates remain native.
- Adapter declines document opening/preview and cancels document creation using the public completion contract. Disable public document creation. Runtime-signature-checked preview and context-menu guards act only on descendants of the experimental Split; original controller calls pass through unchanged.
- Native menus elsewhere may remain. **Do not copy, move, delete, rename, import, or perform other file-writing actions. This is not a write sandbox.** Files/provider normal activity, metadata, downloads and preferences are not globally suppressed. The probe does not itself perform networking or file writes.
- Close using the explicit button. UIKit forwards appearance; after modal dismissal, detach only the experimental child and clear owned strong references. Do not stop the shared observer or remove foreign subscription tokens.
- The memory-only report checks original parent edges, construction/presentation, selection/hierarchy callback counts, close/detach, and weak `stillAlive` snapshots after one second. `stillAlive` is not a leak diagnosis; callbacks are not proof of successful navigation.

## Final device round

1. Install 0.3.0, fully quit Files, reopen it. Do not separately run another collection-only round.
2. Within 180 seconds of launch, tap **原生实验 / 导出**, read the warning, choose **启动真实原生实例**.
3. Verify the new native browser is visible. Enter a harmless folder, enter a subfolder, go back. Try selection and cancel it; do not invoke write actions. A document/open/preview request should say the experiment does not support it.
4. Tap **关闭实验**. Check the original Files tree is still usable and its prior browsing position is sensible. Wait at least two seconds.
5. Tap **原生实验 / 导出** again and share the final report using its share button. If preflight blocks, the specific reason is included; do not keep retrying or collect another probe round. If Files crashes, stop rather than repeat.

The lifecycle recorder retains its 8192-event/2048-object cap and 180-second deadline from process startup. Experiment summary counts are main-thread state and can outlive that trace deadline; the report exposes both. No persistent log or automatic upload exists.

## Build and checks

The dedicated `.github/workflows/files-native-probe-roothide.yml` runs source boundary checks, executes the exact MRC wrappers against host self/nil/replacement initializer fixtures, builds with RootHide Theos for arm64 + arm64e, and verifies package identity, 0.3.0 version and actual Mach-O slices. The experiment and entry UI are ARC; the original lifecycle wrappers remain MRC.

Build success does not validate this private native UI placement or runtime navigation on a device. This final device round is for construction, independent navigation, selection and exit only, not cross-pane writes or two simultaneous new Split panes.
