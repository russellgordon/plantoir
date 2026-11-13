using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;

namespace Plantoir.Core.Scripting;

public sealed record RedactionRule(string Name, string Pattern, string Replacement);

/// <summary>
/// Takes out of a line anything that names the teacher, or that would let
/// somebody else act as them, on the way IN to a problem report.
/// Matches contracts/shared-rules.json -> problemReportRedaction.
/// </summary>
public static class LogRedactor
{
    public const string RemovedToken = "[removed: token]";
    public const string RemovedEmail = "[removed: email address]";
    public const string RemovedAccount = "[removed: account id]";
    public const string RemovedPersonPath = "person";
    public const int SecretLength = 40;

    public static readonly IReadOnlyList<RedactionRule> PatternRules = new List<RedactionRule>
    {
        new("macHomeFolder", @"/Users/[^/\s""':]+", "/Users/" + RemovedPersonPath),
        new("windowsHomeFolder", @"([A-Za-z]:\\Users\\)[^\\\s""':]+", "$1" + RemovedPersonPath),
        // A username and password written into an address (#709; on Windows
        // since step 0 of v2.0.0): before the email rule, which would
        // otherwise take the password and the host for an address and leave
        // the username behind.
        new("urlUserinfo", @"(?i)(https?://)[^/\s:@]+:[^/\s@]+@", "$1" + RemovedToken + "@"),
        new("emailAddress", @"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", RemovedEmail),
        new("labelledSecret", @"(?i)\b(\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s*)\S+", "$1" + RemovedToken),
        new("bearerHeader", @"(?i)\bBearer\s+\S+", "Bearer " + RemovedToken),
        // A Basic Authorization header (#709): the base64 of a username and
        // password. Anchored on the header's own name, so "Basic French" in a
        // course title is left alone (the mac's review L4).
        new("basicAuthHeader", @"(?i)(\bAuthorization:\s*Basic\s+)\S+", "$1" + RemovedToken),
        new("netlifyToken", @"\bnfp_[A-Za-z0-9]{8,}", RemovedToken),
        new("accountFlag", @"(?i)(--account[=\s]\s*)[A-Za-z0-9]{16,}", "$1" + RemovedAccount),
        new("accountIdentifier", @"(?i)(account\s*id\s*[:=]?\s*)[A-Za-z0-9]{16,}", "$1" + RemovedAccount),
        // #739: wrangler's "A request to the Cloudflare API (/accounts/<id>/pages/…) failed."
        new("accountPath", @"(?i)(/accounts/)[A-Za-z0-9]{16,}", "$1" + RemovedAccount),
    };

    public static string Redacting(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        string result = text;
        foreach (var rule in PatternRules)
        {
            result = Regex.Replace(result, rule.Pattern, rule.Replacement);
        }
        result = RemovingLongSecrets(result);
        return result;
    }

    private static string RemovingLongSecrets(string text)
    {
        var sb = new StringBuilder();
        var run = new StringBuilder();

        foreach (char c in text)
        {
            if (IsTokenCharacter(c))
            {
                run.Append(c);
                continue;
            }

            sb.Append(Settled(run.ToString()));
            run.Clear();
            sb.Append(c);
        }

        sb.Append(Settled(run.ToString()));
        return sb.ToString();
    }

    private static string Settled(string run)
    {
        if (run.Length != SecretLength) return run;
        if (IsAllLowercaseHexadecimal(run)) return run;
        return RemovedToken;
    }

    private static bool IsTokenCharacter(char c)
    {
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) return true;
        if (c >= '0' && c <= '9') return true;
        return c == '_' || c == '-';
    }

    private static bool IsAllLowercaseHexadecimal(string run)
    {
        foreach (char c in run)
        {
            bool isDigit = c >= '0' && c <= '9';
            bool isHexLetter = c >= 'a' && c <= 'f';
            if (!isDigit && !isHexLetter) return false;
        }
        return true;
    }
}
