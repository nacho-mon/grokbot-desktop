// gbd: fast client for Grok Bot Desktop. Same protocol and token handling as grokbot-desktop.ps1,
// without starting PowerShell. Talks only to http://127.0.0.1:<port>. Never prints the token.
// Build (no admin): %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /optimize+ /out:gbd.exe client\gbd.cs
// C# 5 only (the csc that ships with .NET Framework 4.x).
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;

static class Gbd
{
    const string Version = "1.2.6";

    const string Usage =
"gbd " + Version + " - fast client for Grok Bot Desktop (127.0.0.1 only, token and tray kill switch)\n" +
"\n" +
"Usage:\n" +
"  gbd status\n" +
"  gbd open <app|url|uri> [--wait <title>] [--args \"<arguments>\"] [--timeout ms]\n" +
"  gbd screenshot [--full] [--monitor all|N | --window active | --hwnd <id>] [--max-width N] [--format png|jpg] [--quality 1-100]\n" +
"  gbd type <text> [--gap ms] [--paste]\n" +
"  gbd key <combo>\n" +
"  gbd click <x> <y> [--button left|right|middle] [--double] [--space screen|image]\n" +
"  gbd move <x> <y> [--space screen|image]\n" +
"  gbd scroll <dy> [--x N] [--y N]\n" +
"  gbd focus <title> | --hwnd <id>\n" +
"  gbd foreground | windows\n" +
"  gbd wait --title <text> [--timeout ms] [--foreground] [--gone]\n" +
"  gbd launch <program> [--args \"<arguments>\"] [--wait-title <text>] [--timeout ms]\n" +
"  gbd batch <json> | --b64 <base64> | --file <steps.json> | -   [--delay ms]\n" +
"  gbd selftest\n" +
"  gbd version | help\n" +
"\n" +
"screenshot: light by default (active window, JPG 60, max 1280 px). --full = all monitors, PNG, real size.\n" +
"open: opens, brings to the front and returns title and hwnd, no screenshot. URLs (https://... or x.com) go to Chrome = new tab.\n" +
"chrome://, edge://, about: go to the browser (verified Ctrl+T, then the URL). Shortcuts matched by process, not title.\n" +
"type: Unicode per character, 8 ms apart (--gap 0-50); --paste = clipboard + Ctrl+V, clipboard text restored. Stops with focus_changed.\n" +
"batch: stepDelayMs 0 by default (--delay N to change it); '-' reads the JSON from stdin (UTF-8).\n" +
"From Windows PowerShell 5.1, --b64 or --file avoid quoting problems. The kill switch is checked between steps.\n" +
"selftest: Chrome on x.com, Calculator 2+2=, a new Notepad note with a welcome text; pass/fail per step.\n" +
"There is no on/off here: use Turn on / Turn off in the tray icon.";

    class Req
    {
        public string Route;
        public string Method = "POST";
        public string Json;
        public int TimeoutMs = 30000;
    }

    static int Main(string[] argv)
    {
        try { return Run(argv); }
        catch (Exception)
        {
            return Fail("client_error", "Unexpected error in gbd.", 1);
        }
    }

    static int Run(string[] argv)
    {
        if (argv.Length == 0) { WriteText(Usage); return 0; }
        string cmd = argv[0].ToLowerInvariant();
        List<string> a = new List<string>(argv);
        a.RemoveAt(0);

        if (cmd == "help" || cmd == "--help" || cmd == "-h" || cmd == "/?") { WriteText(Usage); return 0; }
        if (cmd == "version" || cmd == "--version") { WriteLine("{\"ok\":true,\"client\":\"gbd\",\"version\":\"" + Version + "\"}"); return 0; }
        if (cmd == "on" || cmd == "off")
            return Fail("kill_switch_ui_only", "Control cannot be turned on or off from the CLI. Use Turn on or Turn off in the tray icon menu.", 1);

        Req req;
        try { req = Parse(cmd, a); }
        catch (UsageException e) { return Fail(e.Code, e.Message, 2); }
        if (req == null) return Fail("usage", "Unknown command. See gbd help.", 2);
        return Send(req);
    }

    class UsageException : Exception
    {
        public string Code;
        public UsageException(string message) : base(message) { Code = "usage"; }
        public UsageException(string code, string message) : base(message) { Code = code; }
    }

    static UsageException Bad() { return new UsageException("Missing or invalid argument. See gbd help."); }

