"""
The teacher's own domain for one destination of one section (#904).

contracts/file-formats.json -> customDomainReading is the rule and its cases,
and courseConfigKeys -> custom_domains the shape: `custom_domains.sections.
section<N>` is a map keyed by destination TYPE (`netlify`,
`cloudflare_pages`), or, in the OLDER shape written before a course could
have more than one destination, a bare string that belongs to the PRIMARY
destination (`deploy_target`, Netlify when it is absent) and to no other.

Before #904 build_site.py read this itself, and differently from deploy.py's
own reader (#799's `leg_custom_domain`, which now asks this module too) and
both apps: it applied a bare
string to a course whose primary destination is a folder, which has no site
address, and it raised on an entry that was a list or a number, which every
other reader treats as no domain. One function now answers for every Python
caller.

Pure stdlib; imported by build_site.py by bare name, so it is baked into the
website builder beside it (Dockerfile).
"""

# Destination types that have a site address. A folder on this computer has
# none (file-formats.json: "never `local_folder`, which has no domain
# concept"), so no shape of the setting ever gives it one.
DESTINATION_TYPES_WITH_AN_ADDRESS = ("netlify", "cloudflare_pages")

# What an absent deploy_target means (PublishingDestinations.whenTheKeyIsAbsent
# on the mac).
PRIMARY_WHEN_THE_KEY_IS_ABSENT = "netlify"


def primary_destination_type(config) -> str:
    """The course's primary destination type, as its settings say it."""
    if not isinstance(config, dict):
        return PRIMARY_WHEN_THE_KEY_IS_ABSENT
    value = config.get("deploy_target")
    if isinstance(value, str) and value:
        return value
    return PRIMARY_WHEN_THE_KEY_IS_ABSENT


def for_destination(config, section_number, destination_type: str) -> str:
    """The domain the course's settings give `destination_type` for this
    section, exactly as stored, or "" when they give it none.

    Every shape the format does not describe (a list, a number, a map whose
    value is not a string, a `sections` that is not a map) is no domain,
    never an error: a build must not stop over a setting it cannot use."""
    if destination_type not in DESTINATION_TYPES_WITH_AN_ADDRESS:
        return ""
    if not isinstance(config, dict):
        return ""
    custom_domains = config.get("custom_domains")
    if not isinstance(custom_domains, dict):
        return ""
    sections = custom_domains.get("sections")
    if not isinstance(sections, dict):
        return ""
    entry = sections.get(f"section{section_number}")
    value = None
    if isinstance(entry, dict):
        value = entry.get(destination_type)
    elif isinstance(entry, str):
        if primary_destination_type(config) == destination_type:
            value = entry
    if not isinstance(value, str):
        return ""
    return value
