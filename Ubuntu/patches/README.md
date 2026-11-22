# Unified diffs

These diffs are generated from the upstream files this submission replaces, as
they exist on the `installers` branch of FOSSEE/eSim (and, for NGHDL, the files
bundled in `nghdl.zip` inside `eSim-2.5.zip`):

| Patch | Base file | Result |
|---|---|---|
| `0001-install-eSim-25.04-support.patch` | `Ubuntu/install-eSim.sh` | 25.04/25.10 dispatch, `/etc/os-release` parsing, dead code removed |
| `0002-nghdl-25.04-llvm18.patch` | `nghdl/install-nghdl.sh` | 25.04/25.10 dispatch and new `install-nghdl-scripts/install-nghdl-25.04.sh` |
| `0003-install-eSim-25.04-fixes.patch` | `Ubuntu/install-eSim-scripts/install-eSim-25.04.sh` | the 25.04 profile fixes (I-03…I-15) |

They apply to a checkout of the fork at the same relative paths:

```bash
cd ~/eSim            # fork, branch installers-ubuntu-25.04
patch -p1 < /path/to/esim-ubuntu-25.04/patches/0001-install-eSim-25.04-support.patch
```

For an extracted `eSim-2.5` tree the layout is different (`install-eSim.sh` is
at the root and the NGHDL files come from `nghdl.zip`), so use the copy-based
helper instead:

```bash
bash tools/apply-patches.sh /path/to/eSim-2.5
```

That helper is what was used for the verified end-to-end run.
