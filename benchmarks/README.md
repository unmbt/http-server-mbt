# Native benchmark

Run a repeatable in-process static-file measurement with:

```text
moon run benchmarks --target native --release -- --root testdata/public --path /hello.txt --iterations 10000
```

`--io-backend platform` is the stable default. On Linux, `--io-backend auto`
uses the experimental io_uring file-read path only when the startup probe
succeeds; `--io-backend io_uring` fails before opening the engine when the
kernel or sandbox does not provide it. The output is observational evidence,
not a performance acceptance threshold.
