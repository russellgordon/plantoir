import Foundation

/// The first deploy of a section stops on one line: "Paste Netlify token:".
///
/// That line is the whole question a teacher used to be asked. It names
/// something they have never heard of, does not say where to get it, and
/// arrives in a dialog with a text field and a Send button — so the honest
/// answer to it is "I have no idea". This turns those three requests into
/// something that can be acted on without leaving the app: what the
/// credential is for, the numbered steps that produce one, and the page to
/// get it from as a LINK the teacher clicks.
///
/// **The link is a link, never an automatic browser tab.** The launchers used
/// to `open` the page themselves the moment they asked. A browser jumping in
/// front of the app, unasked, reads as something going wrong rather than as
/// help — so the address is offered and the teacher decides when to follow it.
struct CredentialRequest: Equatable {

    // MARK: - Stored properties

    /// Which credential this is, so the interface can tell them apart
    /// without matching on wording.
    var name: String

    /// The dialog's title.
    var title: String

    /// Why this is being asked at all, in one short paragraph.
    var explanation: String

    /// What to do, in order.
    var steps: [String]

    /// What the link says.
    var linkTitle: String

    /// Where the link goes.
    var linkAddress: URL?

    /// The label beside the field the answer is typed into.
    var fieldLabel: String

    /// The placeholder text inside the field when empty.
    var fieldPlaceholder: String

    /// True when the answer is a secret and must not be shown as it is
    /// typed. A token is; an account's ID is not.
    var isSecret: Bool

    // MARK: - Computed properties

    /// Netlify's personal access token, asked for the first time a section
    /// is deployed there.
    static var netlifyToken: CredentialRequest {
        return CredentialRequest(
            name: "netlifyToken",
            title: "Connect to Netlify",
            explanation: "Netlify hosts this section's website for free, and it needs to know that "
                       + "the deploys are coming from you. It does that with an access token — a "
                       + "long code that acts like a password made just for this app. Creating one "
                       + "takes about a minute, and you will not be asked again: it is saved "
                       + "securely on this computer.",
            steps: [
                "Open the Netlify page linked below, and sign in if you are asked to.",
                "Choose “New access token”.",
                "Describe it as something you will recognise later, such as “Class websites”.",
                "Change the expiry — it starts at 7 days. A token that expires stops your "
                    + "deploys working, with nothing on screen to say why, so set a date "
                    + "after the end of your school year: next July is a safe choice. Choose "
                    + "“No expiration” instead if it is offered.",
                "Choose “Generate token”, then copy the long code Netlify shows you — it is only shown once.",
                "Paste it below.",
            ],
            linkTitle: "Open Netlify’s access tokens page",
            linkAddress: URL(string: "https://app.netlify.com/user/applications#personal-access-tokens")!,
            fieldLabel: "Netlify token",
            fieldPlaceholder: "Paste it here",
            isSecret: true
        )
    }

    /// Cloudflare's API token, asked for the first time a section is
    /// deployed to Cloudflare Pages.
    static var cloudflareToken: CredentialRequest {
        return CredentialRequest(
            name: "cloudflareToken",
            title: "Connect to Cloudflare",
            explanation: "Cloudflare hosts this section's website for free, and it needs to know that "
                       + "the deploys are coming from you. It does that with an API token — a long "
                       + "code that acts like a password made just for this app. Creating one takes "
                       + "about two minutes, and you will not be asked again: it is saved securely on "
                       + "this computer.",
            steps: [
                "Open the Cloudflare page linked below, and sign in if you are asked to.",
                "Choose “Create Token”, then “Create Custom Token”.",
                "Name it something you will recognise later, such as “Class websites”.",
                "Give it one permission, chosen from the three dropdowns: Account, then "
                    + "Cloudflare Pages, then Edit.",
                "Under “Account Resources”, choose “Include” and then your own account by "
                    + "name. A token that names no account cannot deploy anything, and what "
                    + "you get back if you skip this does not mention accounts at all.",
                "Under “TTL”, set the end date to after the end of your school year — next "
                    + "July is a safe choice — or leave it with no end date. An expired token "
                    + "stops your deploys working, with nothing on screen to say why.",
                "Choose “Continue to summary”, then “Create Token”.",
                "Copy the long code Cloudflare shows you — it is only shown once — and paste it below.",
            ],
            linkTitle: "Open Cloudflare’s API tokens page",
            linkAddress: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!,
            fieldLabel: "Cloudflare token",
            fieldPlaceholder: "Paste it here",
            isSecret: true
        )
    }

    /// Where an Account ID is found. Written once and used by both of the
    /// requests below, because they differ only in why they are asking:
    /// two copies would drift, and the steps are the part that must not.
    static var accountIDSteps: [String] {
        return [
            "Open the Cloudflare dashboard linked below, and sign in if you are asked to.",
            "Choose “Workers & Pages” from the list on the left.",
            "Find “Account ID” on the right-hand side, and copy it.",
            "Paste it below. (It is also the long code in your browser's address bar, "
                + "just after dash.cloudflare.com/.)",
        ]
    }

    /// Cloudflare's account ID, asked only when the token cannot say which
    /// account it belongs to.
    static var cloudflareAccountID: CredentialRequest {
        return CredentialRequest(
            name: "cloudflareAccountID",
            title: "One more thing from Cloudflare",
            explanation: "The token you just made is allowed to deploy, but not to look up which "
                       + "Cloudflare account it belongs to — so the account's ID is needed as well. "
                       + "This is the only time you will be asked for it.",
            steps: CredentialRequest.accountIDSteps,
            linkTitle: "Open the Cloudflare dashboard",
            linkAddress: URL(string: "https://dash.cloudflare.com")!,
            fieldLabel: "Account ID",
            fieldPlaceholder: "Paste it here",
            isSecret: false
        )
    }