    static Req Parse(string cmd, List<string> a)
    {
        Req r = new Req();
        JsonObj b = new JsonObj();
        switch (cmd)
        {
            case "status": r.Route = "/status"; r.Method = "GET"; return r;
            case "windows": r.Route = "/windows"; r.Method = "GET"; return r;
            case "foreground": r.Route = "/foreground"; r.Method = "GET"; return r;
            case "screenshot":
                for (int i = 0; i < a.Count; i++)
                {
                    string k = a[i];
                    if (k == "--full") b.Bool("full", true);
                    else if (k == "--monitor" && i + 1 < a.Count) b.Str("monitor", a[++i]);
                    else if (k == "--window" && i + 1 < a.Count) b.Str("window", a[++i].ToLowerInvariant());
                    else if (k == "--hwnd" && i + 1 < a.Count) b.Raw("hwnd", Num(a[++i]));
                    else if (k == "--max-width" && i + 1 < a.Count) b.Raw("maxWidth", Num(a[++i]));
                    else if (k == "--format" && i + 1 < a.Count) b.Str("format", a[++i].ToLowerInvariant());
                    else if (k == "--quality" && i + 1 < a.Count) b.Raw("quality", Num(a[++i]));
                    else throw Bad();
                }
                r.Route = "/screenshot"; r.Json = b.ToString(); return r;
            case "open":
            case "launch":
            {
                List<string> words = new List<string>();
                int wait = 10000;
                for (int i = 0; i < a.Count; i++)
                {
                    string k = a[i];
                    if (k == "--args" && i + 1 < a.Count) b.Str("args", a[++i].Trim());
                    else if ((k == "--wait" || k == "--wait-title") && i + 1 < a.Count) b.Str("waitTitle", a[++i]);
                    else if (k == "--timeout" && i + 1 < a.Count) { wait = int.Parse(Num(a[++i])); b.Raw("timeoutMs", wait.ToString()); }
                    else if (k.StartsWith("--")) throw Bad();
                    else words.Add(k);
                }
                if (words.Count == 0) throw Bad();
                b.Str(cmd == "open" ? "target" : "path", string.Join(" ", words.ToArray()));
                r.Route = "/" + cmd; r.Json = b.ToString(); r.TimeoutMs = wait + 15000; return r;
            }
            case "focus":
            {
                int idx = a.IndexOf("--hwnd");
                if (idx >= 0 && idx + 1 < a.Count) b.Raw("hwnd", Num(a[idx + 1]));
                else if (a.Count > 0) b.Str("title", string.Join(" ", a.ToArray()));
                else throw Bad();
                r.Route = "/focus"; r.Json = b.ToString(); return r;
            }
            case "key":
                if (a.Count == 0) throw Bad();
                b.Str("combo", string.Join(" ", a.ToArray()));
                r.Route = "/key"; r.Json = b.ToString(); return r;
            case "type":
            {
                int pi = a.IndexOf("--paste");
                if (pi >= 0) { b.Bool("paste", true); a.RemoveAt(pi); }
                int gi = a.IndexOf("--gap");
                if (gi >= 0)
                {
                    if (gi + 1 >= a.Count) throw Bad();
                    b.Raw("gapMs", Num(a[gi + 1]));
                    a.RemoveRange(gi, 2);
                }
                if (a.Count == 0) throw Bad();
                b.Str("text", string.Join(" ", a.ToArray()));
            }
                r.Route = "/type"; r.Json = b.ToString(); r.TimeoutMs = 120000; return r;
            case "click":
            case "move":
                if (a.Count < 2) throw Bad();
                b.Raw("x", Num(a[0])); b.Raw("y", Num(a[1]));
                for (int i = 2; i < a.Count; i++)
                {
                    string k = a[i];
                    if (k == "--space" && i + 1 < a.Count) b.Str("space", a[++i]);
                    else if (cmd == "click" && k == "--button" && i + 1 < a.Count) b.Str("button", a[++i]);
                    else if (cmd == "click" && k == "--double") b.Bool("double", true);
                    else throw Bad();
                }
                r.Route = "/" + cmd; r.Json = b.ToString(); return r;
            case "scroll":
                if (a.Count < 1) throw Bad();
                b.Raw("dy", Num(a[0]));
                for (int i = 1; i < a.Count; i++)
                {
                    if (a[i] == "--x" && i + 1 < a.Count) b.Raw("x", Num(a[++i]));
                    else if (a[i] == "--y" && i + 1 < a.Count) b.Raw("y", Num(a[++i]));
                    else throw Bad();
                }
                r.Route = "/scroll"; r.Json = b.ToString(); return r;
            case "wait":
            {
                int wait = 5000;
                List<string> words = new List<string>();
                for (int i = 0; i < a.Count; i++)
                {
                    string k = a[i];
                    if (k == "--title" && i + 1 < a.Count) b.Str("title", a[++i]);
                    else if (k == "--timeout" && i + 1 < a.Count) { wait = int.Parse(Num(a[++i])); b.Raw("timeoutMs", wait.ToString()); }
                    else if (k == "--foreground") b.Bool("foreground", true);
                    else if (k == "--gone") b.Bool("gone", true);
                    else if (k.StartsWith("--")) throw Bad();
                    else words.Add(k);
                }
                if (!b.Has("title"))
                {
                    if (words.Count == 0) throw Bad();
                    b.Str("title", string.Join(" ", words.ToArray()));
                }
                r.Route = "/wait"; r.Json = b.ToString(); r.TimeoutMs = wait + 15000; return r;
            }
            case "selftest":
                r.Route = "/selftest"; r.Json = "{}"; r.TimeoutMs = 130000; return r;
            case "batch":
                r.Route = "/batch"; r.TimeoutMs = 200000; r.Json = BatchJson(a); return r;
        }
        return null;
    }

