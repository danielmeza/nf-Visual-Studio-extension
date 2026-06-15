// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

using System.Diagnostics;
using System.Threading;

namespace Blink
{
    public class Program
    {
        public static void Main()
        {
            int counter = 0;

            while (true)
            {
                // Set a breakpoint on the next line to confirm the debugger
                // attaches and stops on the device (standard-tooling F5 gate).
                Debug.WriteLine($"Blink {counter}");

                counter++;

                Thread.Sleep(1000);
            }
        }
    }
}
