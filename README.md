# Reproduction for bazelbuild/bazel#29186

Bazel 9.2.0 crashes with `ALREADY_DECLARED_CHILD_MISSING` when a top-level `alias()` is built with `--notrack_incremental_state` (https://github.com/bazelbuild/bazel/issues/29186). The tree is bzlmod with one dependency (`rules_shell`); no toolchain is needed.

## Reproducing

```
bazel clean && bazel test --notrack_incremental_state //...
```

Exits 37 with:

```
FATAL: bazel crashed due to an internal error. Printing stack trace:
java.lang.IllegalStateException: Unexpected inconsistency: BuildDriverKey of ActionLookupKey: ConfiguredTargetKey{label=//tools/aliased:aliased, config=BuildConfigurationKey[1a589d14ca3886895c1228db75ec6c30d0c253d2c9f4c3070e5f3535de94c607]}, [tools/aliased], ALREADY_DECLARED_CHILD_MISSING
	at com.google.devtools.build.lib.skyframe.NodeDroppingInconsistencyReceiver.noteInconsistencyAndMaybeThrow(NodeDroppingInconsistencyReceiver.java:73)
	at com.google.devtools.build.skyframe.DelegatingGraphInconsistencyReceiver.noteInconsistencyAndMaybeThrow(DelegatingGraphInconsistencyReceiver.java:39)
	at com.google.devtools.build.skyframe.SkyFunctionEnvironment.batchPrefetch(SkyFunctionEnvironment.java:278)
	at com.google.devtools.build.skyframe.SkyFunctionEnvironment.<init>(SkyFunctionEnvironment.java:230)
	at com.google.devtools.build.skyframe.SkyFunctionEnvironment.create(SkyFunctionEnvironment.java:182)
	at com.google.devtools.build.skyframe.AbstractParallelEvaluator$Evaluate.run(AbstractParallelEvaluator.java:442)
```

The `otherKeys` entry `[tools/aliased]` is the package of the alias itself, not the package of the target the alias points at.

Bisecting the flags: `--notrack_incremental_state` is necessary, while `--rewind_lost_inputs`, `--keep_going` and `--skip_incompatible_explicit_targets` are not, and `--noexperimental_merged_skyframe_analysis_execution` makes it pass, so Skymeld is required. Replacing the `alias()` in `tools/aliased/BUILD.bazel` with a direct reference such as a `filegroup` also passes. The alias has to be a top-level target, that is, matched by the wildcard pattern.

## Filler packages

`pkg/p1` through `pkg/p600` are timing ballast: one `genrule` and one `sh_test` each, and nothing references the alias. They exist so the alias's `BUILD_DRIVER` node runs after Skymeld has dropped the alias's `PACKAGE` node, which needs plenty of other actions still executing in between. At 600 packages the crash reproduced 5/5 on macOS and 3/3 on Linux; at 200 it reproduced only 3/5. Run `./generate.sh <n>` to change the count.

## Mechanism

Line numbers are from tag `9.2.0`.

For each top-level target, `BuildDriverFunction` looks up the `Target` to post a `TargetConfiguredEvent`. It asks Skyframe for the package of `configuredTarget.getOriginalLabel()` (`BuildDriverFunction.java:426`). That makes `BUILD_DRIVER` a parent of a `PACKAGE` node.

For an alias, `getOriginalLabel()` returns the alias's own label, not `actual` (`lib/rules/AliasConfiguredTarget.java:236-238`). So the package requested is `tools/aliased`, which holds nothing but the alias.

With `--notrack_incremental_state`, Skyframe drops nodes during the build once their consumers are done. The `tools/aliased` package node is dropped after the alias is analyzed. The alias's `BUILD_DRIVER` node runs later, during execution, and finds it gone.

Skyframe reports that as `ALREADY_DECLARED_CHILD_MISSING`. `NodeDroppingInconsistencyReceiver` tolerates a fixed set of parent -> child pairs (lines 42 and 51). `BUILD_DRIVER -> PACKAGE` isn't one of them, so it throws at line 73. `RewindableGraphInconsistencyReceiver` checks the same set, so `--rewind_lost_inputs` only changes the class at the top of the stack.