    static string Num(string s)
    {
        long n;
        if (!long.TryParse(s, out n)) throw Bad();
        return n.ToString();
    }

    // Accepts inline JSON, --b64, --file or '-' (stdin). Adds stepDelayMs 0 unless given.
    static string BatchJson(List<string> a)
    {
        int delay = 0;
        int di = a.IndexOf("--delay");
        if (di >= 0)
        {
            if (di + 1 >= a.Count) throw Bad();
            delay = int.Parse(Num(a[di + 1]));
            a.RemoveRange(di, 2);
        }
        if (a.Count == 0) throw Bad();
        string json;
        if (a[0] == "--file")
        {
            if (a.Count != 2) throw Bad();
            try { json = File.ReadAllText(a[1], Encoding.UTF8); }
            catch (Exception) { throw new UsageException("invalid_args", "Could not read the steps file."); }
        }
        else if (a[0] == "--b64")
        {
            if (a.Count != 2) throw Bad();
            try { json = Encoding.UTF8.GetString(Convert.FromBase64String(a[1])); }
            catch (Exception) { throw new UsageException("invalid_args", "The steps base64 is invalid."); }
        }
        else if (a[0] == "-" && a.Count == 1)
        {
            using (Stream s = Console.OpenStandardInput())
            using (StreamReader sr = new StreamReader(s, new UTF8Encoding(false)))
                json = sr.ReadToEnd();
        }
        else
        {
            json = string.Join(" ", a.ToArray());
            if (json.IndexOf('"') < 0)
            {
                // Windows PowerShell 5.1 drops embedded double quotes when it calls an exe.
                // The raw command line still has them: take everything after the batch verb.
                string raw = RawTailAfterVerb();
                if (raw != null && raw.IndexOf('"') >= 0) json = raw;
            }
        }
        json = json.Trim('\uFEFF', ' ', '\t', '\r', '\n');
        if (json.StartsWith("[")) return "{\"stepDelayMs\":" + delay + ",\"steps\":" + json + "}";
        if (json.StartsWith("{") && json.IndexOf("\"stepDelayMs\"", StringComparison.Ordinal) < 0 && json.IndexOf("\"steps\"", StringComparison.Ordinal) >= 0)
            return "{\"stepDelayMs\":" + delay + "," + json.Substring(1);
        return json;
    }

    static string RawTailAfterVerb()
    {
        string line = Environment.CommandLine;
        int i = 0;
        // Skip the program token (quoted or not), then the verb.
        for (int t = 0; t < 2; t++)
        {
            while (i < line.Length && char.IsWhiteSpace(line[i])) i++;
            if (i < line.Length && line[i] == '"')
            {
                int j = line.IndexOf('"', i + 1);
                i = j < 0 ? line.Length : j + 1;
            }
            else
            {
                while (i < line.Length && !char.IsWhiteSpace(line[i])) i++;
            }
        }
        string rest = line.Substring(Math.Min(i, line.Length)).Trim();
        int d = rest.IndexOf(" --delay ", StringComparison.Ordinal);
        if (d >= 0) rest = rest.Substring(0, d).Trim();
        if (rest.Length >= 2 && rest[0] == '"' && (rest[1] == '[' || rest[1] == '{') && rest[rest.Length - 1] == '"')
            rest = rest.Substring(1, rest.Length - 2);
        return rest.Length == 0 ? null : rest;
    }

