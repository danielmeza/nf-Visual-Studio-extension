// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
//
// Layer A POC harness — headless nanoFramework debug-protocol test.
//
// Drives the SHARED nf-debugger wire-protocol client (the same one the AD7 engine
// and a future Concord engine sit on) to validate, with NO Visual Studio:
//
//   Tier 1a (gate)  : the SDK-built .pe is ACCEPTED + LOADABLE by a real nanoCLR
//                     runtime  (Engine.DeploymentExecute succeeds).
//   Tier 1b (gate)  : the deployed program EXECUTES (its Debug.WriteLine output is
//                     observed over Engine.OnMessage).
//   Tier 2 (bonus)  : a breakpoint command + hit notification ROUND-TRIPS
//                     (Engine.SetBreakpoints + Engine.OnCommand /
//                     c_Debugging_Execution_BreakpointHit). Best-effort: source-line
//                     breakpoints (method index + IP from the .pdbx / device type
//                     system) are what the AD7 engine layers on top and are
//                     validated by Layer B (real VS F5). See RESULTS.md.
//
// Target = the `nanoclr` Win32 virtual device over a virtual serial port
// (Windows-only), or a physical board. Build runs anywhere (net8.0).
//
// Usage:
//   nano-debug-protocol-test --port COM5 --pe <dir-or-file> [--expect Blink]
//       [--timeout 30] [--reboot] [--gate-on-deploy-only] [--require-breakpoint]

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using nanoFramework.Tools.Debugger;
using nanoFramework.Tools.Debugger.WireProtocol;

using BreakpointDef = nanoFramework.Tools.Debugger.WireProtocol.Commands.Debugging_Execution_BreakpointDef;

internal static class Program
{
    private static int Main(string[] args)
    {
        Options o;
        try
        {
            o = Options.Parse(args);
        }
        catch (ArgumentException ex)
        {
            Console.Error.WriteLine("ERROR: " + ex.Message);
            Options.PrintUsage();
            return 2;
        }

        List<byte[]> assemblies = LoadPeFiles(o.PePath, out var peNames);
        if (assemblies.Count == 0)
        {
            Console.Error.WriteLine($"ERROR: no .pe files found at '{o.PePath}'.");
            return 2;
        }

        Console.WriteLine($"== Layer A debug-protocol test ==");
        Console.WriteLine($"   port    : {o.Port}");
        Console.WriteLine($"   pe      : {peNames.Count} assembly(ies): {string.Join(", ", peNames)}");
        Console.WriteLine($"   expect  : program output containing \"{o.Expect}\"");
        Console.WriteLine($"   timeout : {o.TimeoutSeconds}s");
        Console.WriteLine();

        PortBase serialPort = PortBase.CreateInstanceForSerial(false);
        NanoDeviceBase device = serialPort.AddDevice(o.Port);
        if (device == null)
        {
            Console.Error.WriteLine($"FAIL: could not add device on port '{o.Port}'. Is the nanoclr virtual device running on that port?");
            return 1;
        }

        device.CreateDebugEngine();
        Engine engine = device.DebugEngine;

        bool ran = false;
        bool breakpointHit = false;
        using var ranSignal = new ManualResetEventSlim(false);
        using var hitSignal = new ManualResetEventSlim(false);

        engine.OnMessage += (IncomingMessage m, string text) =>
        {
            string line = (text ?? string.Empty).TrimEnd('\r', '\n');
            if (line.Length > 0)
            {
                Console.WriteLine("   [program] " + line);
            }

            if (!string.IsNullOrEmpty(o.Expect) && line.Contains(o.Expect))
            {
                ran = true;
                ranSignal.Set();
            }
        };

        engine.OnCommand += (IncomingMessage m, bool reply) =>
        {
            if (m?.Header != null && m.Header.Cmd == Commands.c_Debugging_Execution_BreakpointHit)
            {
                Console.WriteLine("   [engine] breakpoint-hit notification received");
                breakpointHit = true;
                hitSignal.Set();
            }
        };

        try
        {
            Console.WriteLine("-> connecting debug engine...");
            if (!engine.Connect(5000, true, true))
            {
                Console.Error.WriteLine("FAIL: could not connect the debug engine to the device.");
                return 1;
            }

            Console.WriteLine($"   connected: nanoCLR={engine.IsConnectedTonanoCLR}, source={engine.ConnectionSource}");

            try
            {
                var info = device.GetDeviceInfo(true);
                Console.WriteLine("   device info: " + (info != null ? info.ToString().Split('\n').FirstOrDefault()?.Trim() : "<none>"));
            }
            catch (Exception ex)
            {
                Console.WriteLine("   (device info unavailable: " + ex.Message + ")");
            }

            // --- Tier 1a: deploy the SDK-built PE(s) -------------------------------
            Console.WriteLine($"-> deploying {assemblies.Count} assembly(ies)...");
            bool deployed = engine.DeploymentExecute(assemblies, o.Reboot, false, null, new ConsoleProgress());
            if (!deployed)
            {
                Console.Error.WriteLine("FAIL (Tier 1a): the runtime rejected the deployment — the SDK-built PE did not load.");
                return 1;
            }
            Console.WriteLine("   OK (Tier 1a): deployment accepted — the SDK-built PE is loadable on nanoCLR.");

            // --- Tier 2 setup: best-effort breakpoint (symbol-free round-trip) -----
            if (!o.GateOnDeployOnly)
            {
                try
                {
                    var bp = new BreakpointDef
                    {
                        // Fires when assemblies load — exercises the breakpoint command +
                        // hit-notification path WITHOUT needing device-side symbol
                        // resolution (that is the AD7 engine's job; see Layer B).
                        m_flags = BreakpointDef.c_ASSEMBLIES_LOADED,
                        m_pid = unchecked((uint)BreakpointDef.c_PID_ANY),
                    };
                    engine.SetBreakpoints(new[] { bp });
                    Console.WriteLine("   breakpoint armed (assemblies-loaded round-trip check).");
                }
                catch (Exception ex)
                {
                    Console.WriteLine("   (could not arm breakpoint: " + ex.Message + ")");
                }
            }

            // --- Tier 1b: run and observe execution --------------------------------
            Console.WriteLine("-> resuming execution...");
            engine.ResumeExecution();

            var deadline = TimeSpan.FromSeconds(o.TimeoutSeconds);
            var handles = new[] { ranSignal.WaitHandle, hitSignal.WaitHandle };
            var sw = System.Diagnostics.Stopwatch.StartNew();
            while (sw.Elapsed < deadline && !(ran && (breakpointHit || o.GateOnDeployOnly)))
            {
                WaitHandle.WaitAny(handles, 500);
            }
        }
        finally
        {
            try { engine?.Stop(); } catch { /* best effort */ }
            try { device?.Disconnect(true); } catch { /* best effort */ }
        }

        // --- verdict ---------------------------------------------------------------
        Console.WriteLine();
        Console.WriteLine("== results ==");
        Console.WriteLine($"   Tier 1a deploy/load : PASS");
        Console.WriteLine($"   Tier 1b execution   : {(ran ? "PASS" : (o.GateOnDeployOnly ? "skipped" : "NOT OBSERVED"))}");
        Console.WriteLine($"   Tier 2  breakpoint  : {(breakpointHit ? "PASS" : "not observed (best-effort)")}");

        bool gatePass = true;
        if (!o.GateOnDeployOnly && !ran)
        {
            gatePass = false;
        }
        if (o.RequireBreakpoint && !breakpointHit)
        {
            gatePass = false;
        }

        Console.WriteLine();
        Console.WriteLine(gatePass ? "RESULT: PASS" : "RESULT: FAIL");
        return gatePass ? 0 : 1;
    }

