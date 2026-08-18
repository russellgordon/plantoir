using System;
using System.Collections.Generic;

namespace Plantoir.Core.Scripting;

public sealed record CredentialRequest(
    string Name,
    string Title,
    string Explanation,
    string FieldLabel,
    bool IsSecret,
    string LinkAddress,
    string LinkTitle,
    IReadOnlyList<string> Steps);

public static class CredentialRequests
{
    private static readonly string[] CloudflareAccountIDSteps =
    [
        "Open the Cloudflare dashboard linked below, and sign in if you are asked to.",
        "Choose “Workers & Pages” from the list on the left.",
        "Find “Account ID” on the right-hand side, and copy it.",
        "Paste it below. (It is also the long code in your browser's address bar, just after dash.cloudflare.com/.)"
    ];

    public static readonly CredentialRequest NetlifyToken = new(
        Name: "netlifyToken",
        Title: "Connect to Netlify",
        Explanation: "Netlify hosts this section's website for free, and it needs to know that the publishing is coming from you. " +
                     "It does that with an access token — a long code that acts like a password made just for this app. " +
                     "Creating one takes about a minute, and you will not be asked again: it is saved securely on this computer.",
        FieldLabel: "Netlify token",
        IsSecret: true,
        LinkAddress: "https://app.netlify.com/user/applications#personal-access-tokens",
        LinkTitle: "Open Netlify’s access tokens page",
        Steps:
        [
            "Open the Netlify page linked below, and sign in if you are asked to.",
            "Choose “New access token”.",
            "Describe it as something you will recognise later, such as “Class websites”.",
            "Change the expiry — it starts at 7 days. A token that expires stops your publishing working, with nothing on screen to say why, " +
            "so set a date after the end of your school year: next July is a safe choice. Choose “No expiration” instead if it is offered.",
            "Choose “Generate token”, then copy the long code Netlify shows you — it is only shown once.",
            "Paste it below."
        ]);

    public static readonly CredentialRequest CloudflareToken = new(
        Name: "cloudflareToken",
        Title: "Connect to Cloudflare",
        Explanation: "Cloudflare hosts this section's website for free, and it needs to know that the publishing is coming from you. " +
                     "It does that with an API token — a long code that acts like a password made just for this app. " +
                     "Creating one takes about two minutes, and you will not be asked again: it is saved securely on this computer.",
        FieldLabel: "Cloudflare token",
        IsSecret: true,
        LinkAddress: "https://dash.cloudflare.com/profile/api-tokens",
        LinkTitle: "Open Cloudflare’s API tokens page",
        Steps:
        [
            "Open the Cloudflare page linked below, and sign in if you are asked to.",
            "Choose “Create Token”, then “Create Custom Token”.",
            "Name it something you will recognise later, such as “Class websites”.",
            "Give it one permission, chosen from the three dropdowns: Account, then Cloudflare Pages, then Edit.",
            "Under “Account Resources”, choose “Include” and then your own account by name. A token that names no account cannot publish anything, " +
            "and what you get back if you skip this does not mention accounts at all.",
            "Under “TTL”, set the end date to after the end of your school year — next July is a safe choice — or leave it with no end date. " +
            "An expired token stops your publishing working, with nothing on screen to say why.",
            "Choose “Continue to summary”, then “Create Token”.",
            "Copy the long code Cloudflare shows you — it is only shown once — and paste it below."
        ]);

    public static readonly CredentialRequest CloudflareAccountID = new(
        Name: "cloudflareAccountID",
        Title: "One more thing from Cloudflare",
        Explanation: "The token you just made is allowed to publish, but not to look up which Cloudflare account it belongs to — " +
                     "so the account's ID is needed as well. This is the only time you will be asked for it.",
        FieldLabel: "Account ID",
        IsSecret: false,
        LinkAddress: "https://dash.cloudflare.com",
        LinkTitle: "Open the Cloudflare dashboard",
        Steps: CloudflareAccountIDSteps);

    public static readonly CredentialRequest CloudflareAccountIDHelp = new(
        Name: "cloudflareAccountIDHelp",
        Title: "Where to find your Account ID",
        Explanation: "Cloudflare gives every account a 32-character ID, and it says which account your class websites are published into. " +
                     "It identifies you rather than a class, so you enter it once here and every course published to Cloudflare uses it.",
        FieldLabel: "Account ID",
        IsSecret: false,
        LinkAddress: "https://dash.cloudflare.com",
        LinkTitle: "Open the Cloudflare dashboard",
        Steps: CloudflareAccountIDSteps);

    public static readonly CredentialRequest TeacherSurname = new(
        Name: "teacherSurname",
        Title: "Teacher Surname",
        Explanation: "Your surname is used to create a clear, recognizable web address for your students and families (such as mcv4u-s1-2026-gordon), " +
                     "and to prevent naming conflicts with other classes. It is saved on this computer and only asked once.",
        FieldLabel: "Surname",
        IsSecret: false,
        LinkAddress: "",
        LinkTitle: "",
        Steps:
        [
            "Type your surname below using letters only (for example, “Gordon”).",
            "It will be combined with course codes and the school year to name your class websites."
        ]);

    public static readonly CredentialRequest SiteName = new(
        Name: "siteName",
        Title: "Choose a Website Address",
        Explanation: "Every website published to Netlify (*.netlify.app) or Cloudflare Pages (*.pages.dev) needs a unique web address. " +
                     "On Netlify, this name is shared globally with all users across the world.",
        FieldLabel: "Website address",
        IsSecret: false,
        LinkAddress: "",
        LinkTitle: "",
        Steps:
        [
            "Standard address (recommended): <course>-s<section>-<year>-<surname> (e.g. mcv4u-s1-2026-gordon)",
            "With school abbreviation: <school>-<course>-s<section>-<year>-<surname> (e.g. lcs-mcv4u-s1-2026-gordon)",
            "Use only lowercase letters, numbers, and hyphens."
        ]);

    public static readonly CredentialRequest SiteNameConflict = new(
        Name: "siteNameConflict",
        Title: "Website Address Already Taken",
        Explanation: "That website address is already in use by another site on Netlify. You can add a number suffix or include your school's initials to make it unique.",
        FieldLabel: "Website address",
        IsSecret: false,
        LinkAddress: "",
        LinkTitle: "",
        Steps:
        [
            "Add a number suffix (such as -01, pre-filled below).",
            "Or add your school's initials (e.g. lcs-mcv4u-s1-2026-gordon).",
            "Use only lowercase letters, numbers, and hyphens."
        ]);

    public static CredentialRequest? MatchPrompt(string prompt)
    {
        string lower = prompt.ToLowerInvariant();
        if (lower.Contains("last name") || lower.Contains("surname"))
            return TeacherSurname;
        if (lower.Contains("choose a different netlify site name") || lower.Contains("different netlify site name"))
            return SiteNameConflict;
        if (lower.Contains("enter netlify site name") || lower.Contains("netlify site name") || lower.Contains("website name"))
            return SiteName;
        if (lower.Contains("netlify") && (lower.Contains("token") || lower.Contains("personal access")))
            return NetlifyToken;
        if (lower.Contains("cloudflare") && (lower.Contains("account id") || lower.Contains("account")))
            return CloudflareAccountID;
        if (lower.Contains("cloudflare") && lower.Contains("token"))
            return CloudflareToken;
        return null;
    }
}
