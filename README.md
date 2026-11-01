# Swizzlescope

A macOS runtime inspector and method tracer written in Objective-C. Load a framework, dylib or plug-in
bundle into the app, browse every class it contributes, export class-dump style headers, and tick any
method to log its calls live with decoded arguments, return values and timings.

It is a small, dependency-free project: a Makefile, clang, AppKit and the Objective-C runtime.

![Swizzlescope tracing -[NSView setNeedsDisplay:] while browsing NSWindow](docs/screenshot.png)

## Why Objective-C and not Swift

Everything this tool does lives in the Objective-C runtime's C API and its dynamic messaging model:

- **Runtime enumeration.** `objc_copyImageNames`, `objc_copyClassNamesForImage`, `class_copyMethodList`,
  `class_copyIvarList`, `class_copyPropertyList`. Calling these from Objective-C needs no bridging layer.
- **Message forwarding as a hook.** The tracer replaces a method's IMP with `_objc_msgForward`, so every call
  flows through `forwardInvocation:` where an `NSInvocation` exposes the arguments and return value. Swizzling,
  `NSInvocation`, alias selectors and `objc_msgSend` casts are natural in Objective-C and awkward or blocked in Swift.
- **Type encodings.** Argument and return types are decoded from `@encode` strings. Swift classes that do not
  inherit from `NSObject` are invisible to this runtime anyway, so Swift would add nothing here.
- **AppKit without SwiftUI.** Outline views, tables, split views and toolbars are built programmatically.

## Build and run

Requires Xcode command line tools (clang) on macOS 13 or later. Apple Silicon and Intel are both supported.

```sh
make            # builds build/Swizzlescope.app, build/swizzlescope (CLI) and build/Fixture.bundle
make run        # opens the app
make test       # runs Tests/run.sh: CLI end-to-end tests against the fixture bundle
```

## The app

- **Sidebar.** Every loaded image that contributes Objective-C classes, with the classes beneath it. The
  search field filters class names; prefix a query with `sel:` to find classes implementing a selector that
  contains the fragment (for example `sel:sendEvent`).
- **Methods tab.** Class and instance methods with decoded declarations and raw encodings. Tick **Trace** to
  start logging a method; untick to restore the original implementation. **Trace Shown** traces everything
  that matches the filter box.
- **Ivars, Properties, Protocols.** Offsets, decoded types and raw attribute strings.
- **Header.** A class-dump style `@interface`. **Export Header…** (⇧⌘E) saves it.
- **Playground.** Create an instance of the selected class, send it messages with typed arguments, and dump
  its ivars. Arguments are typed as text: numbers, `YES`/`NO`, `"strings"`, JSON arrays or objects, `nil`,
  class names for `Class`, selector names for `SEL`, `{x, y, w, h}` for structs.
- **Trace Log.** One line per traced call, written when the call returns. Sequence numbers reflect call order
  and nested traced calls are indented. **Pause** stops the display without untracing anything.
- **File > Open Bundle…** (⌘O) loads a `.framework`, `.bundle` or `.dylib` into the app's process.

Launch arguments, mainly for scripting and testing:

```sh
build/Swizzlescope.app/Contents/MacOS/Swizzlescope -load build/Fixture.bundle -select FXChild -tab Playground \
    -trace '-[NSWindow sendEvent:],-[FXChild addInt:toInt:]'
```

A good first thing to try: select `NSWindow`, trace `sendEvent:`, and click around the window.

## The command-line tool

`build/swizzlescope` shares the Core sources with the app and is also the test harness.

```sh
swizzlescope images                               # loaded images with class counts
swizzlescope classes Foundation                   # classes in images whose path contains "Foundation"
swizzlescope classes build/Fixture.bundle         # load a bundle, then list what it contributed
swizzlescope dump NSString                        # ivars, properties, methods with encodings
swizzlescope header FXBase build/Fixture.bundle   # class-dump style header
swizzlescope search sendEvent                     # classes implementing a selector containing "sendEvent"
swizzlescope load /path/To.framework              # load and report
swizzlescope call build/Fixture.bundle '-[FXBase insetRect:by:]' '{0, 0, 100, 50}' 5   # typed call
swizzlescope trace build/Fixture.bundle --run '+[FXChild runSelfTest]' \
    '-[FXBase greet:]' '-[FXChild addInt:toInt:]'   # trace, run, print events
```

Sample trace output:

```
#2 [main]   -[FXChild addInt:toInt:] <FXChild: 0x1049dc4f0> (2, 3) -> 105  1.2 µs
#5 [main]   -[FXBase greet:] <FXChild: 0x1049dc4f0> ("world") -> "Hello, world"  1.7 µs
#6 [main]   -[FXBase insetRect:by:] <FXChild: 0x1049dc4f0> ({{0, 0}, {100, 50}}, 5) -> {{5, 5}, {90, 40}}  541 ns
#1 [main] +[FXChild runSelfTest] () -> 16  123.1 µs
```

## How tracing works

1. The original IMP is stored under an alias selector, `__swizzlescope_<selector>`, on the same class.
2. The method's IMP is set to `_objc_msgForward` (or `_objc_msgForward_stret` on x86_64 for large struct
   returns). If the class only inherited the method, an override is added so the superclass is untouched.
3. The class's `forwardInvocation:` is replaced once with the tracer's hook; the previous implementation is
   kept under `__swizzlescope_forwardInvocation:` and still receives genuinely unknown selectors.
4. The hook decodes arguments from the `NSInvocation`, swaps in the alias selector, invokes, reads the return
   value and appends an event to a buffer. The UI drains the buffer every 100 ms.
5. Untracing puts the original IMP back.

Safety measures: a thread-local guard so calls made while describing or enqueueing an event pass through
silently; separate locks for the trace table and the event buffer; a blocklist for root `NSObject`
implementations, memory-management and forwarding selectors, and Swizzlescope's own classes; a refusal to trace
the same selector on both a class and one of its ancestors or descendants at the same time.

## Limits

- Inspects code loaded into its own process. Attaching to other running apps needs SIP disabled or a
  debugger entitlement, which is out of scope.
- `.app` main executables are `MH_EXECUTE` and cannot be `dlopen`'d. Load a framework or plug-in inside the app
  instead.
- Loading a bundle runs its initializers. Only load code you trust.
- Variadic methods and methods whose type encodings `NSInvocation` cannot represent are refused.
- Inside a traced method `_cmd` is the alias selector, which matters only to code that inspects `_cmd`.
- Tracing abstract class-cluster methods (for example `-[NSString length]`) shows nothing because concrete
  subclasses override them; trace the concrete class instead (`sel:` search helps find it).
- Tracing `init` family methods works but is experimental because `NSInvocation` does not model their
  ownership conventions.

## Layout

```
Core/      runtime enumeration, class model, type-encoding decoder, header writer, loader, tracer, value parser
App/       AppKit UI: window, sidebar, detail tabs, trace log, playground
CLI/       swizzlescope command-line tool
Fixture/   test bundle with methods covering common argument and return types
Tests/     run.sh end-to-end tests and golden headers
```

## Contributing

Issues and pull requests are welcome. Keep `Core/` free of AppKit so the CLI remains the test harness, and
extend `Tests/run.sh` (and the golden headers in `Tests/golden/`) when changing Core behaviour. CI builds
with warnings as errors and runs `make test` on the latest macOS runner.

## License

MIT. See [LICENSE](LICENSE).
