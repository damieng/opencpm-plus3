# zx84 MCP Smoke Test

Manual pre-commit smoke test for the default `build/cpm3.dsk` image using the
zx84 MCP emulator.

Run this after:

- `python3 tools/z80lint.py`
- `build.cmd`

The goal is to catch:

- boot regressions
- CCP command regressions
- BBC BASIC launch/exit regressions
- file operation regressions (`TYPE`, `REN`, wildcard `DIR`)
- disk-performance regressions (extra retries or materially higher cycle counts)

## Setup

Start the emulator and boot the image:

```text
model +3
load build/cpm3.dsk
disk_boot
run 1000
```

Find the screen buffer address from the BIOS listing:

```text
rg "char_buffer:" build/bios.lst
```

Use that address with the emulator's `char_buffer` command or memory viewer.
OCR is not reliable with the 5px font, so prefer the character buffer over OCR.

## Performance Notes

At each disk-heavy step below:

- inspect `fdc_log`
- confirm there are no retries
- note the cycle counts for comparison with previous runs

Treat retries as a bug. Treat a noticeable cycle-count increase across the same
workflow as a regression to investigate before committing.

## Test Flow

### 1. Boot and initial directory

At the CCP prompt, run:

```text
DIR
```

Check:

- the screen buffer shows the signon line and a directory listing
- `fdc_log` shows normal reads with no retries

### 2. Launch BBC BASIC and run a program

At the CCP prompt, run:

```text
BBCBASIC
```

Then type:

```text
10 PRINT "Hello"
RUN
```

Check:

- the screen buffer shows the BBC BASIC banner or prompt
- after `RUN`, the screen buffer contains `Hello`
- `fdc_log` does not show retries during launch

Exit BBC BASIC:

```text
QUIT
```

Check:

- control returns to the CCP prompt cleanly

### 3. Directory again

Run:

```text
DIR
```

Check:

- the CCP prompt and directory listing still render correctly
- `fdc_log` remains retry-free

### 4. TYPE a SUB file

Run:

```text
TYPE RPED.SUB
```

Check:

- file contents display in the screen buffer
- `fdc_log` remains retry-free

### 5. Rename the SUB file

Run:

```text
REN RPED.SUB TEST.SUB
DIR A:*.SUB
```

Check:

- the wildcard directory shows `TEST.SUB`
- `RPED.SUB` no longer appears
- `fdc_log` remains retry-free

### 6. Optional cleanup

To restore the original filename before finishing:

```text
REN TEST.SUB RPED.SUB
DIR A:*.SUB
```

Check:

- `RPED.SUB` is present again

## Suggested MCP Input Pattern

When driving the emulator interactively, the typical pattern is:

```text
type "DIR"
key enter
```

Repeat that for each command (`BBCBASIC`, `RUN`, `QUIT`, etc.). After each
step, inspect:

- screen contents via `char_buffer`
- disk behaviour via `fdc_log`

## Commit Gate

Before committing, this smoke test should pass with:

- successful boot
- correct screen-buffer contents at each checkpoint
- BBC BASIC launch, `RUN`, and `QUIT` working
- successful `TYPE`, `REN`, and wildcard `DIR`
- no FDC retries
- no unexplained cycle-count regression