    static string HomePath()
    {
        string h = Environment.GetEnvironmentVariable("DESKCTL_HOME");
        if (string.IsNullOrEmpty(h)) h = Environment.GetEnvironmentVariable("GROKBOT_DESKTOP_HOME");
        if (!string.IsNullOrEmpty(h)) return Path.GetFullPath(h);
        string lad = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        if (!string.IsNullOrEmpty(lad)) return Path.Combine(lad, "GrokBotDesktop");
        string xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        if (string.IsNullOrEmpty(xdg)) xdg = Path.Combine(Environment.GetEnvironmentVariable("HOME") ?? ".", ".config");
        return Path.Combine(xdg, "GrokBotDesktop");
    }

    static int Send(Req r)
    {
        string home = HomePath();
        string token = Environment.GetEnvironmentVariable("DESKCTL_TOKEN");
        if (string.IsNullOrEmpty(token))
        {
            string tf = Environment.GetEnvironmentVariable("DESKCTL_TOKEN_FILE");
            if (string.IsNullOrEmpty(tf)) tf = Path.Combine(home, "token");
            if (!File.Exists(tf)) return Fail("no_token", "Grok Bot Desktop cannot find its token. Run scripts\\install.ps1.", 1);
            token = File.ReadAllText(tf).Trim();
        }
        string pf = Path.Combine(home, "port");
        int port;
        if (!File.Exists(pf) || !int.TryParse(File.ReadAllText(pf).Trim(), out port) || port < 1 || port > 65535)
            return Fail("bridge_unavailable", "Grok Bot Desktop is not running. Run scripts\\start.ps1.", 1);

        string envTimeout = Environment.GetEnvironmentVariable("DESKCTL_TIMEOUT_MS");
        int timeout = r.TimeoutMs;
        int et;
        if (!string.IsNullOrEmpty(envTimeout) && int.TryParse(envTimeout, out et)) timeout = et;

        try
        {
            ServicePointManager.Expect100Continue = false;
            ServicePointManager.UseNagleAlgorithm = false;
            // Loopback only: the address is fixed, there is no URL override.
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:" + port + r.Route);
            req.Proxy = null;
            req.KeepAlive = false;
            req.Method = r.Method;
            req.Timeout = timeout;
            req.ReadWriteTimeout = timeout;
            req.Headers.Add("X-Deskctl-Token", token);
            req.Headers.Add("Authorization", "Bearer " + token);
            if (r.Method == "POST")
            {
                byte[] bytes = new UTF8Encoding(false).GetBytes(r.Json ?? "{}");
                req.ContentType = "application/json; charset=utf-8";
                req.ContentLength = bytes.Length;
                using (Stream rs = req.GetRequestStream()) rs.Write(bytes, 0, bytes.Length);
            }
            HttpWebResponse resp;
            try { resp = (HttpWebResponse)req.GetResponse(); }
            catch (WebException we)
            {
                resp = we.Response as HttpWebResponse;
                if (resp == null) throw;
            }
            byte[] body;
            using (resp)
            using (Stream s = resp.GetResponseStream())
            using (MemoryStream ms = new MemoryStream())
            {
                s.CopyTo(ms);
                body = ms.ToArray();
            }
            string text = Encoding.UTF8.GetString(body).Trim();
            WriteLine(text);
            return System.Text.RegularExpressions.Regex.IsMatch(text, "^\\{\\s*\"ok\"\\s*:\\s*true") ? 0 : 1;
        }
        catch (Exception)
        {
            return Fail("bridge_unavailable", "Could not connect to Grok Bot Desktop. Is it running?", 1);
        }
    }

    static int Fail(string code, string message, int exit)
    {
        WriteLine("{\"ok\":false,\"error\":" + JsonObj.Q(code) + ",\"message\":" + JsonObj.Q(message) + "}");
        return exit;
    }

    static void WriteLine(string s) { WriteText(s); }

    static void WriteText(string s)
    {
        byte[] b = new UTF8Encoding(false).GetBytes(s + "\n");
        using (Stream o = Console.OpenStandardOutput()) o.Write(b, 0, b.Length);
    }

    class JsonObj
    {
        readonly List<string> parts = new List<string>();
        readonly HashSet<string> keys = new HashSet<string>();
        public bool Has(string k) { return keys.Contains(k); }
        public void Str(string k, string v) { Raw(k, Q(v)); }
        public void Bool(string k, bool v) { Raw(k, v ? "true" : "false"); }
        public void Raw(string k, string v) { keys.Add(k); parts.Add(Q(k) + ":" + v); }
        public override string ToString() { return "{" + string.Join(",", parts.ToArray()) + "}"; }
        public static string Q(string s)
        {
            StringBuilder sb = new StringBuilder("\"");
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            return sb.Append('"').ToString();
        }
    }
}
