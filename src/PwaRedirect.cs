// Forwarding pipeline: IFEO arguments -> first HTTP(S) URL -> optional Bing query
// conversion -> one quoted Chrome argument. This program runs only on demand;
// it does not watch processes, change browser preferences, or run as a service.
// Keep this source ASCII: Build.ps1 embeds it in the distributable BAT. Use C#
// Unicode escapes for non-ASCII test data rather than changing the BAT encoding.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class PwaRedirect {
    // These Win32 imports are used only by the quoting self-test. Windows passes
    // a command-line string to a child process, so test with a real Windows parser
    // instead of assuming that placing quotes around text preserves argv.
    [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern IntPtr CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr ptr);
    /// <summary>
    /// Check that Quote produces exactly one argument with the original value.
    /// The dummy executable occupies argv[0]; our input must occupy argv[1].
    /// </summary>
    private static bool RoundTrip(string value) {
        int count;
        IntPtr argv = CommandLineToArgvW("test.exe " + Quote(value), out count);
        if (argv == IntPtr.Zero) return false;
        try { return count == 2 && Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, IntPtr.Size)) == value; }
        // CommandLineToArgvW allocates unmanaged memory owned by this caller.
        finally { LocalFree(argv); }
    }
    /// <summary>
    /// Convert a supported Bing web-search URL into Chrome's "? search terms"
    /// syntax. The caller supplies an absolute HTTP(S) URL from Extract.
    /// Return the original URL for everything else, including image searches.
    /// Chrome, not this program, selects the profile and its default engine.
    /// </summary>
    public static string BrowserInput(string url) {
        Uri uri = new Uri(url);
        // The leading dot in the suffix is a hostname boundary: accept
        // cn.bing.com, but never bing.com.evil.example or notbing.com.
        bool bing = uri.Host.Equals("bing.com", StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith(".bing.com", StringComparison.OrdinalIgnoreCase);
        if (bing && uri.AbsolutePath.TrimEnd('/').Equals("/search", StringComparison.OrdinalIgnoreCase)) {
            // Split before decoding so an encoded ampersand (%26) stays inside
            // the search term. Split each pair on its first '=' for the same reason.
            foreach (string part in uri.Query.TrimStart('?').Split('&')) {
                int eq = part.IndexOf('=');
                if (eq < 0) continue;
                // Form-style query strings use '+' for space; decode %2B only
                // afterward so a literal encoded plus sign remains a plus sign.
                string name = Uri.UnescapeDataString(part.Substring(0, eq).Replace("+", " "));
                if (!name.Equals("q", StringComparison.OrdinalIgnoreCase)) continue;
                string query = Uri.UnescapeDataString(part.Substring(eq + 1).Replace("+", " "));
                // A NUL cannot be represented in a Windows process command line.
                // Prefixing with '? ' also keeps query text such as --incognito
                // in search mode rather than presenting it as a Chrome switch.
                if (!String.IsNullOrWhiteSpace(query) && query.IndexOf('\0') < 0) return "? " + query;
            }
        }
        // Missing/empty q or a different endpoint is still a valid web link.
        return url;
    }
    /// <summary>
    /// Encode one Windows argv value, including embedded quotes and backslashes.
    /// This is process-argument quoting, not cmd.exe/PowerShell escaping: no shell
    /// is used to launch Chrome. Always quote, including empty strings.
    /// </summary>
    public static string Quote(string value) {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        // Buffer a run of backslashes until its following character is known.
        // Before a literal quote, emit 2*n+1 backslashes; before ordinary text,
        // keep n backslashes unchanged. A final run must be doubled because it
        // immediately precedes the closing delimiter added below.
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
    /// <summary>
    /// Find the first absolute HTTP(S) URL in an IFEO launch command. IFEO adds
    /// the original executable path, and the helper contributes switches such as
    /// --launch-edge-store-page; none of those non-URL arguments go to Chrome.
    /// Return null for unsupported inputs, rather than executing a local path.
    /// </summary>
    public static string Extract(string[] args) {
        foreach (string arg in args) {
            string s = arg;
            // 15 is the length of "microsoft-edge:". Strip exactly one wrapper;
            // leave URL escaping intact until the search-query conversion stage.
            if (s.StartsWith("microsoft-edge:", StringComparison.OrdinalIgnoreCase)) s = s.Substring(15);
            Uri uri;
            if (Uri.TryCreate(s, UriKind.Absolute, out uri) && (uri.Scheme == "https" || uri.Scheme == "http")) return uri.AbsoluteUri;
        }
        return null;
    }
    // STA supports the Windows Forms error dialogs in this console-less EXE.
    // Runtime exit codes: 0 = launch requested, 2 = unsupported input, 3 = error.
    // Self-test exit codes 10-20 identify a failed check; no browser is opened.
    [STAThread] public static int Main(string[] args) {
        if (args.Length == 1 && args[0] == "--self-test") {
            // 10-13: helper prefixes, ordinary URLs, blocked file URLs, no URL.
            // 14-17: Unicode/form decoding, hostname boundary, unrelated endpoint,
            // and a missing query. 18-20: quoting and switch-like query text.
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
            // These values must each remain a single argument after Windows
            // parsing, even when they contain whitespace or shell metacharacters.
            foreach (string sample in new string[]{"", "a b", "\u4e2d\u6587", "a\"b", "a\\", "a\\\"b", "? --incognito", "? a&b|c%PATH%", "line\nbreak"}) {
                if (!RoundTrip(sample)) return 20;
            }
            return 0;
        }
        // Keep diagnostics per user. Never log arguments, URLs, or search terms.
        // Logging is best-effort: permissions or concurrent writes must not
        // prevent a browser launch. The size threshold is approximate, not a
        // synchronized rotation scheme shared across simultaneous invocations.
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
        // Do not relaunch the original helper here: the same IFEO filter would
        // intercept that launch again, causing a forwarding loop.
        if (url == null) { log("no-supported-url"); MessageBox.Show("No HTTP/HTTPS URL found. This redirect only supports web links. Remove it using option 2 if it interferes with other Edge helper operations.", "Click to Do redirect"); return 2; }
        try {
            // Match the installer's system-wide Chrome prerequisite. Avoid a
            // PATH lookup or a fallback to the microsoft-edge protocol.
            string chrome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google\\Chrome\\Application\\chrome.exe");
            if (!File.Exists(chrome)) chrome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google\\Chrome\\Application\\chrome.exe");
            if (!File.Exists(chrome)) throw new FileNotFoundException("Chrome was not found in Program Files.");
            string input = BrowserInput(url);
            // UseShellExecute=false starts Chrome directly. Quote protects the
            // one argument; cmd.exe is never involved, and no profile or engine
            // is forced. A successful Start only means the launch was requested,
            // not that the resulting page was loaded successfully.
            Process.Start(new ProcessStartInfo(chrome, Quote(input)) {UseShellExecute=false});
            log(input.StartsWith("? ") ? "chrome-default-search-requested" : "chrome-url-launch-requested");
            return 0;
        } catch (Exception e) { log("launch-failed"); MessageBox.Show(e.Message,"Click to Do redirect"); return 3; }
    }
}
