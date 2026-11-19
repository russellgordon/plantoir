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

    /// <summary>
    /// The pattern rules, in exactly the order
    /// <c>problemReportRedaction.ruleOrder.order</c> names (#853, #876; Windows
    /// #941). The order decides what is left when two rules match the same
    /// text, and the contract pins it by name and by behaviour, so it is not
    /// to be changed here without the contract. The patterns are the mac's,
    /// written as C# verbatim strings.
    /// </summary>
    public static readonly IReadOnlyList<RedactionRule> PatternRules = new List<RedactionRule>
    {
        // A username and password written into an address (#709), any scheme
        // (#853): first, because the email rule would otherwise take the
        // password and the host for an address and leave the username behind.
        new("urlUserinfo", @"(?i)(?<![a-z0-9+.\-])([a-z][a-z0-9+.\-]*://)[^/\s:@\[\]?#]+:(?:(?=\d)[^\s@]+|(?!\d)[^\s@]+(?: [^\s:@]+)*)@", "$1" + RemovedToken + "@"),
        // A home folder, two-word names included (#876), before labelledSecret,
        // which would otherwise take `/Users/First` as a token and leave `Last`.
        new("macHomeFolder", @"(?im)(/Users/)(?:(?:[^/\s""':]|'(?=\p{L}))+(?: (?!-|[^/\s""':]*(?:token|secret|password|api[_\-]?key)\s*[=:]|[^/\s""':]*(?:bearer|authorization|account)(?![a-z]))(?:[^/\s""':]|'(?=\p{L}))+)*(?=[/""'\r]|:(?:\s|$)|$)|(?:[^/\s""':]|'(?=\p{L}))+)", "$1" + RemovedPersonPath),
        // The same on Windows, with doubled backslashes as Python prints them and
        // a carriage return ending the name (#853 round 2).
        new("windowsHomeFolder", @"(?im)([A-Z]:\\{1,2}Users\\{1,2})(?:(?:[^\\\s""':]|'(?=\p{L}))+(?: (?!-|[^\\\s""':]*(?:token|secret|password|api[_\-]?key)\s*[=:]|[^\\\s""':]*(?:bearer|authorization|account)(?![a-z]))(?:[^\\\s""':]|'(?=\p{L}))+)*(?=[\\/""'\r]|:(?:\s|$)|$)|(?:[^\\\s""':]|'(?=\p{L}))+)", "$1" + RemovedPersonPath),
        // A Basic Authorization header (#709), in a header line, JSON or a
        // Python dict (#853). Anchored on the header's own name, so "Basic
        // French" in a course title is left alone (the mac's review L4).
        new("basicAuthHeader", @"(?i)(\bAuthorization[""']?\s*[:=]\s*[""']?\s*Basic\s+)(?!\[removed: )(?!Bearer\s+\S|Basic\s+\S|[""']?Authorization[""']?\s*[:=]|\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s+\S|--account[=\s]\s*(?:[A-Za-z0-9]{16}|\[removed: account id\])|account\s*id\s*[:=]?\s*(?:[A-Za-z0-9]{16}|\[removed: account id\]))\S+", "$1" + RemovedToken),
        new("bearerHeader", @"(?i)\bBearer\s+(?!\[removed: )(?!Bearer\s+\S|Basic\s+\S|[""']?Authorization[""']?\s*[:=]|\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s+\S|--account[=\s]\s*(?:[A-Za-z0-9]{16}|\[removed: account id\])|account\s*id\s*[:=]?\s*(?:[A-Za-z0-9]{16}|\[removed: account id\]))\S+", "Bearer " + RemovedToken),
        new("labelledSecret", @"(?i)\b(\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s*)(?>(?:Basic\s+)*)(?!\[removed: )(?!Bearer\s+\S|[""']?Authorization[""']?\s*[:=]|\w*(?:token|secret|password|api[_\-]?key)\s*[=:]\s+\S|--account[=\s]\s*(?:[A-Za-z0-9]{16}|\[removed: account id\])|account\s*id\s*[:=]?\s*(?:[A-Za-z0-9]{16}|\[removed: account id\]))\S+", "$1" + RemovedToken),
        new("netlifyToken", @"\bnfp_[A-Za-z0-9]{8,}", RemovedToken),
        new("accountFlag", @"(?i)(--account[=\s]\s*)[A-Za-z0-9]{16,}", "$1" + RemovedAccount),
        new("accountIdentifier", @"(?i)(account\s*id\s*[:=]?\s*)[A-Za-z0-9]{16,}", "$1" + RemovedAccount),
        // #739: wrangler's "A request to the Cloudflare API (/accounts/<id>/pages/...) failed."
        new("accountPath", @"(?i)(/accounts/)[A-Za-z0-9]{16,}", "$1" + RemovedAccount),
        // curl's `-u name:password` and `--user name:password` (#853).
        new("userFlag", @"(?<![\w\-])((?>-[A-Za-z]*?u)[ \t]*|--user(?:=|[ \t]+))(?!\[removed: [a-z ]+\](?:\s|$))(?:'[^':\n]*:[^'\n]*'|""[^"":\n]*:[^""\n]*""|(?:\[removed: [a-z ]+\]|[^\s:'""])+:(?:\[removed: [a-z ]+\]|\S)+)", "$1" + RemovedToken),
        // Last, so an address left by the rules above is still taken.
        new("emailAddress", @"(?:(?<!://)\[removed: (?:token|account id)\]|(?<![A-Za-z0-9._%+\-])[A-Za-z0-9._%+\-]+)@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", RemovedEmail),
    };

    /// <summary>The text as it may be written to a report.</summary>
    public static string Redacting(string text)
    {
        return Redacting(text, PatternRules);
    }

    /// <summary>
    /// The text with these pattern rules applied in this order, then the
    /// 40-character run. The app always passes <see cref="PatternRules"/>; a
    /// test passes the same rules in another order, to show that a
    /// <c>problemReportRedaction.ruleOrder</c> case depends on the order
    /// (the mac's <c>redacting(_:applyingInOrder:)</c>).
    /// </summary>
    public static string Redacting(string text, IReadOnlyList<RedactionRule> rulesInOrder)
    {
        if (string.IsNullOrEmpty(text)) return text;
        string result = text;
        foreach (var rule in rulesInOrder)
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