    /// <summary>Reads each .pe into a 4-byte-aligned buffer (mirrors DeployProvider).</summary>
    private static List<byte[]> LoadPeFiles(string path, out List<string> names)
    {
        names = new List<string>();
        var files = new List<string>();

        if (Directory.Exists(path))
        {
            files.AddRange(Directory.GetFiles(path, "*.pe"));
        }
        else if (File.Exists(path))
        {
            files.Add(path);
        }

        // Deploy core libraries first if present (resolution order safety).
        files = files
            .OrderBy(f => Path.GetFileName(f).Equals("mscorlib.pe", StringComparison.OrdinalIgnoreCase) ? 0 : 1)
            .ThenBy(Path.GetFileName)
            .ToList();

        var assemblies = new List<byte[]>();
        foreach (string file in files)
        {
            byte[] raw = File.ReadAllBytes(file);
            long aligned = (raw.Length + 3) / 4 * 4;
            byte[] buffer = new byte[aligned];
            Array.Copy(raw, buffer, raw.Length);
            assemblies.Add(buffer);
            names.Add(Path.GetFileNameWithoutExtension(file));
        }

        return assemblies;
    }

    private sealed class ConsoleProgress : IProgress<string>
    {
        public void Report(string value)
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                Console.WriteLine("   [deploy] " + value.TrimEnd());
            }
        }
    }
}

internal sealed class Options
{
    public string Port = "";
    public string PePath = "";
    public string Expect = "Blink";
    public int TimeoutSeconds = 30;
    public bool Reboot;
    public bool GateOnDeployOnly;
    public bool RequireBreakpoint;

    public static Options Parse(string[] args)
    {
        var o = new Options();
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--port": o.Port = Next(args, ref i); break;
                case "--pe": o.PePath = Next(args, ref i); break;
                case "--expect": o.Expect = Next(args, ref i); break;
                case "--timeout": o.TimeoutSeconds = int.Parse(Next(args, ref i)); break;
                case "--reboot": o.Reboot = true; break;
                case "--gate-on-deploy-only": o.GateOnDeployOnly = true; break;
                case "--require-breakpoint": o.RequireBreakpoint = true; break;
                default: throw new ArgumentException("unknown argument: " + args[i]);
            }
        }

        if (string.IsNullOrEmpty(o.Port)) throw new ArgumentException("--port is required");
        if (string.IsNullOrEmpty(o.PePath)) throw new ArgumentException("--pe is required");
        return o;
    }

    private static string Next(string[] args, ref int i)
    {
        if (i + 1 >= args.Length) throw new ArgumentException("missing value after " + args[i]);
        return args[++i];
    }

    public static void PrintUsage()
    {
        Console.Error.WriteLine(
            "usage: nano-debug-protocol-test --port <name> --pe <dir-or-file> " +
            "[--expect <token>] [--timeout <seconds>] [--reboot] " +
            "[--gate-on-deploy-only] [--require-breakpoint]");
    }
}
