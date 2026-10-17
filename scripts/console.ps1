# Usage: .\scripts\console.ps1 -ProcessId <pid> [-Send 'eventloop reload','cup reload'] [-Read 40]
# Types commands into the console of a running Wreckfest2.exe server and/or prints the last lines on its console screen.
# The server has no network remote-control, so this attaches to the server's console window and injects keystrokes
# (the same as typing there). Run it as its own process: it detaches this process from its own console while it works.
param(
    [Parameter(Mandatory)][int]$ProcessId,
    [string[]]$Send = @(),
    [string]$SendList = '',   # several commands in one argument, separated by |
    [int]$Read = 0,
    [int]$DelayMs = 400
)
$ErrorActionPreference = 'Stop'
if ($SendList) { $Send = @($Send) + ($SendList -split '\|' | Where-Object { $_.Trim() }) }

$p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if (-not $p -or $p.ProcessName -ne 'Wreckfest2') { throw "Process $ProcessId is not a running Wreckfest2.exe." }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WfConsole {
    [StructLayout(LayoutKind.Explicit, Size = 20)]
    struct INPUT_RECORD {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public int bKeyDown;
        [FieldOffset(8)] public ushort wRepeatCount;
        [FieldOffset(10)] public ushort wVirtualKeyCode;
        [FieldOffset(12)] public ushort wVirtualScanCode;
        [FieldOffset(14)] public char UnicodeChar;
        [FieldOffset(16)] public uint dwControlKeyState;
    }
    [StructLayout(LayoutKind.Sequential)] struct COORD { public short X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct SMALL_RECT { public short Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct CSBI { public COORD dwSize; public COORD dwCursorPosition; public ushort wAttributes; public SMALL_RECT srWindow; public COORD dwMaximumWindowSize; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteConsoleInput(IntPtr h, INPUT_RECORD[] buf, uint len, out uint written);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetConsoleScreenBufferInfo(IntPtr h, out CSBI info);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ReadConsoleOutputCharacter(IntPtr h, StringBuilder sb, uint len, COORD at, out uint read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000, SHARE_RW = 3, OPEN_EXISTING = 3;
    static readonly IntPtr INVALID = new IntPtr(-1);

    public static void Attach(uint pid) {
        FreeConsole();
        if (!AttachConsole(pid)) throw new InvalidOperationException("AttachConsole failed, error " + Marshal.GetLastWin32Error());
    }
    public static void Detach() { FreeConsole(); }

    public static void Type(string line) {
        IntPtr h = CreateFile("CONIN$", GENERIC_READ | GENERIC_WRITE, SHARE_RW, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == INVALID) throw new InvalidOperationException("Cannot open the console input, error " + Marshal.GetLastWin32Error());
        try {
            var recs = new INPUT_RECORD[(line.Length + 1) * 2]; int n = 0;
            foreach (char c in line) { recs[n++] = Key(c, 0, true); recs[n++] = Key(c, 0, false); }
            recs[n++] = Key('\r', 0x0D, true); recs[n++] = Key('\r', 0x0D, false);
            uint written;
            if (!WriteConsoleInput(h, recs, (uint)n, out written)) throw new InvalidOperationException("WriteConsoleInput failed, error " + Marshal.GetLastWin32Error());
        } finally { CloseHandle(h); }
    }
    static INPUT_RECORD Key(char c, ushort vk, bool down) {
        var r = new INPUT_RECORD(); r.EventType = 1; r.bKeyDown = down ? 1 : 0; r.wRepeatCount = 1;
        r.wVirtualKeyCode = vk; r.UnicodeChar = c; return r;
    }

    // Last `lines` non-empty rows of the console screen buffer.
    public static string[] Screen(int lines) {
        IntPtr h = CreateFile("CONOUT$", GENERIC_READ | GENERIC_WRITE, SHARE_RW, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == INVALID) throw new InvalidOperationException("Cannot open the console output, error " + Marshal.GetLastWin32Error());
        try {
            CSBI info; if (!GetConsoleScreenBufferInfo(h, out info)) throw new InvalidOperationException("GetConsoleScreenBufferInfo failed");
            int width = info.dwSize.X, last = Math.Max(info.dwCursorPosition.Y, info.srWindow.Bottom);
            var rows = new System.Collections.Generic.List<string>();
            for (int y = 0; y <= last; y++) {
                var sb = new StringBuilder(width); uint read;
                ReadConsoleOutputCharacter(h, sb, (uint)width, new COORD { X = 0, Y = (short)y }, out read);
                string s = sb.ToString().Replace('\0', ' ').TrimEnd();
                if (s.Length > 0) rows.Add(s);
            }
            int skip = Math.Max(0, rows.Count - lines);
            return rows.GetRange(skip, rows.Count - skip).ToArray();
        } finally { CloseHandle(h); }
    }
}
'@

try {
    [WfConsole]::Attach([uint32]$ProcessId)
    foreach ($cmd in $Send) {
        if ($cmd -match '[\x00-\x1f]') { throw 'Commands cannot contain control characters.' }
        [WfConsole]::Type($cmd)
        Start-Sleep -Milliseconds $DelayMs
    }
    if ($Read -gt 0) { [WfConsole]::Screen($Read) }
} finally {
    [WfConsole]::Detach()
}
