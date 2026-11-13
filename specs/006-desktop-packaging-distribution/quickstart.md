# Quickstart: Packaging & Distributing RxGenerator Desktop

## Prerequisites

1. Working Elixir 1.17+ and Erlang/OTP 27+ installation on the build machine.
2. Windows: Built-in `.NET Framework 4.8` (`csc.exe`) for compiling the native WebView2 supervisor runner.
3. Linux: `dpkg-deb` and `gcc` for assembling the `.deb` package.

---

## 1. Assembling the Standalone Mix Release

Set environment variables and build release:

```powershell
# Set production environment
$env:MIX_ENV="prod"

# Install production dependencies
mix deps.get --only prod

# Compile production assets
mix assets.deploy

# Assemble the self-contained BEAM release (bundles ERTS)
mix release rx_generator --overwrite
```

---

## 2. Compiling the Native Desktop Runner (Windows)

The native runner is compiled using the Windows standard C# compiler:

```powershell
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" `
  /target:winexe `
  /out:"_build\prod\rel\rx_generator\bin\RxGeneratorApp.exe" `
  /reference:System.Windows.Forms.dll `
  /reference:System.Drawing.dll `
  native_runner\windows\RxGeneratorApp.cs
```

---

## 3. Running & Testing the Packaged App

Launch the native wrapper:

```powershell
& "_build\prod\rel\rx_generator\bin\RxGeneratorApp.exe"
```

1. The app automatically creates `%APPDATA%\RxGenerator`, copies the pre-seeded catalog database, generates persistent secrets, and executes migrations.
2. The Phoenix server binds to an available loopback port on `127.0.0.1`.
3. The native WebView2 window launches and loads the RxGenerator LiveView prescription interface in < 3.5 seconds.
4. Closing the window cleanly shuts down the BEAM release node.