    /// The same instructions, shown because the TEACHER asked for them —
    /// the button beside the Account ID field in Course Settings and in the
    /// new-course wizard.
    ///
    /// A separate request rather than a flag on the one above, because the
    /// two are asking at opposite moments and only the WHY differs. The
    /// launcher's version arrives mid-deploy and explains itself as "one
    /// more thing"; this one is opened by somebody filling in a form who
    /// has quite reasonably no idea what a Cloudflare account ID is, and
    /// may not have made a token yet — so it must not talk about the token
    /// they just made.
    static var cloudflareAccountIDHelp: CredentialRequest {
        return CredentialRequest(
            name: "cloudflareAccountIDHelp",
            title: "Where to find your Account ID",
            explanation: "Cloudflare gives every account a 32-character ID, and it says which "
                       + "account your class websites are deployed into. It identifies you "
                       + "rather than a class, so you enter it once here and every course "
                       + "deployed to Cloudflare uses it.",
            steps: CredentialRequest.accountIDSteps,
            linkTitle: "Open the Cloudflare dashboard",
            linkAddress: URL(string: "https://dash.cloudflare.com")!,
            fieldLabel: "Account ID",
            fieldPlaceholder: "Paste it here",
            isSecret: false
        )
    }

    /// The teacher's surname, asked once per working folder on a first deploy
    /// so that website addresses can be built automatically.
    static var teacherSurname: CredentialRequest {
        return CredentialRequest(
            name: "teacherSurname",
            title: "Teacher Surname",
            explanation: "Your surname is used to create a clear, recognizable web address for your "
                       + "students and families (such as mcv4u-s1-2026-gordon), and to prevent naming "
                       + "conflicts with other classes. It is saved on this computer and only asked once.",
            steps: [
                "Type your surname below using letters only (for example, “Gordon”).",
                "It will be combined with course codes and the school year to name your class websites.",
            ],
            linkTitle: "",
            linkAddress: nil,
            fieldLabel: "Surname",
            fieldPlaceholder: "e.g. Gordon",
            isSecret: false
        )
    }

    /// The website address (subdomain), asked the first time a section is deployed.
    static var siteName: CredentialRequest {
        return CredentialRequest(
            name: "siteName",
            title: "Choose a Website Address",
            explanation: "Every website deployed to Netlify (*.netlify.app) or Cloudflare Pages "
                       + "(*.pages.dev) needs a unique web address. On Netlify, this name is shared "
                       + "globally with all users across the world.",
            steps: [
                "Standard address (recommended): <course>-s<section>-<year>-<surname> (e.g. mcv4u-s1-2026-gordon)",
                "With school abbreviation: <school>-<course>-s<section>-<year>-<surname> (e.g. lcs-mcv4u-s1-2026-gordon)",
                "Use only lowercase letters, numbers, and hyphens.",
            ],
            linkTitle: "",
            linkAddress: nil,
            fieldLabel: "Website address",
            fieldPlaceholder: "e.g. mcv4u-s1-2026-gordon",
            isSecret: false
        )
    }

    /// Prompted when the chosen website address is already taken on Netlify.
    static var siteNameConflict: CredentialRequest {
        return CredentialRequest(
            name: "siteNameConflict",
            title: "Website Address Already Taken",
            explanation: "That website address is already in use by another site on Netlify. You can "
                       + "add a number suffix or include your school's initials to make it unique.",
            steps: [
                "Add a number suffix (such as -01, pre-filled below).",
                "Or add your school's initials (e.g. lcs-mcv4u-s1-2026-gordon).",
                "Use only lowercase letters, numbers, and hyphens.",
            ],
            linkTitle: "",
            linkAddress: nil,
            fieldLabel: "Website address",
            fieldPlaceholder: "e.g. mcv4u-s1-2026-gordon-01",
            isSecret: false
        )
    }

    /// Every request there is, so a test can walk them.
    static var all: [CredentialRequest] {
        return [
            CredentialRequest.netlifyToken,
            CredentialRequest.cloudflareToken,
            CredentialRequest.cloudflareAccountID,
            CredentialRequest.cloudflareAccountIDHelp,
            CredentialRequest.teacherSurname,
            CredentialRequest.siteName,
            CredentialRequest.siteNameConflict,
        ]
    }

    // MARK: - Functions

    /// The request a launcher's one-line prompt is asking for, or nil when
    /// it is asking something ordinary that the plain dialog handles.
    ///
    /// Matched on the words that name the credential rather than on the
    /// whole line, because the same prompt is worded slightly differently
    /// by the two launchers and neither wording is worth pinning.
    static func matching(_ question: String) -> CredentialRequest? {
        let wording: String = question.lowercased()
        if wording.contains("last name") || wording.contains("surname") {
            return CredentialRequest.teacherSurname
        }
        if wording.contains("choose a different netlify site name") || wording.contains("different netlify site name") {
            return CredentialRequest.siteNameConflict
        }
        if wording.contains("enter netlify site name") || wording.contains("netlify site name") || wording.contains("website name") {
            return CredentialRequest.siteName
        }
        if wording.contains("netlify") && (wording.contains("token") || wording.contains("personal access")) {
            return CredentialRequest.netlifyToken
        }
        if wording.contains("cloudflare") && (wording.contains("account id") || wording.contains("account")) {
            return CredentialRequest.cloudflareAccountID
        }
        if wording.contains("cloudflare") && wording.contains("token") {
            return CredentialRequest.cloudflareToken
        }
        return nil
    }
}
