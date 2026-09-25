using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class PwaRedirect {
    [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern IntPtr CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr ptr);
    private static bool RoundTrip(string value) {
        int count;
        IntPtr argv = CommandLineToArgvW("test.exe " + Quote(value), out count);
        if (argv == IntPtr.Zero) return false;
        try { return count == 2 && Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, IntPtr.Size)) == value; }
        finally { LocalFree(argv); }
    }
    public static string BrowserInput(string url) {
        Uri uri = new Uri(url);
        bool bing = uri.Host.Equals("bing.com", StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith(".bing.com", StringComparison.OrdinalIgnoreCase);
        if (bing && uri.AbsolutePath.TrimEnd('/').Equals("/search", StringComparison.OrdinalIgnoreCase)) {
            foreach (string part in uri.Query.TrimStart('?').Split('&')) {
                int eq = part.IndexOf('=');
                if (eq < 0) continue;
                string name = Uri.UnescapeDataString(part.Substring(0, eq).Replace("+", " "));
                if (!name.Equals("q", StringComparison.OrdinalIgnoreCase)) continue;
                string query = Uri.UnescapeDataString(part.Substring(eq + 1).Replace("+", " "));
                if (!String.IsNullOrWhiteSpace(query) && query.IndexOf('\0') < 0) return "? " + query;
            }
        }
        return url;
    }
    public static string Quote(string value) {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); }
            else { result.Append('\\', slashes); result.Append(c); }
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        result.Append('"');
        return result.ToString();
    }
    public static string Extract(string[] args) {
        foreach (string arg in args) {
            string s = arg;
            if (s.StartsWith("microsoft-edge:", StringComparison.OrdinalIgnoreCase)) s = s.Substring(15);
            Uri uri;
            if (Uri.TryCreate(s, UriKind.Absolute, out uri) && (uri.Scheme == "https" || uri.Scheme == "http")) return uri.AbsoluteUri;
        }
        return null;
    }
    [STAThread] public static int Main(string[] args) {
        if (args.Length == 1 && args[0] == "--self-test") {
            if (Extract(new string[]{"pwahelper.exe", "--launch-edge-store-page", "--single-argument", "microsoft-edge:https://www.google.com/search?q=a%26b"}) != "https://www.google.com/search?q=a%26b") return 10;
            if (Extract(new string[]{"--single-argument", "https://example.com/?a=1&b=2"}) != "https://example.com/?a=1&b=2") return 11;
            if (Extract(new string[]{"microsoft-edge:file:///C:/Windows/notepad.exe"}) != null) return 12;
            if (Extract(new string[]{"--launch-edge-store-page"}) != null) return 13;
            if (BrowserInput("https://www.bing.com/search?q=%E4%B8%AD%E6%96%87+a%2Bb%26c&form=test") != "? \u4e2d\u6587 a+b&c") return 14;
            if (BrowserInput("https://bing.com.evil.example/search?q=test") != "https://bing.com.evil.example/search?q=test") return 15;
            if (BrowserInput("https://www.bing.com/images/search?q=test") != "https://www.bing.com/images/search?q=test") return 16;
            if (BrowserInput("https://www.bing.com/search?form=test") != "https://www.bing.com/search?form=test") return 17;
            if (Quote("a\"b\\") != "\"a\\\"b\\\\\"") return 18;
            if (BrowserInput("https://cn.bing.com/search?q=--incognito") != "? --incognito") return 19;
            foreach (string sample in new string[]{"", "a b", "\u4e2d\u6587", "a\"b", "a\\", "a\\\"b", "? --incognito", "? a&b|c%PATH%", "line\nbreak"}) {
                if (!RoundTrip(sample)) return 20;
            }
            return 0;
        }
        string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ClickToDoPwaRedirect");
        Action<string> log = delegate(string status) {
            try {
                Directory.CreateDirectory(logDir);
                string path = Path.Combine(logDir,"status.log");
                if (File.Exists(path) && new FileInfo(path).Length > 262144) File.WriteAllText(path, "");
                File.AppendAllText(path, DateTime.Now.ToString("O") + " " + status + Environment.NewLine);
            } catch { }
        };
        log("invoked");
        string url = Extract(args);
        if (url == null) { log("no-supported-url"); MessageBox.Show("No HTTP/HTTPS URL found. This redirect only supports web links. Remove it using option 2 if it interferes with other Edge helper operations.", "Click to Do redirect"); return 2; }
        try {
            string chrome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google\\Chrome\\Application\\chrome.exe");
            if (!File.Exists(chrome)) chrome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google\\Chrome\\Application\\chrome.exe");
            if (!File.Exists(chrome)) throw new FileNotFoundException("Chrome was not found in Program Files.");
            string input = BrowserInput(url);
            Process.Start(new ProcessStartInfo(chrome, Quote(input)) {UseShellExecute=false});
            log(input.StartsWith("? ") ? "chrome-default-search-requested" : "chrome-url-launch-requested");
            return 0;
        } catch (Exception e) { log("launch-failed"); MessageBox.Show(e.Message,"Click to Do redirect"); return 3; }
    }
}
