using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

// Split-pane host for Everything. It opens two NEW Everything windows and embeds them.
// Windows that were already open are never adopted or closed.
static class W
{
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    public delegate void HookProc(IntPtr hook, uint ev, IntPtr h, int obj, int child, uint thread, uint time);
    [DllImport("user32")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32")] public static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
    [DllImport("user32", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32")] public static extern IntPtr SetParent(IntPtr c, IntPtr p);
    [DllImport("user32", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetLong(IntPtr h, int i);
    [DllImport("user32", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetLong(IntPtr h, int i, IntPtr v);
    [DllImport("user32")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hi, bool r);
    [DllImport("user32")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hi, uint f);
    [DllImport("user32")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
    [DllImport("user32")] public static extern bool UnregisterHotKey(IntPtr h, int id);
    [DllImport("user32")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32")] public static extern IntPtr SetWinEventHook(uint a, uint b, IntPtr m, HookProc p, uint pid, uint th, uint f);
    [DllImport("user32")] public static extern bool UnhookWinEvent(IntPtr h);
    [DllImport("oleacc")] static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);

    public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    public static List<IntPtr> Tops()
    {
        var r = new List<IntPtr>();
        EnumWindows((h, l) => { if (IsWindowVisible(h) && Cls(h).StartsWith("EVERYTHING_(")) r.Add(h); return true; }, IntPtr.Zero);
        return r;
    }
    public static IntPtr TabBar(IntPtr p)
    {
        IntPtr f = IntPtr.Zero;
        EnumChildWindows(p, (h, l) => { if (Cls(h) == "SysTabControl32") { f = h; return false; } return true; }, IntPtr.Zero);
        return f;
    }
    static Accessibility.IAccessible Acc(IntPtr h)
    {
        Guid g = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71"); object o;
        if (h == IntPtr.Zero || AccessibleObjectFromWindow(h, 0xFFFFFFFC, ref g, out o) != 0 || o == null) return null;
        return (Accessibility.IAccessible)o;
    }
    public static List<string> TabNames(IntPtr win)
    {
        var r = new List<string>();
        var a = Acc(TabBar(win));
        if (a == null) return r;
        try
        {
            int n = a.accChildCount;
            for (int i = 1; i <= n; i++) { string s = ""; try { s = a.get_accName(i) ?? ""; } catch { } r.Add(s); }
        }
        finally { Marshal.ReleaseComObject(a); }
        return r;
    }
    public static int CurTab(IntPtr win)
    {
        IntPtr t = TabBar(win);
        return t == IntPtr.Zero ? -1 : SendMessage(t, 0x130B, IntPtr.Zero, IntPtr.Zero).ToInt32();
    }
    public static void SelectTab(IntPtr win, int idx)
    {
        IntPtr t = TabBar(win);
        if (t == IntPtr.Zero) return;
        SendMessage(t, 0x1330, (IntPtr)idx, IntPtr.Zero);
        if (CurTab(win) != idx)
        {
            var a = Acc(t);
            if (a != null) { try { a.accDoDefaultAction(idx + 1); } catch { } finally { Marshal.ReleaseComObject(a); } }
        }
    }
}

class TabRef { public IntPtr Win; public string Title; public int Index; public string PaneName; }

class Pane
{
    public IntPtr Hwnd; public Panel Host; public string Name; public IntPtr OldStyle;
    public void Fit() { if (W.IsWindow(Hwnd)) W.MoveWindow(Hwnd, 0, 0, Host.ClientSize.Width, Host.ClientSize.Height, true); }
}

class Palette : Form
{
    readonly TextBox box = new TextBox { Dock = DockStyle.Top };
    readonly ListBox list = new ListBox { Dock = DockStyle.Fill, IntegralHeight = false };
    readonly List<TabRef> all; List<TabRef> shown = new List<TabRef>();
    public TabRef Picked;
    public Palette(List<TabRef> tabs)
    {
        all = tabs; Text = "Search tabs"; FormBorderStyle = FormBorderStyle.SizableToolWindow; StartPosition = FormStartPosition.CenterParent;
        Size = new Size(620, 380); KeyPreview = true; ShowInTaskbar = false; Font = new Font("Segoe UI", 10);
        Controls.Add(list); Controls.Add(box);
        box.TextChanged += (s, e) => Apply();
        list.DoubleClick += (s, e) => Pick();
        KeyDown += OnKey;
        Shown += (s, e) => box.Focus();
        Apply();
    }
    void Apply()
    {
        var words = box.Text.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        shown = all.Where(t => words.All(w => t.Title.IndexOf(w, StringComparison.OrdinalIgnoreCase) >= 0)).ToList();
        list.BeginUpdate(); list.Items.Clear();
        foreach (var t in shown) list.Items.Add("[" + t.PaneName + "] " + t.Title);
        if (shown.Count > 0) list.SelectedIndex = 0;
        list.EndUpdate();
    }
    void Pick() { if (list.SelectedIndex >= 0) { Picked = shown[list.SelectedIndex]; DialogResult = DialogResult.OK; Close(); } }
    void OnKey(object s, KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape) { Close(); e.Handled = e.SuppressKeyPress = true; }
        else if (e.KeyCode == Keys.Enter) { Pick(); e.Handled = e.SuppressKeyPress = true; }
        else if ((e.KeyCode == Keys.Down || e.KeyCode == Keys.Up) && shown.Count > 0)
        {
            int d = e.KeyCode == Keys.Down ? 1 : -1;
            list.SelectedIndex = Math.Max(0, Math.Min(shown.Count - 1, list.SelectedIndex + d));
            e.Handled = e.SuppressKeyPress = true;
        }
    }
}

class Host : Form
{
    const int WM_HOTKEY = 0x312, GWL_STYLE = -16, MaxRecent = 64;
    const long WS_CAPTION = 0xC00000, WS_THICKFRAME = 0x40000, WS_SYSMENU = 0x80000, WS_MINMAX = 0x30000;
    const uint MOD = 0x0002 | 0x0001 | 0x4000; // Ctrl+Alt, no auto-repeat
    readonly string exe, statePath;
    readonly SplitContainer split = new SplitContainer { Dock = DockStyle.Fill, SplitterWidth = 6 };
    readonly Pane left = new Pane { Name = "L" }, right = new Pane { Name = "R" };
    readonly List<TabRef> recent = new List<TabRef>();
    readonly Timer settle = new Timer { Interval = 150 };
    W.HookProc hookProc; IntPtr fgHook, selHook, nameHook; bool keysOn; Palette palette; Pane active;

    public Host(string exePath, string state)
    {
        exe = exePath; statePath = state; Text = "Everything Split"; Size = new Size(1000, 680); StartPosition = FormStartPosition.CenterScreen;
        Controls.Add(split); left.Host = split.Panel1; right.Host = split.Panel2; active = left;
        split.Panel1.Resize += (s, e) => left.Fit(); split.Panel2.Resize += (s, e) => right.Fit();
        settle.Tick += (s, e) => { settle.Stop(); NoteCurrent(); WriteState(); };
        Shown += (s, e) => Start();
        FormClosing += (s, e) => Release();
    }

    IntPtr OpenNew(HashSet<IntPtr> known)
    {
        var p = new ProcessStartInfo(exe, "-url \"es:?newwindow=1&newtab=1\"") { UseShellExecute = false };
        using (Process.Start(p)) { }
        var clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < 10000)
        {
            Application.DoEvents();
            foreach (var h in W.Tops()) if (!known.Contains(h)) return h;
            System.Threading.Thread.Sleep(80);
        }
        return IntPtr.Zero;
    }

    void Adopt(Pane p, IntPtr h)
    {
        p.Hwnd = h; p.OldStyle = W.GetLong(h, GWL_STYLE);
        long st = p.OldStyle.ToInt64() & ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINMAX);
        W.ShowWindow(h, 9);
        W.SetLong(h, GWL_STYLE, (IntPtr)st);
        W.SetParent(h, p.Host.Handle);
        W.SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, 0x0027); // keep size/pos/z, apply frame
        p.Fit();
    }

    void Start()
    {
        var known = new HashSet<IntPtr>(W.Tops());
        IntPtr a = OpenNew(known); if (a == IntPtr.Zero) { Fail(); return; }
        known.Add(a);
        IntPtr b = OpenNew(known); if (b == IntPtr.Zero) { W.PostMessage(a, 0x10, IntPtr.Zero, IntPtr.Zero); Fail(); return; }
        Adopt(left, a); Adopt(right, b);
        hookProc = OnEvent;
        fgHook = W.SetWinEventHook(3, 3, IntPtr.Zero, hookProc, 0, 0, 2);
        uint pid; W.GetWindowThreadProcessId(a, out pid);
        selHook = W.SetWinEventHook(0x8006, 0x8006, IntPtr.Zero, hookProc, pid, 0, 2);
        nameHook = W.SetWinEventHook(0x800C, 0x800C, IntPtr.Zero, hookProc, pid, 0, 2);
        FocusPane(left); SyncKeys(); NoteCurrent(); WriteState();
    }
    void Fail() { MessageBox.Show(this, "Could not open two Everything windows.", Text); Close(); }

    void OnEvent(IntPtr hook, uint ev, IntPtr h, int obj, int child, uint thread, uint time)
    {
        if (ev == 3)
        {
            if (h == left.Hwnd) active = left; else if (h == right.Hwnd) active = right;
            SyncKeys(); settle.Stop(); settle.Start();
        }
        else if (W.Cls(h) == "SysTabControl32") { settle.Stop(); settle.Start(); }
    }

    bool OursInFront()
    {
        IntPtr f = W.GetForegroundWindow();
        return f == Handle || f == left.Hwnd || f == right.Hwnd || (palette != null && f == palette.Handle);
    }
    void SyncKeys()
    {
        bool want = OursInFront();
        if (want == keysOn) return;
        keysOn = want;
        uint[] vks = { 'K', 'E', 'O', 'S' };
        for (int i = 0; i < vks.Length; i++) { if (want) W.RegisterHotKey(Handle, i + 1, MOD, vks[i]); else W.UnregisterHotKey(Handle, i + 1); }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY)
        {
            int id = m.WParam.ToInt32();
            if (id == 1) SearchTabs(); else if (palette == null)
            {
                if (id == 2) RecentTab();
                else if (id == 3) FocusPane(active == left ? right : left);
                else if (id == 4) ToggleSplit();
            }
            return;
        }
        base.WndProc(ref m);
    }

    void FocusPane(Pane p)
    {
        if (p == right && split.Panel2Collapsed) ToggleSplit();
        active = p; W.SetForegroundWindow(p.Hwnd); WriteState();
    }
    void ToggleSplit()
    {
        split.Panel2Collapsed = !split.Panel2Collapsed;
        if (split.Panel2Collapsed && active == right) active = left;
        left.Fit(); right.Fit(); W.SetForegroundWindow(active.Hwnd); WriteState();
    }

    List<TabRef> AllTabs()
    {
        var r = new List<TabRef>();
        foreach (var p in new[] { left, right })
        {
            if (!W.IsWindow(p.Hwnd)) continue;
            var names = W.TabNames(p.Hwnd);
            for (int i = 0; i < names.Count; i++) r.Add(new TabRef { Win = p.Hwnd, Title = names[i], Index = i, PaneName = p.Name });
        }
        return r;
    }
    int RecentRank(TabRef t)
    {
        int i = recent.FindIndex(x => x.Win == t.Win && x.Title == t.Title);
        return i < 0 ? int.MaxValue : i;
    }
    void SearchTabs()
    {
        if (palette != null) { palette.Activate(); return; }
        var tabs = AllTabs().OrderBy(RecentRank).ToList();
        using (palette = new Palette(tabs))
        {
            palette.Shown += (s, e) => { SyncKeys(); W.SetForegroundWindow(palette.Handle); };
            palette.ShowDialog(this);
            var pick = palette.Picked; palette = null;
            if (pick != null) GoTo(pick.Win, pick.Title, pick.Index); else W.SetForegroundWindow(active.Hwnd);
        }
    }
    void GoTo(IntPtr win, string title, int hint)
    {
        var names = W.TabNames(win);
        int idx = hint < names.Count && names[hint] == title ? hint : names.IndexOf(title);
        if (idx < 0) return;
        Pane p = win == left.Hwnd ? left : right;
        if (p == right && split.Panel2Collapsed) ToggleSplit();
        active = p; W.SetForegroundWindow(win); W.SelectTab(win, idx); NoteCurrent(); WriteState();
    }
    void RecentTab()
    {
        NoteCurrent();
        foreach (var t in recent.Skip(1).ToList())
        {
            if (W.IsWindow(t.Win) && W.TabNames(t.Win).Contains(t.Title)) { GoTo(t.Win, t.Title, t.Index); return; }
            recent.Remove(t);
        }
    }
    void NoteCurrent()
    {
        if (!W.IsWindow(active.Hwnd)) return;
        var names = W.TabNames(active.Hwnd); int c = W.CurTab(active.Hwnd);
        if (c < 0 || c >= names.Count) return;
        recent.RemoveAll(x => x.Win == active.Hwnd && x.Title == names[c]);
        recent.Insert(0, new TabRef { Win = active.Hwnd, Title = names[c], Index = c, PaneName = active.Name });
        if (recent.Count > MaxRecent) recent.RemoveRange(MaxRecent, recent.Count - MaxRecent);
    }
    void WriteState()
    {
        if (string.IsNullOrEmpty(statePath)) return;
        var b = new StringBuilder();
        b.AppendLine("active=" + active.Name); b.AppendLine("collapsed=" + split.Panel2Collapsed);
        foreach (var p in new[] { left, right })
        {
            int c = W.CurTab(p.Hwnd); var n = W.TabNames(p.Hwnd);
            b.AppendLine(p.Name + "_hwnd=" + p.Hwnd.ToInt64()); b.AppendLine(p.Name + "_cur=" + (c >= 0 && c < n.Count ? n[c] : ""));
            b.AppendLine(p.Name + "_tabs=" + string.Join(" | ", n));
        }
        b.AppendLine("recent=" + string.Join(" | ", recent.Select(x => x.PaneName + ":" + x.Title)));
        try { File.WriteAllText(statePath + ".tmp", b.ToString()); File.Copy(statePath + ".tmp", statePath, true); } catch { }
    }
    void Release()
    {
        settle.Stop();
        if (fgHook != IntPtr.Zero) W.UnhookWinEvent(fgHook);
        if (selHook != IntPtr.Zero) W.UnhookWinEvent(selHook);
        if (keysOn) for (int i = 1; i <= 4; i++) W.UnregisterHotKey(Handle, i);
        foreach (var p in new[] { left, right })
        {
            if (p.Hwnd == IntPtr.Zero || !W.IsWindow(p.Hwnd)) continue;
            W.ShowWindow(p.Hwnd, 0); W.SetParent(p.Hwnd, IntPtr.Zero); W.SetLong(p.Hwnd, GWL_STYLE, p.OldStyle);
            W.PostMessage(p.Hwnd, 0x10, IntPtr.Zero, IntPtr.Zero);
        }
    }
}

static class Program
{
    [STAThread]
    static void Main(string[] a)
    {
        string exe = a.Length > 0 ? a[0] : @"C:\Program Files\Everything 1.5a\Everything64.exe";
        string state = a.Length > 1 ? a[1] : null;
        Application.EnableVisualStyles();
        Application.Run(new Host(exe, state));
    }
}
