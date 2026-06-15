using System;
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
                // Set a breakpoint on the next line for the WS4 debug validation.
                Debug.WriteLine($"Blink {counter}");
                counter++;

                Thread.Sleep(1000);
            }
        }
    }
}
